#!/bin/sh
# FreshTomato for Xiaomi R2D - installer. Run as root on the STOCK firmware booted from slot 1
# (os1 + rootfs1), from the directory with the unpacked release:
#   cd /tmp/freshtomato-r2d-XXXX && sh install.sh [--no-tftp] [--yes]
#
# Writes:  os0 (kernel) and rootfs0 (UBI, volume "ftroot").  Leaves os1 + rootfs1 (stock) untouched,
#          so stock stays available: run uninstall.sh from FreshTomato (or set flag_last_success=1).
# Flags:   flag_last_success=0 (CFE boots os0), try_failed flags cleared.
#          --no-tftp also switches off flag_tftp_bootup (CFE then does not wait ~20 s for a TFTP server).
set -e
cd "$(dirname "$0")"

TRX=r2d-ft-os0.trx
UBI=r2d-ft-rootfs.ubi
NOTFTP=0; YES=0
for a in "$@"; do
	case "$a" in
		--no-tftp) NOTFTP=1 ;;
		--yes|-y) YES=1 ;;
		*) echo "usage: sh install.sh [--no-tftp] [--yes]"; exit 1 ;;
	esac
done

die() { echo "ERROR: $*"; exit 1; }

echo "== checks"
[ "$(id -u)" = 0 ] || die "run as root"
MODEL=$(nvram get model 2>/dev/null)
[ "$MODEL" = "R2D" ] || die "this is not a Xiaomi R2D (nvram model='$MODEL')"
for t in ubiformat ubiattach ubidetach mtd md5sum dd nvram; do
	command -v $t >/dev/null 2>&1 || die "tool '$t' not found - is this the stock firmware?"
done
[ -f /proc/xiaomi/model ] || [ -d /usr/share/xiaoqiang ] || [ -f /etc/config/xiaoqiang ] || \
	die "this does not look like the stock firmware; to update FreshTomato, boot stock first (uninstall.sh)"

# the FreshTomato kernel has this partition table built in: refuse any router whose flash differs
MTD_EXPECTED='mtd0: 00080000 00020000 "boot"
mtd1: 00080000 00020000 "nvram"
mtd2: 00040000 00020000 "board_data"
mtd3: 00040000 00020000 "crash"
mtd4: 00080000 00020000 "rsvd0"
mtd5: 00400000 00020000 "os0"
mtd6: 00400000 00020000 "os1"
mtd7: 00600000 00020000 "rsvd1"
mtd8: 08000000 00020000 "rootfs0"
mtd9: 08000000 00020000 "rootfs1"
mtd10: 0f000000 00020000 "overlay"'
if [ "$(grep '^mtd' /proc/mtd)" != "$MTD_EXPECTED" ]; then
	echo "Flash partitions of this router:"; cat /proc/mtd
	die "unexpected flash layout - this build supports only the stock R2D layout (see README)"
fi
OS0=5; RFS0=8
for m in $OS0 $RFS0; do
	f=/sys/class/mtd/mtd$m/writesize
	[ ! -f $f ] || [ "$(cat $f)" = 2048 ] || die "unexpected NAND page size $(cat $f) on mtd$m (need 2048)"
done

# never overwrite the slot we are running from
[ "$(nvram get flag_boot_rootfs)" = "1" ] || \
	die "stock is running from slot 0 (flag_boot_rootfs=$(nvram get flag_boot_rootfs)); boot slot 1 first:
       nvram set flag_last_success=1; nvram commit; reboot"
for u in /sys/class/ubi/ubi[0-9]*; do
	[ -f "$u/mtd_num" ] || continue
	if [ "$(cat "$u/mtd_num")" = "$RFS0" ]; then
		grep -q "^ubi${u##*ubi}:" /proc/mounts && die "rootfs0 is mounted (${u##*/}) - not running from slot 1?"
		echo "   detaching ${u##*/} (rootfs0)"
		ubidetach -m "$RFS0" || ubidetach -d "${u##*ubi}" || die "cannot detach rootfs0"
	fi
done

echo "== verify release files"
[ -f md5sums ] || die "md5sums missing"
for f in $TRX $UBI; do
	want=$(grep " $f\$" md5sums | cut -d' ' -f1)
	have=$(md5sum $f | cut -d' ' -f1)
	[ -n "$want" ] && [ "$want" = "$have" ] || die "$f: checksum mismatch (download again)"
done
[ "$(dd if=$TRX bs=4 count=1 2>/dev/null)" = "HDR0" ] || die "$TRX is not a TRX image"
TRXLEN=$(wc -c < $TRX)
[ "$TRXLEN" -le 4194304 ] || die "$TRX is larger than os0"

echo
echo "About to write FreshTomato $(cat VERSION 2>/dev/null):"
echo "   $TRX -> mtd$OS0 (os0)"
echo "   $UBI -> mtd$RFS0 (rootfs0)"
echo "Stock firmware in os1/rootfs1 is kept. Do NOT power off the router during the next minutes."
if [ $YES = 0 ]; then
	printf "Type YES to continue: "; read ans; [ "$ans" = "YES" ] || die "cancelled"
fi

echo "== write rootfs0"
ubiformat /dev/mtd$RFS0 -f $UBI -y -q || die "ubiformat failed - stock is still active (flags not changed)"
echo "   verifying rootfs0"
D=9
ubiattach -m $RFS0 -d $D -O 2048 >/dev/null || die "cannot attach the written rootfs0 - stock is still active (flags not changed)"
V=/tmp/r2d-verify; mkdir -p $V
if mount -t ubifs -o ro ubi$D:ftroot $V; then
	OKR=1; [ -x $V/sbin/rc ] && [ -x $V/sbin/preinit ] && [ -f $V/usr/lib/libshared.so ] || OKR=0
	umount $V
else
	OKR=0
fi
ubidetach -d $D || true
[ $OKR = 1 ] || die "written rootfs0 does not mount or is incomplete - stock is still active (flags not changed)"
echo "   rootfs0 OK"

echo "== write os0"
mtd write $TRX os0 || die "writing os0 failed - stock is still active (flags not changed)"
BLK=$(( (TRXLEN + 4095) / 4096 ))
got=$(dd if=/dev/mtd$OS0 bs=4096 count=$BLK 2>/dev/null | md5sum | cut -d' ' -f1)
[ "$got" = "$(md5sum < $TRX | cut -d' ' -f1)" ] || die "os0 readback mismatch - stock is still active (flags not changed)"
echo "   os0 readback OK"

echo "== switch boot slot"
nvram set flag_last_success=0
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
[ $NOTFTP = 1 ] && nvram set flag_tftp_bootup=off
nvram commit

echo
echo "Done. Reboot now:  reboot"
echo "FreshTomato will be at http://192.168.1.1 (LAN)."
echo "If it does not come up within ~3 minutes, power-cycle the router; to go back to stock see uninstall.sh / README."
