# FreshTomato for Xiaomi Mi Router R2D

Unofficial port of [FreshTomato-ARM](https://bitbucket.org/pedro311/freshtomato-arm) to the **Xiaomi Mi Router R2D**
(小米路由器 / "Mi Router" 2015, BCM4709, 512 MB NAND, built-in 1 TB HDD).
Not to be confused with the R1D (FreshTomato already supports it) or the R3D ("Mi Router HD").

*Русская версия ниже.*

## Status

Tested on one router with stock ROM 2.25.209. Use at your own risk.

| Works | Notes |
|---|---|
| LAN / WAN, both radios (5 GHz BCM4352, 2.4 GHz BCM43217) | stock MACs and radio calibration kept |
| Internal HDD | automounted as `/tmp/mnt/sda1` (Samba, MiniDLNA, FTP built in) |
| Fan | native controller `r2dfan`, same curve as stock (thermal sensor + tach) |
| Stock firmware | kept in the second slot, one command to go back |
| Entware | built-in `entware-install.sh` (armv7sf-k2.6 repo, frozen since 2024) |

Not supported: upgrading from the FreshTomato web UI. To upgrade, go back to stock and run the new `install.sh`
(FreshTomato settings live in nvram and are kept).

## How it works

The router has two firmware slots: `os0`+`rootfs0` and `os1`+`rootfs1`; the bootloader picks one by the nvram flag
`flag_last_success`. The installer writes FreshTomato into slot 0 (kernel TRX into `os0`, UBIFS rootfs into
`rootfs0`) and leaves stock in slot 1 untouched. Bootloader, nvram layout, calibration data and slot 1 are
read-only for the FreshTomato kernel.

## Install

You need root SSH on the stock firmware.

1. **Unlock SSH.** Bind the router to a Mi account, log in at <https://d.miwifi.com/rom/ssh>, note the root password
   and download `miwifi_ssh.bin`. Put it into the root of a FAT32 USB stick, power the router off, insert the stick,
   hold Reset, power on, release Reset when the LED blinks yellow. (Worked on the stable ROM despite the page saying
   "developer ROM only".)
2. **Copy the release** (`freshtomato-r2d-<version>.tar.gz` from Releases) onto the internal HDD (e.g. via the stock
   Samba share; on stock it is `/userdisk/data`) or a USB stick (then use its mount point from `mount`).
3. **Run the installer** over SSH (`ssh root@192.168.31.1`; old dropbear may need
   `-o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa`):
   ```sh
   cd /tmp && tar xzf /userdisk/data/freshtomato-r2d-*.tar.gz
   sh freshtomato-r2d-*/install.sh      # type YES
   reboot
   ```
   If stock currently runs from slot 0, the installer refuses and prints the command to switch to slot 1 first.
   It also refuses if the flash partition table differs from the stock R2D one (the FreshTomato kernel has it built in).
   The slot is switched only after the kernel in `os0` has been read back and the new rootfs mounted and checked.
4. After ~1 minute: **http://192.168.1.1**, login `root` / `admin` — **change the password**.
   Wi-Fi: `FreshTomato24` / `FreshTomato50` with the Wi-Fi password you had on stock (open if stock Wi-Fi had none;
   a band whose stock security cannot be carried over is switched off instead).
   **The router address changes** from 192.168.31.1 to 192.168.1.1, and **WAN starts as DHCP**: with PPPoE / L2TP
   set up the WAN in Basic → Network first.

## Go back to stock

From FreshTomato: `sh uninstall.sh` (in the release archive), or
`nvram set flag_last_success=1; nvram commit; reboot`.

## Recovery

- If the FreshTomato rootfs is missing or cannot be mounted, the boot initramfs starts a rescue telnet shell on
  `192.168.1.1` (LAN, no password) for 10 minutes, then reboots.
- The bootloader (CFE) does not verify signatures. With nvram `flag_tftp_bootup=on` it tries to RAM-boot
  `192.168.1.2:vmlinuz` over TFTP on every boot (costs ~20 s when no server answers); with `boot_wait=on` it
  *flashes* a TRX served there. The installer's `--no-tftp` option switches `flag_tftp_bootup` off.
- Stock USB recovery only works while stock is the active slot.

## Build

Base: FreshTomato-ARM `arm-master`, commit `437139c980fec983ce9b09b1cac1c4336dd519e5`, toolchain
`hndtools-arm-uclibc-7.5` from the same tree (needs a host with glibc ≥ 2.38, e.g. Debian 13).

1. Apply `patches/0001…0004, 0006, 0007` with `git apply` in the FreshTomato tree and run `make r1do` once.
2. Static busybox for the initramfs: copy `release/src-rt-6.x.4708/router/busybox` elsewhere, apply
   `patches/0005-busybox-ubiattach-O.patch` (`patch -p1`), use `config/busybox-initramfs.config`, build with the same toolchain.
3. Initramfs directory (default `/root/r2d-initramfs`): the static `busybox` and `lib/modules/et.ko`
   (from `linux/linux-2.6.36/drivers/net/et/`, `strip --strip-debug`).
4. Kernel config: apply the changes from `config/kernel-config.diff` (UBI/UBIFS built in, `INITRAMFS_SOURCE`,
   `CRASHLOG`).
5. `tools/r2d-mkimage.sh <tree>/release/src-rt-6.x.4708 <outdir> <version>` → TRX, UBI image and release archive.

| Patch | What |
|---|---|
| 0001 | kernel: R2D NAND partition table, stock partitions read-only |
| 0002 | kernel: keep the custom initramfs in the `MFG_WAR` build pass |
| 0003 | robo switch: VLAN fallback for the Xiaomi nvram (no `vlanNvid`) |
| 0004 | rc/shared: R2D as a variant of R1D (interfaces, MACs, Wi-Fi security from stock keys, HDD coldplug, cleanup of Xiaomi provisioning AP) |
| 0005 | busybox: `ubiattach -O` (VID header offset 2048, as stock formats it) |
| 0006 | rc: native fan controller `r2dfan` (LM75 over bit-banged I²C, PWM, tachometer) |
| 0007 | pppd: clear `pppdb` after `tdb_close()` in the forked child (upstream fix 2026-09-28); without it PPPoE WAN redials in a loop with "Fatal signal 11" |

Releases up to r6 are built without 0007: with a PPPoE WAN they need a pppd rebuilt with it.

## License

GPL-2.0, like FreshTomato and the Linux kernel.

---

# FreshTomato для Xiaomi Mi Router R2D

Неофициальный порт FreshTomato-ARM на **Xiaomi Mi Router R2D** (2015, BCM4709, NAND 512 МБ, встроенный HDD 1 ТБ).
Не путать с R1D (его FreshTomato поддерживает официально) и R3D (Mi Router HD).

Проверено на одном роутере со стоковой 2.25.209. Всё на свой риск.

**Что работает:** LAN/WAN, оба радио, встроенный HDD (автомонтирование, Samba/MiniDLNA/FTP),
вентилятор (свой контроллер `r2dfan`, кривая как в стоке), Entware через `entware-install.sh`.
Сток остаётся во втором слоте. Обновление из веб-интерфейса FreshTomato не поддерживается:
вернуться на сток и запустить `install.sh` новой версии (настройки в nvram сохраняются).

**Установка:**
1. Получить SSH на стоке: привязать роутер к Mi-аккаунту, на <https://d.miwifi.com/rom/ssh> взять root-пароль
   и `miwifi_ssh.bin`, положить его в корень флешки FAT32, выключить роутер, вставить флешку, держать Reset,
   включить питание, отпустить при жёлтом мигании.
2. Положить архив релиза на встроенный HDD (например, через Samba стока) или на флешку.
3. По SSH (`ssh root@192.168.31.1`):
   ```sh
   cd /tmp && tar xzf /userdisk/data/freshtomato-r2d-*.tar.gz
   sh freshtomato-r2d-*/install.sh      # ввести YES
   reboot
   ```
4. Через ~минуту: **http://192.168.1.1**, вход `root` / `admin` — **сменить пароль**.
   Wi-Fi `FreshTomato24` / `FreshTomato50` с паролем от стока.
   **Адрес роутера меняется** с 192.168.31.1 на 192.168.1.1, **WAN стартует как DHCP**: при PPPoE / L2TP сначала
   настроить WAN в Basic → Network.
   В релизах до r6 включительно PPPoE уходит в бесконечный редиал (pppd падает с «Fatal signal 11»):
   нужен pppd, пересобранный с патчем 0007.

**Вернуть сток:** `sh uninstall.sh` из FreshTomato или `nvram set flag_last_success=1; nvram commit; reboot`.

**Восстановление:** при сломанном rootfs initramfs поднимает telnet без пароля на 192.168.1.1 (LAN) на 10 минут.
Загрузчик подписи не проверяет: при `flag_tftp_bootup=on` пробует загрузить ядро по TFTP с 192.168.1.2.

Сборка и список патчей — в английской части выше.
