#!/bin/bash
# Build FreshTomato images for Xiaomi R2D from an already built FreshTomato-ARM tree
# (patches 0001..0006 applied, "make r1do" done once, kernel config from kernel-config.diff).
#
# usage: r2d-mkimage.sh <src-rt-6.x.4708 dir> <output dir> [version]
#
# Produces in <output dir>:
#   r2d-ft-os0.trx      kernel + boot initramfs, for mtd "os0"
#   r2d-ft-rootfs.ubi   UBI image (volume "ftroot", UBIFS) for mtd "rootfs0"
#   install.sh, uninstall.sh, md5sums, VERSION
#   freshtomato-r2d-<version>.tar.gz   all of the above
set -euo pipefail

T=$(readlink -f "$1")
mkdir -p "$2"
OUT=$(readlink -f "$2")
VER=${3:-$(date +%Y%m%d)}
HERE=$(dirname "$(readlink -f "$0")")
PORT=$(dirname "$HERE")

export PATH=$T/toolchains/hndtools-arm-uclibc-7.5/usr/bin:$PATH
S=arm-brcm-linux-uclibcgnueabi-strip
L=$T/linux/linux-2.6.36
KV=2.6.36.4brcmarm

for t in mkfs.ubifs ubinize python3 $S; do command -v $t >/dev/null || { echo "missing tool: $t"; exit 1; }; done
[ -d "$T/router/arm-uclibc/target" ] || { echo "no router/arm-uclibc/target - run the full build first"; exit 1; }

mkdir -p "$OUT"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "== boot initramfs"
# kernel .config: CONFIG_INITRAMFS_SOURCE points to $IR/initramfs.list;
# $IR must also contain busybox (static, see config/busybox-initramfs.config) and lib/modules/et.ko
IR=$(sed -n 's/^CONFIG_INITRAMFS_SOURCE="\(.*\)\/initramfs.list"/\1/p' "$L/.config")
[ -n "$IR" ] && [ -x "$IR/busybox" ] && [ -f "$IR/lib/modules/et.ko" ] || { echo "initramfs dir '$IR' incomplete"; exit 1; }
install -m 0755 "$PORT/initramfs/init" "$IR/init"
sed "s#/root/r2d-initramfs#$IR#g" "$PORT/initramfs/initramfs.list" > "$IR/initramfs.list"
rm -f "$L"/usr/initramfs_data.cpio* "$L"/usr/initramfs_data.*o

echo "== rebuild libshared, rc, kernel"
make -C "$T/router" shared >"$W/shared.log" 2>&1 || { tail -30 "$W/shared.log"; exit 1; }
make -C "$T/router" rc >"$W/rc.log" 2>&1 || { tail -30 "$W/rc.log"; exit 1; }
make -C "$T/router" kernel >"$W/kernel.log" 2>&1 || { tail -30 "$W/kernel.log"; exit 1; }

echo "== stage rootfs"
R=$W/rootfs
cp -a "$T/router/arm-uclibc/target" "$R"
install -m 0500 "$T/router/rc/rc" "$R/sbin/rc"; $S "$R/sbin/rc"
ln -sf rc "$R/sbin/r2dfan"
install -m 0755 "$T/router/shared/libshared.so" "$R/usr/lib/libshared.so"; $S "$R/usr/lib/libshared.so"
M=$R/lib/modules/$KV/kernel
n=0
for k in $(cd "$M" && find . -name '*.ko'); do
	if [ -f "$L/$k" ]; then cp "$L/$k" "$M/$k"; $S --strip-debug "$M/$k"; n=$((n+1)); fi
done
echo "   refreshed $n kernel modules"
# crc16 is built into the kernel (needed by UBIFS)
rm -f "$M/lib/crc16.ko"
sed -i -e '/^kernel\/lib\/crc16.ko:/d' -e 's# kernel/lib/crc16.ko##' "$R/lib/modules/$KV/modules.dep"
grep -q R2D "$R/usr/lib/libshared.so" || { echo "libshared has no R2D support - patches not applied?"; exit 1; }
echo "$VER" > "$R/rom/r2d-version"

echo "== rootfs -> UBIFS -> UBI"
# NAND: 128 KiB PEB, 2 KiB page, stock UBI layout without subpages (VID header @2048 -> LEB 126976)
# rootfs0 = 1024 PEB; leave room for bad-block reserve and the layout volume
mkfs.ubifs -r "$R" -m 2048 -e 126976 -c 1000 -x lzo -F -o "$W/rootfs.ubifs"
cat > "$W/ubi.cfg" <<EOF
[ftroot]
mode=ubi
image=$W/rootfs.ubifs
vol_id=0
vol_type=dynamic
vol_name=ftroot
vol_flags=autoresize
EOF
ubinize -o "$OUT/r2d-ft-rootfs.ubi" -m 2048 -p 128KiB -s 2048 -O 2048 "$W/ubi.cfg"

echo "== kernel -> TRX"
"$T/ctools/objcopy" -O binary -R .note -R .note.gnu.build-id -R .comment -S "$L/vmlinux" "$W/piggy"
"$T/ctools/lzma_4k" e "$W/piggy" "$W/vmlinuz" >/dev/null 2>&1
python3 "$HERE/trx.py" build "$W/vmlinuz" "$OUT/r2d-ft-os0.trx"
python3 "$HERE/trx.py" check "$OUT/r2d-ft-os0.trx" || { echo "TRX check failed"; exit 1; }
[ "$(stat -c %s "$OUT/r2d-ft-os0.trx")" -le $((4 * 1024 * 1024)) ] || { echo "TRX does not fit os0 (4 MiB)"; exit 1; }

echo "== bundle"
install -m 0755 "$HERE/install.sh" "$HERE/uninstall.sh" "$OUT/"
echo "$VER" > "$OUT/VERSION"
(cd "$OUT" && md5sum r2d-ft-os0.trx r2d-ft-rootfs.ubi install.sh uninstall.sh VERSION > md5sums)
D=freshtomato-r2d-$VER
rm -rf "$W/$D"; mkdir "$W/$D"
(cd "$OUT" && cp r2d-ft-os0.trx r2d-ft-rootfs.ubi install.sh uninstall.sh VERSION md5sums "$W/$D/")
tar -C "$W" -czf "$OUT/$D.tar.gz" "$D"
ls -l "$OUT"
