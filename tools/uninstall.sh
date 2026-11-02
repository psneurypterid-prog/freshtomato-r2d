#!/bin/sh
# FreshTomato for Xiaomi R2D - go back to the stock firmware kept in os1/rootfs1.
# Run as root on FreshTomato:  sh uninstall.sh [--yes]
# Only nvram boot flags are changed; FreshTomato stays in os0/rootfs0, so install.sh (from stock)
# or "nvram set flag_last_success=0; nvram commit" (from stock) brings it back.
set -e
[ "$(nvram get model)" = "R2D" ] || { echo "ERROR: not a Xiaomi R2D"; exit 1; }
if [ "$1" != "--yes" ] && [ "$1" != "-y" ]; then
	printf "Switch to the stock firmware (os1) and reboot? Type YES: "; read ans
	[ "$ans" = "YES" ] || { echo "cancelled"; exit 1; }
fi
nvram set flag_last_success=1
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram commit
echo "Rebooting into stock. Stock web UI: http://192.168.31.1"
sleep 2
reboot
