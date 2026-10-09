# binwalk v2 for Windows

This is a modified version of binwalk v2 that allows it to run on Windows without requiring any additional software.

Extraction is primarily handled through 7-Zip (command-line version). However, formats that the original binwalk extracts using the Python standard library or its own built-in code continue to be handled that way (with 7-Zip used as a fallback if extraction fails). Unsupported formats that cannot be extracted by either method are silently skipped, even when `-e` is specified.

* **Requirements:** Python 3.8 or later (no additional pip packages required)

## Installation

1. Install Python 3.8 or later from https://www.python.org/downloads/windows/ and check **"Add python.exe to PATH"** in the installer.
2. Double-click **`install.bat`** in this folder (or run it from Command Prompt).

   * It automatically runs `pip install`, detects 7-Zip, and performs self-tests, including ZIP/GZIP extraction and skipping unsupported formats.
3. Open a new Command Prompt and start using binwalk.

```
binwalk firmware.bin            Scan for signatures
binwalk -e firmware.bin         Extract (using 7-Zip)
binwalk -eM firmware.bin        Extract and recursively scan extracted files
binwalk -eM -C C:\out fw.bin    Specify the output directory
py -3 -m binwalk firmware.bin   (If the binwalk command is not found)
```

To uninstall, run `uninstall.bat`.

### Running Without Installation (Portable Mode)

You can run `binwalk.bat` directly from this folder (e.g., `binwalk.bat -e firmware.bin`).

You can verify that it works by running `selftest.py` (`py -3 selftest.py`).

## 7-Zip Location

Binwalk uses `7z.exe` (along with `7z.dll`) located in the `7-Zip` directory inside the binwalk package.

* Source location: `src\binwalk\7-Zip\`
* After installation: `<Python>\Lib\site-packages\binwalk\7-Zip\`
* To use `7z.exe` from another location, set the `BINWALK_7Z` environment variable to its full path.
* If 7-Zip cannot be found, extraction with `-e` will stop with an error indicating where it was expected.

## Supported and Skipped Formats

### Extracted Using the Python Standard Library or Built-in Code

These formats are handled the same way as in the original binwalk, before attempting extraction with 7-Zip.

gzip / xz / lzma (7-Zip fallback on failure), zlib, raw deflate (`-X`), raw LZMA (`-Z`), Arcadyan obfuscated firmware, D-Link ROMFS, PFS, Windows CE images

### Extracted Using 7-Zip

Rules are defined in `src\binwalk\config\extract.conf`.

| Format                                                                | Output                                                                                                            |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| bzip2 / compress (Z) (also used as a fallback for gzip / xz / lzma)   | Decompressed files directly under `_<filename>.extracted\`                                                        |
| zip / 7z / tar / rar / arj / lha / cab / xar / rpm / dmg / iso / cpio | Directories such as `zip-root`, `7z-root`, `tar-root`, etc.                                                       |
| SquashFS / CramFS / EXT / QCOW / VMDK (VMware 4)                      | Directories such as `squashfs-root`, `cramfs-root`, `ext-root`, etc. (their contents are not recursively scanned) |
| Intel HEX                                                             | `.ihex` files are converted to binary using 7-Zip                                                                 |

### Detection Only

The following formats are detected but skipped during extraction. No data is carved out, no directories are created, and no warnings are issued.

| Category                                 | Formats                                                                                                                                           |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Compression                              | LZ4, LZO / lzop, lzip, rzip / lrzip, Snappy, StuffIt, AFX, KGB, pack200                                                                           |
| Archives                                 | InstallShield CAB, JAR (ARJ Software), multi-volume ZIP, BFF (AIX), BSA, Borg, GNU tar incremental, HPACK, JAM, LBR, PAR                          |
| Filesystems                              | JFFS2, UBI / UBIFS, YAFFS, romfs, Minix, BSD 2.x, QNX (IFS/4/6), EFS2, MPFS, TROC, WDK, Wind River, Foscam, Netboot, VMware 3 disks, DOS Emulator |
| SquashFS variants that 7-Zip cannot open | DD-WRT signed variants, non-standard signatures, older LZMA-based variants, etc. (only the carved `0.squashfs` file is retained)                  |
| Formats requiring external libraries     | Hilink (pycrypto), PGP (gnupg) — disabled                                                                                                         |
| Other                                    | Motorola S-Record, uImage / TRX / Android bootimg / DTB and other firmware components (no extraction rules existed in the original version)       |

7-Zip exit codes **0 (success)** and **1 (warning, e.g., extra data at the end of carved data)** are both treated as successful extraction.

### Formats 7-Zip Can Open but Binwalk Does Not Detect

Binwalk has no built-in signatures for the following formats, so it will not detect them even if they are embedded in firmware:

ZSTD (standalone), NTFS, FAT, GPT/MBR, VHD/VHDX, VDI, WIM, HFS, CHM, NSIS, MSI, Base64

You can still open an entire file directly with 7-Zip to inspect these formats. Support can be added by defining the appropriate signatures and extraction rules.

## Disabled Features (Removing Third-Party Dependencies)

* **External tools:** All references to external tools have been removed from `extract.conf`, including gzip / tar / unzip / jar / unsquashfs / sasquatch / cramfsck / jefferson / ubi_reader / yaffshiv / srec_cat / lzop / unrar / cabextract / tsk_recover / mount, and others.
* **Plugins** (`DISABLED_SYSTEM_PLUGINS` in `core\plugin.py`): Only `hilink` (requires pycrypto) and `pgp` (requires python-gnupg) are disabled.

  * The `cpio` plugin retains its duplicate-extraction prevention logic, but extraction now uses 7-Zip instead of the external `cpio` command.
* **Disassembly (`-Y`)** (capstone), entropy graph plotting (matplotlib), and the use of numpy / numba have been removed.

  * Numeric output from `-E` still works using pure Python. Use `-F` if performance is too slow.

## Windows Compatibility Fixes

* Fixed raw deflate / raw LZMA extraction code that did not work under Python 3 due to mixed `str` and `bytes` types and `/` division.
* Replaced POSIX-style command-line parsing, which broke backslashes in paths such as `C:\...`, with Windows-compatible parsing. Paths containing spaces are also supported.
* Resolved the issue where `extract.conf` could not represent paths such as `C:\...` because `:` is used as a delimiter, by introducing the `%7z` placeholder.
* Prevented stdin from being passed to 7-Zip, avoiding password prompts that could otherwise hang on encrypted archives.
* Fixed `core\version.py` so binwalk no longer crashes when run directly from the source tree without being installed.
* Fixed console-width detection (which depended on `fcntl`), improved character encoding handling so characters that cannot be converted using encodings such as cp932 do not cause crashes, and added wildcard expansion for `*.bin` (which is not performed by cmd or PowerShell).
* Updated `setup.py` to remove dependencies on `distutils` (removed in Python 3.12) and the Unix-only `which` command, and to include the `7-Zip` directory in the package.
* Normalized absolute extraction paths to help prevent recursive extraction from stopping due to case differences in Windows paths.
* Improved startup behavior in environments where the user configuration directory cannot be created.
* The root privilege check (`--run-as`) has no effect on Windows and does not interfere with operation.

## Known Limitations

* **Symbolic links:** 7-Zip itself neutralizes dangerous links. On Windows, links are generally not created, so they do not normally pose a practical risk.
* **ISO:** The signature is located 32 KB before the actual data, so 7-Zip may be unable to open the carved fragment. The original `.iso` file can still be opened directly with `7z x`.
* **Extraction rule syntax:** The existing format remains unchanged: `regex:extension:command:success_codes:recursive`. Custom rules can also be defined using `-D`. Prefixing a command with `%7z` uses the bundled copy of 7-Zip.


# Original README

![Build Status](https://github.com/OSPG/binwalk/actions/workflows/test.yml/badge.svg)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://GitHub.com/OSPG/binwalk/graphs/commit-activity)
[![GitHub license](https://img.shields.io/github/license/OSPG/binwalk.svg)](https://github.com/OSPG/binwalk/blob/master/LICENSE)

Binwalk is a fast, easy to use tool for analyzing, reverse engineering, and extracting firmware images.

### EOL notice

This fork was born to fix some outsanding issues with binwalk v2 and generally to keep it in good shape. It served his purpose helping users and distro packagers alike. However, given the original author recently rewrote binwalk in rust and is in active development again, there is no need to maintain binwalk v2 anymore. Users and contributors should migrate to binwalk v3. This new version also provides a library in Rust, see https://github.com/ReFirmLabs/binwalk/wiki/Using-the-Rust-Library.

As a result, **this repository will effectively be EOL at 12/12/2025**, at which point this repository may be archived or removed.

-----

### Important notice

This is a fork of the original code from ReFirmLabs. This fork is maintained by the community and there is no relation between the maintainers of this fork and the original authors or the original company (though we greatly appreciate their work). 

If you want to contribute feel free to open issues, pull requests, or even ask to be added to the repository to help with reviewing and merging PR. 

### Alternative software

There seems to exist a well-maintained alternative called [unblob](https://unblob.org/). According to some reports it has better extraction capabilities (are able to extract more data and faster). The downside is that it doesn't detect as much filetypes as binwalk. Another important difference is the number of dependencies: while binwalk doesn't require any dependency (they are optional), unblob depends on almost 20 packages.

### *** Extraction Security Notice ***

Prior to Binwalk v2.3.3, extracted archives could create symlinks which point anywhere on the file system, potentially resulting in a directory traversal attack if subsequent extraction utilties blindly follow these symlinks. More generically, Binwalk makes use of many third-party extraction utilties which may have unpatched security issues; Binwalk v2.3.3 and later allows external extraction tools to be run as an unprivileged user using the `run-as` command line option (this requires Binwalk itself to be run with root privileges). Additionally, Binwalk v2.3.3 and later will refuse to perform extraction as root unless `--run-as=root` is specified.

### Installation and Usage

* [Installation](./INSTALL.md)
* [API](./API.md)
* [Supported Platforms](https://github.com/OSPG/binwalk/wiki/Supported-Platforms)
* [Getting Started](https://github.com/OSPG/binwalk/wiki/Quick-Start-Guide)
* [Binwalk Command Line Usage](https://github.com/OSPG/binwalk/wiki/Usage)
* [Binwalk IDA Plugin Usage](https://github.com/OSPG/binwalk/wiki/Creating-Custom-Plugins)

More information on [Wiki](https://github.com/OSPG/binwalk/wiki)

### Windows (7-Zip build)

This tree is a Windows-friendly build that extracts exclusively through the bundled 7-Zip (`src/binwalk/7-Zip`). See [INSTALL_WINDOWS.md](./INSTALL_WINDOWS.md).
