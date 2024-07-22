# Tarb, A Backup Solution for Android, With Recovery Mode Support


---
Backup/restore apps and respective data, SSAIDs, runtime permissions, system settings, Magisk modules, and more.

All required binaries/executables are included: busybox for general tools, curl for updates, openssl for encryption, tar for archiving, and zstd for compression.

**Works in recovery mode as well.**


---
## NOTICE

This program, along with all included binaries (busybox, openssl, tar and zstd), are free and open source software.
They are provided "as is", and come with absolutely no warranties.
One can do whatever they want with those programs, as long as they follow the terms of each license.

The binaries are provided by @osm0sis and @Zackptg5 -- credits to them, other contributors, and original authors.
Refer to the sources below for more information:

- https://github.com/Magisk-Modules-Repo/busybox-ndk/
- https://github.com/Zackptg5/Cross-Compiled-Binaries-Android/


---
## USAGE

`# sh /path/to/executable` prints the help text.

e.g., `# sh /sdcard/tarb-arm64`

The `-m` option installs Tarb as a Magisk/KernelSU module -- to be available system-wide, as `tarb` and `/data/t` (for recovery).


---
## BUILDING FROM SOURCE

`$ ./build.sh [o] [CPU architecture...]`

`o` is for offline build: binaries are not downloaded/updated.

`wget` with SSL/TLS support is required for downloading binaries.
Alternatively, one can download them manually.

Supported archs are ARM, ARM64, x86 and x64.

Examples:

`$ ./build.sh arm arm64`: builds for those two architectures.

`$ ./build.sh`: builds for all supported architectures.


---
## LINKS

- [Donate - Zelle: iprj25 @ gmail . com](https://enroll.zellepay.com/qr-codes?data=eyJuYW1lIjoiSVZBTkRSTyIsInRva2VuIjoiaXByajI1QGdtYWlsLmNvbSIsImFjdGlvbiI6InBheW1lbnQifQ==)
- [Donate - Airtm, username: ivandro863auzqg](https://app.airtm.com/send-or-request/send)
- [Donate - Credit/Debit Card](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=iprj25@gmail.com&lc=US&item_name=VR25+is+creating+free+and+open+source+software.+Donate+to+suppport+their+work.&no_note=0&cn=&currency_code=USD&bn=PP-DonationsBF:btn_donateCC_LG.gif:NonHosted)
- [Donate - Liberapay](https://liberapay.com/vr25)
- [Donate - Patreon](https://patreon.com/vr25)
- [Donate - PayPal Me](https://paypal.me/vr25xda)

- [Telegram Channel](https://t.me/vr25_xda)
- [Telegram Group](https://t.me/vr25_tarb)
- [Telegram Profile](https://t.me/vr25xda)

- [Upstream Repository](https://github.com/VR-25/tarb)
- [XDA Thread](https://forum.xda-developers.com/t/tarb-a-backup-solution-for-android-with-recovery-mode-support.4443801)
