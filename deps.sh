#!/bin/bash

# Binwalk dependencies installer
# Updated for Ubuntu 24.04 LTS compatibility (Python 3.12)

set -eu
set -o nounset

# ---------------------------------------------------------------------------
# Distro detection
# ---------------------------------------------------------------------------
if ! which lsb_release > /dev/null 2>&1; then
    lsb_release() {
        if [ -f /etc/os-release ]; then
            [[ "$1" = "-i" ]] && grep ^"ID=" /etc/os-release | cut -d= -f2 | tr -d '"'
            [[ "$1" = "-r" ]] && grep "VERSION_ID" /etc/os-release | cut -d= -f2 | tr -d '"'
        elif [ -f /etc/lsb-release ]; then
            [[ "$1" = "-i" ]] && grep "DISTRIB_ID" /etc/lsb-release | cut -d= -f2
            [[ "$1" = "-r" ]] && grep "DISTRIB_RELEASE" /etc/lsb-release | cut -d= -f2
        else
            echo Unknown
        fi
    }
fi

distro="$(lsb_release -i 2>/dev/null | cut -f2 || echo Unknown)"
distro_version="$(lsb_release -r 2>/dev/null | cut -f2 | cut -c1-2 || echo 00)"

# ---------------------------------------------------------------------------
# Package list
# Notes:
#   - python3-distutils removed (gone in Python 3.12; python3-setuptools provides shim)
#   - p7zip / p7zip-full are transitional stubs in Ubuntu 24.04 — use 7zip directly
#   - cramfsswap removed (not in Ubuntu 24.04 repos)
#   - lhasa provides the `lha` binary
# ---------------------------------------------------------------------------
APT_CANDIDATES="
    7zip arj build-essential bzip2 cabextract clang cmake cpio
    curl device-tree-compiler dmg2img git gzip lhasa
    liblzma-dev liblzo2-dev liblz4-dev libucl-dev
    locales lz4 lzop mtd-utils
    python3-setuptools python3-matplotlib python3-capstone
    python3-pycryptodome python3-gnupg python3-pytest python3-pytest-cov
    pipx squashfs-tools sleuthkit srecord tar unyaffs unrar unzip
    wget xz-utils zlib1g-dev zstd
"

# ---------------------------------------------------------------------------
# Privilege handling
# ---------------------------------------------------------------------------
if [ "$UID" -eq 0 ]; then
    echo "Running as root — sudo not required."
    SUDO=""
else
    SUDO="sudo -E"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
find_path() {
    printf "checking for %s..." "$1"
    if which "$1" > /dev/null 2>&1; then
        echo "yes"
        return 0
    else
        echo "no"
        return 1
    fi
}

# Resolve pipx venv bin directory reliably across versions
pipx_venv_bin() {
    local pkg="$1"
    local venvs_dir
    # pipx >= 1.x stores venvs in ~/.local/share/pipx/venvs
    venvs_dir="${HOME}/.local/share/pipx/venvs"
    echo "${venvs_dir}/${pkg}/bin"
}

ensure_in_path() {
    local bin_path="$1"
    if [ -d "$bin_path" ]; then
        $SUDO ln -sf "${bin_path}"/* /usr/local/bin/ 2>/dev/null || true
    fi
}

# Install a pipx package, skipping silently if it is already present.
# Usage: pipx_install <venv-name> <install-source>
#   venv-name      : name of the directory under ~/.local/share/pipx/venvs/
#   install-source : argument passed to `pipx install` (PyPI name, git URL, local path)
pipx_install() {
    local venv_name="$1"
    local install_src="$2"
    local venv_dir="${HOME}/.local/share/pipx/venvs/${venv_name}"

    if [ -d "$venv_dir" ]; then
        echo "pipx: ${venv_name} already installed — skipping."
        return 0
    fi
    pipx install "$install_src"
}

# ---------------------------------------------------------------------------
# Individual installers (all use subshells so `cd` can never strand the script)
# ---------------------------------------------------------------------------
install_yaffshiv() {
    (
        cd /tmp
        # Skip clone+install if pipx venv already exists
        if [ -d "${HOME}/.local/share/pipx/venvs/yaffshiv" ]; then
            echo "pipx: yaffshiv already installed — skipping."
            return 0
        fi
        rm -rf yaffshiv
        git clone --quiet --depth 1 --branch master https://github.com/devttys0/yaffshiv
        pipx install ./yaffshiv || echo "WARNING: yaffshiv install had issues"
        rm -rf yaffshiv
    )
}

install_sasquatch_deb() {
    # Install sasquatch from onekey-sec prebuilt deb (easiest for Ubuntu 24.04)
    local arch
    arch=$(dpkg --print-architecture)

    # Fetch the latest release tag dynamically instead of hardcoding a version
    local release_url latest_tag
    release_url="https://api.github.com/repos/onekey-sec/sasquatch/releases/latest"
    latest_tag=$(curl -fsSL "$release_url" | grep '"tag_name"' | head -1 | cut -d'"' -f4 2>/dev/null || echo "")

    if [ -z "$latest_tag" ]; then
        echo "Could not determine latest sasquatch release tag."
        return 1
    fi

    local deb_url="/tmp/sasquatch_1.0.deb"
    echo "Downloading sasquatch ${latest_tag} (${arch}) from onekey-sec..."
    curl -fsSL -o "$deb_url" \
        "https://github.com/onekey-sec/sasquatch/releases/download/${latest_tag}/sasquatch_1.0_${arch}.deb" || {
        echo "Failed to download sasquatch deb."
        rm -f "$deb_url"
        return 1
    }

    $SUDO dpkg -i "$deb_url"
    rm -f "$deb_url"
    echo "sasquatch installed successfully."
}

install_sasquatch_themactep() {
    echo "Installing sasquatch from themactep fork..."
    (
        cd /tmp
        rm -rf sasquatch
        git clone --quiet --depth 1 https://github.com/themactep/sasquatch.git
        (cd sasquatch && ./build.sh) || echo "WARNING: sasquatch (themactep) build had issues"
        rm -rf sasquatch
    )
}

install_sasquatch_devttys0() {
    echo "Installing sasquatch from devttys0 + PR#56..."
    (
        cd /tmp
        rm -rf sasquatch
        git clone --quiet --depth 1 https://github.com/devttys0/sasquatch
        (
            cd sasquatch
            git fetch origin pull/56/head:pr56 2>/dev/null || true
            if git checkout pr56 2>/dev/null; then
                ./build.sh
            else
                echo "PR #56 not available — applying CFLAGS workaround..."
                export CFLAGS="-fcommon -Wno-error"
                ./build.sh
            fi
        ) || echo "WARNING: sasquatch (devttys0) build had issues"
        rm -rf sasquatch
    )
}

install_cramfstools() {
    (
        cd /tmp
        rm -rf cramfs-tools
        git clone --quiet --depth 1 --branch master https://github.com/npitre/cramfs-tools
        # Suppress -Wunused-result warnings from the upstream source (harmless)
        (cd cramfs-tools && make CFLAGS="-W -Wall -O2 -g -I. -Wno-unused-result" \
            && $SUDO install cramfsck /usr/local/bin/) \
            || echo "WARNING: cramfstools build had issues"
        rm -rf cramfs-tools
    )
}

install_ubi_reader() {
    pipx_install "ubi-reader" "git+https://github.com/onekey-sec/ubi_reader.git" || {
        echo "WARNING: ubi_reader pipx install had issues — trying pip fallback..."
        pip3 install git+https://github.com/onekey-sec/ubi_reader.git \
            --break-system-packages 2>/dev/null || true
    }

    if ! which ubireader_extract_files > /dev/null 2>&1; then
        echo "ubireader tools not in PATH — creating symlinks..."
        ensure_in_path "$(pipx_venv_bin ubi-reader)"
    fi
}

install_jefferson() {
    pipx_install "jefferson" "jefferson" || echo "WARNING: jefferson install had issues"

    if ! which jefferson > /dev/null 2>&1; then
        echo "jefferson not in PATH — creating symlinks..."
        ensure_in_path "$(pipx_venv_bin jefferson)"
    fi
}

install_uefi_firmware() {
    pipx_install "uefi-firmware" "uefi_firmware" || {
        echo "WARNING: uefi_firmware pipx install had issues — trying pip fallback..."
        pip3 install uefi_firmware --break-system-packages 2>/dev/null || true
    }

    if ! which uefi-firmware-parser > /dev/null 2>&1; then
        echo "uefi-firmware-parser not in PATH — creating symlinks..."
        ensure_in_path "$(pipx_venv_bin uefi-firmware)"
    fi
}

install_vmlinux_to_elf() {
    pipx_install "vmlinux-to-elf" "git+https://github.com/marin-m/vmlinux-to-elf.git" || {
        echo "WARNING: vmlinux-to-elf pipx install had issues — trying pip fallback..."
        pip3 install git+https://github.com/marin-m/vmlinux-to-elf.git \
            --break-system-packages 2>/dev/null || true
    }

    if ! which vmlinux-to-elf > /dev/null 2>&1; then
        echo "vmlinux-to-elf not in PATH — creating symlinks..."
        ensure_in_path "$(pipx_venv_bin vmlinux-to-elf)"
    fi
}

install_lzfse() {
    (
        cd /tmp
        rm -rf lzfse
        git clone --quiet --depth 1 https://github.com/lzfse/lzfse.git
        # -Wno-dev suppresses the cmake_minimum_required() dev warning in upstream CMakeLists
        (cd lzfse && mkdir -p build && cd build && cmake -Wno-dev .. && make && $SUDO make install) \
            || echo "WARNING: lzfse build had issues"
        rm -rf lzfse
    )
}

install_dumpifs() {
    # Uses a subshell so cd cannot affect the parent script
    (
        cd /tmp
        rm -rf dumpifs-linux
        git clone --quiet --depth 1 https://github.com/ttepatti/dumpifs-linux.git
        cd dumpifs-linux
        rm -f dumpifs
        # Upstream dumpifs-linux has many harmless pointer-sign and format-string
        # warnings due to old C code written for 32-bit QNX.  We cannot fix the
        # source, so silence them by injecting -w (suppress all warnings) into
        # every clang/gcc invocation in the Makefile.
        sed -i 's/^\(.*\bclang\b\)/\1 -w/g; s/^\(.*\bgcc\b\)/\1 -w/g' Makefile 2>/dev/null || true
        if make; then
            $SUDO cp ./dumpifs /usr/local/bin/dumpifs
            [ -f ./dumpifs-folderized.sh ] && $SUDO cp ./dumpifs-folderized.sh /usr/local/bin/
            echo "dumpifs installed."
        else
            echo "WARNING: dumpifs compilation failed."
        fi
        cd /tmp
        rm -rf dumpifs-linux
    )
}

# ---------------------------------------------------------------------------
# Dependency checker
# ---------------------------------------------------------------------------
check_dependencies() {
    set +e  # don't exit on failed checks

    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'

    local PASS=0 FAIL=0 WARN=0

    check_cmd() {
        local cmd="$1" desc="$2" optional="${3:-}"
        if command -v "$cmd" > /dev/null 2>&1; then
            echo -e "[${GREEN}✓${NC}] $cmd — $desc"
            PASS=$((PASS + 1))
        elif [ "$optional" = "optional" ]; then
            echo -e "[${YELLOW}○${NC}] $cmd — $desc (optional)"
            WARN=$((WARN + 1))
        else
            echo -e "[${RED}✗${NC}] $cmd — $desc"
            FAIL=$((FAIL + 1))
        fi
    }

    check_pymod() {
        local mod="$1" desc="$2"
        if python3 -c "import $mod" 2>/dev/null; then
            echo -e "[${GREEN}✓${NC}] python3-$mod — $desc"
            PASS=$((PASS + 1))
        else
            echo -e "[${RED}✗${NC}] python3-$mod — $desc"
            FAIL=$((FAIL + 1))
        fi
    }

    check_lib() {
        local lib="$1" desc="$2"
        if ldconfig -p 2>/dev/null | grep -q "$lib" \
            || [ -f "/usr/lib/$lib" ] \
            || [ -f "/usr/local/lib/$lib" ]; then
            echo -e "[${GREEN}✓${NC}] $lib — $desc"
            PASS=$((PASS + 1))
        else
            echo -e "[${RED}✗${NC}] $lib — $desc"
            FAIL=$((FAIL + 1))
        fi
    }

    echo ""
    echo "========================================"
    echo "  Binwalk Dependencies Checker"
    echo "========================================"

    echo ""
    echo "--- Core Extraction Tools ---"
    # 7zip ships two binaries: 7zz (native) and 7z (wrapper)
    if command -v 7zz > /dev/null 2>&1 || command -v 7z > /dev/null 2>&1; then
        echo -e "[${GREEN}✓${NC}] 7zip — 7-Zip (archives, ISO, CPIO)"
        PASS=$((PASS + 1))
    else
        echo -e "[${RED}✗${NC}] 7zip — 7-Zip (archives, ISO, CPIO)"
        FAIL=$((FAIL + 1))
    fi
    check_cmd unzip   "ZIP extraction"
    check_cmd tar     "TAR archive extraction"
    check_cmd gzip    "GZIP decompression"
    check_cmd bzip2   "BZIP2 decompression"
    check_cmd xz      "XZ/LZMA decompression"
    check_cmd lzop    "LZO decompression"
    check_cmd lz4     "LZ4 decompression"
    check_cmd zstd    "Zstandard decompression"
    check_cmd cpio    "CPIO archive extraction"

    echo ""
    echo "--- Filesystem Extraction ---"
    check_cmd sasquatch              "SquashFS (non-standard)"
    check_cmd unsquashfs             "SquashFS (standard)"
    check_cmd jefferson              "JFFS2 filesystem"
    check_cmd ubireader_extract_images "UBI image extraction"
    check_cmd ubireader_extract_files  "UBIFS extraction"
    check_cmd yaffshiv               "YAFFS filesystem"
    check_cmd unyaffs                "YAFFS2 filesystem"
    check_cmd cramfsck               "CramFS filesystem"

    echo ""
    echo "--- Firmware Tools ---"
    check_cmd uefi-firmware-parser "UEFI/BIOS firmware"
    check_cmd vmlinux-to-elf       "Linux kernel symbols"
    check_cmd dumpifs              "QNX IFS images"
    check_cmd dmg2img              "Apple DMG images"
    check_cmd lzfse                "Apple LZFSE compression"

    echo ""
    echo "--- Additional Extractors ---"
    check_cmd cabextract "Microsoft Cabinet"
    check_cmd unrar      "RAR archives"
    check_cmd arj        "ARJ archives"
    check_cmd lha        "LHA/LZH archives"   # provided by lhasa package
    check_cmd srec_cat   "Motorola S-record"
    check_cmd tsk_recover "Filesystem recovery"
    check_cmd dtc        "Device Tree Compiler"

    echo ""
    echo "--- Build Tools ---"
    check_cmd gcc   "GNU C Compiler"
    check_cmd make  "GNU Make"
    check_cmd cmake "CMake"
    check_cmd git   "Git"

    echo ""
    echo "--- Python Modules ---"
    check_pymod capstone   "Disassembly framework"
    check_pymod matplotlib "Entropy graphs"
    check_pymod gnupg      "GPG support"
    # PyCryptodome can expose itself as either Cryptodome or Crypto
    if python3 -c "import Cryptodome" 2>/dev/null \
        || python3 -c "import Crypto" 2>/dev/null; then
        echo -e "[${GREEN}✓${NC}] python3-pycryptodome — Encryption"
        PASS=$((PASS + 1))
    else
        echo -e "[${RED}✗${NC}] python3-pycryptodome — Encryption"
        FAIL=$((FAIL + 1))
    fi

    echo ""
    echo "--- Libraries ---"
    check_lib liblzo2.so  "LZO compression"
    check_lib liblz4.so   "LZ4 compression"
    check_lib liblzfse.so "Apple LZFSE"

    echo ""
    echo "--- MTD/Flash Utilities ---"
    check_cmd nanddump    "NAND flash dump"
    check_cmd mkfs.jffs2  "JFFS2 creation"
    check_cmd ubinize     "UBI image creation"

    echo ""
    echo "--- Optional ---"
    check_cmd binwalk "Binwalk itself"   optional
    check_cmd strings "String extraction" optional
    check_cmd file    "File type detection" optional

    echo ""
    echo "========================================"
    echo "  Summary"
    echo "========================================"
    echo -e "  ${GREEN}Passed:${NC}   $PASS"
    echo -e "  ${RED}Failed:${NC}   $FAIL"
    echo -e "  ${YELLOW}Optional:${NC} $WARN"
    echo "========================================"

    set -e

    if [ "$FAIL" -eq 0 ]; then
        echo -e "\n${GREEN}All required dependencies installed!${NC}\n"
        return 0
    else
        echo -e "\n${RED}Some dependencies are missing. See above for details.${NC}\n"
        return 1
    fi
}

# ===========================================================================
# Main
# ===========================================================================

echo ""
echo "=== Binwalk Dependencies Installer ==="
echo ""
if [ "$distro" != "Unknown" ]; then
    echo "Detected: $distro $distro_version"
else
    echo "WARNING: Distro not detected — using apt defaults."
fi
echo ""

# Detect package manager
PKGCMD=""
if find_path apt && apt install -s -y dpkg > /dev/null 2>&1; then
    PKGCMD="apt"
elif find_path apt-get; then
    PKGCMD="apt-get"
else
    echo "ERROR: No supported package manager found (apt or apt-get required)."
    exit 1
fi

# Install system packages
# shellcheck disable=SC2086
$SUDO "$PKGCMD" install -y $APT_CANDIDATES || {
    echo "ERROR: System package installation failed."
    exit 1
}

# Make pipx-installed tools available in this shell session immediately.
# `pipx ensurepath` writes to ~/.bashrc/.profile but doesn't affect the
# current session, so we export the path explicitly as well.
pipx ensurepath 2>/dev/null || true
export PATH="${HOME}/.local/bin:${PATH}"

# ---------------------------------------------------------------------------
# Install additional tools
# ---------------------------------------------------------------------------
install_ubi_reader
install_jefferson
install_uefi_firmware

# Sasquatch: try methods in order, stop on first success
if ! install_sasquatch_deb 2>&1; then
    echo "Prebuilt deb unavailable — trying themactep fork..."
    if ! install_sasquatch_themactep 2>&1; then
        echo "themactep fork failed — trying devttys0 + PR#56..."
        install_sasquatch_devttys0
    fi
fi

install_yaffshiv
install_cramfstools
install_vmlinux_to_elf
install_lzfse
install_dumpifs

echo ""
echo "=== Installation complete ==="
echo "Restart your shell or run: source ~/.bashrc"
echo "to make pipx-installed tools (jefferson, ubi_reader, yaffshiv, etc.) available."
echo ""
echo "Running dependency check..."
echo ""

check_dependencies
