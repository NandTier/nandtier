#!/usr/bin/env bash
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# NandTier setup for Linux, macOS and Windows WSL.
#
# Downloads and installs everything the project needs into ONE folder
# (tools/ in the repository, nothing system-wide), then writes local.mk so
# that plain `make` finds it:
#
#   OSS CAD Suite   yosys, nextpnr, apicula, openFPGALoader, iverilog, gtkwave
#   RISC-V GCC      xPack riscv-none-elf-gcc
#   pyserial        for sw/nandtier-programmer.py and sw/gamepad.py
#
#   setup/setup.sh                  download what is missing, install, check
#   setup/setup.sh --download-only  only fill setup/cache/ (for a USB stick or a lab)
#   setup/setup.sh --offline        install from setup/cache/ only, no network at all
#   setup/setup.sh --check          show what is installed and build the firmware
#
# A whole class without internet: on one machine with internet run
#   setup/setup.sh --bundle                       (this OS)
#   setup/setup.sh --bundle --platform win32-x64  (for Windows PCs)
# and copy the archive it makes to the other machines; there,
# unpack it and run setup/setup.sh --offline (or setup\setup.bat -Offline).
#
# Run setup/setup.sh --help for every option. Uninstall: delete tools/ and local.mk.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

PREFIX="$ROOT/tools"
CACHE="$HERE/cache"
MODE=install          # install | download | check
OFFLINE=0
BUNDLE=0
PLATFORM=""
WANT_CAD=1
WANT_GCC=1
UDEV=ask
YES=0
RUN_TEST=1
GCC_FROM=""           # an existing toolchain to use instead of downloading one

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
	sed -n '4,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
	cat <<EOF

Options:
  --prefix DIR       install the tools here (default: $PREFIX)
  --cache DIR        keep downloaded archives here (default: $CACHE)
  --download-only    download into the cache, install nothing
  --offline          never use the network; install from the cache
  --bundle           download, then pack the repository and the cache into
                     one archive next to the repository, for offline machines
  --platform P       linux-x64, linux-arm64, darwin-x64, darwin-arm64 or
                     win32-x64 (with --download-only/--bundle: for another OS)
  --no-cad           skip the OSS CAD Suite (only build firmware)
  --no-gcc           skip the RISC-V GCC (only build bitstreams)
  --gcc DIR          use an installed RISC-V GCC (DIR/bin/<name>-gcc)
  --udev | --no-udev Linux: install USB rules for the boards (needs sudo)
  --no-test          do not build the firmware at the end
  --check            only check the installation and build the firmware
  -y, --yes          answer yes to every question
  -h, --help         this text
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--prefix) PREFIX="$2"; shift ;;
	--prefix=*) PREFIX="${1#*=}" ;;
	--cache) CACHE="$2"; shift ;;
	--cache=*) CACHE="${1#*=}" ;;
	--download-only) MODE=download ;;
	--offline) OFFLINE=1 ;;
	--bundle) MODE=download; BUNDLE=1 ;;
	--platform) PLATFORM="$2"; shift ;;
	--platform=*) PLATFORM="${1#*=}" ;;
	--no-cad) WANT_CAD=0 ;;
	--no-gcc) WANT_GCC=0 ;;
	--gcc) GCC_FROM="$2"; WANT_GCC=0; shift ;;
	--gcc=*) GCC_FROM="${1#*=}"; WANT_GCC=0 ;;
	--udev) UDEV=yes ;;
	--no-udev) UDEV=no ;;
	--no-test) RUN_TEST=0 ;;
	--check) MODE=check ;;
	-y|--yes) YES=1 ;;
	-h|--help) usage; exit 0 ;;
	*) die "unknown option $1 (see --help)" ;;
	esac
	shift
done

mkdir -p "$PREFIX" 2>/dev/null || true
PREFIX="$(cd "$PREFIX" 2>/dev/null && pwd || echo "$PREFIX")"
mkdir -p "$CACHE"
CACHE="$(cd "$CACHE" && pwd)"
LOCK="$CACHE/lock.txt"

ask() {   # ask "question" -> 0 for yes
	[ "$YES" = 1 ] && return 0
	[ -t 0 ] || return 1
	local a; read -r -p "    $1 [y/N] " a || return 1
	case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# --- which machine ------------------------------------------------------------

host_platform() {
	local s m
	s="$(uname -s)"; m="$(uname -m)"
	case "$s" in
	Linux) s=linux ;;
	Darwin) s=darwin ;;
	MINGW*|MSYS*|CYGWIN*) s=win32 ;;
	*) die "unsupported system $s" ;;
	esac
	case "$m" in
	x86_64|amd64) m=x64 ;;
	aarch64|arm64) m=arm64 ;;
	*) die "unsupported processor $m" ;;
	esac
	echo "$s-$m"
}
HOST="$(host_platform)"
[ -n "$PLATFORM" ] || PLATFORM="$HOST"
case "$PLATFORM" in
linux-x64|linux-arm64|darwin-x64|darwin-arm64|win32-x64) ;;
*) die "unknown platform $PLATFORM" ;;
esac
if [ "$PLATFORM" != "$HOST" ] && [ "$MODE" != download ]; then
	die "--platform $PLATFORM is not this machine ($HOST): use it with --download-only or --bundle"
fi
if [ "$HOST" = win32-x64 ] && [ "$MODE" != download ]; then
	die "on Windows run setup\\setup.bat (PowerShell), or use this script inside WSL"
fi

# shellcheck disable=SC1090
VERSIONS="$HERE/versions.txt"
[ -f "$VERSIONS" ] || die "missing $VERSIONS"
getv() { sed -n "s/^$1=//p" "$VERSIONS" | tr -d '\r' | head -n1; }
OSS_CAD_RELEASE="$(getv OSS_CAD_RELEASE)"
RISCV_GCC_VERSION="$(getv RISCV_GCC_VERSION)"
WIN_BUILD_TOOLS_VERSION="$(getv WIN_BUILD_TOOLS_VERSION)"
PYTHON_WIN_VERSION="$(getv PYTHON_WIN_VERSION)"
PYSERIAL_WHEEL="$(getv PYSERIAL_WHEEL)"
PYSERIAL_SHA256="$(getv PYSERIAL_SHA256)"

# --- downloading ----------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

http_get() {   # http_get URL FILE
	if have curl; then
		curl -fL --retry 3 --connect-timeout 20 --progress-bar -o "$2" "$1"
	elif have wget; then
		wget -q --show-progress -O "$2" "$1"
	else
		die "need curl or wget to download (or use --offline with a filled cache)"
	fi
}

http_text() {  # http_text URL  -> stdout
	if have curl; then curl -fsSL --retry 2 --connect-timeout 20 "$1"
	else wget -qO- "$1"; fi
}

sha256_of() {
	if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
	else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

lock_get() { [ -f "$LOCK" ] && sed -n "s/^$1=//p" "$LOCK" | tail -n1 || true; }
lock_set() {
	touch "$LOCK"
	grep -v "^$1=" "$LOCK" > "$LOCK.tmp" || true
	echo "$1=$2" >> "$LOCK.tmp"
	mv "$LOCK.tmp" "$LOCK"
}

# github_asset OWNER/REPO TAG|latest REGEX -> URL of the first matching asset
github_asset() {
	local api
	if [ "$2" = latest ]; then api="https://api.github.com/repos/$1/releases/latest"
	else api="https://api.github.com/repos/$1/releases/tags/$2"; fi
	http_text "$api" 2>/dev/null \
		| grep -o '"browser_download_url": *"[^"]*"' \
		| sed 's/.*"\(https[^"]*\)"$/\1/' \
		| grep -E "/$3\$" | head -n1 || true
}

# fetch KEY URL [SHA256]: download into the cache once; prints the file path
fetch() {
	local key="$1" url="$2" sum="${3:-}" f
	f="$CACHE/$(basename "$url")"
	if [ ! -s "$f" ]; then
		[ "$OFFLINE" = 1 ] && die "$(basename "$f") is not in $CACHE (download it first, without --offline)"
		say "downloading $(basename "$f")" >&2
		http_get "$url" "$f.part" >&2 || { rm -f "$f.part"; die "download failed: $url"; }
		mv "$f.part" "$f"
	fi
	if [ -z "$sum" ] && [ "$OFFLINE" = 0 ] && [ ! -f "$f.sha256" ]; then
		# xPack releases publish a .sha file next to every archive
		case "$url" in *xpack*) http_text "$url.sha" 2>/dev/null | cut -d' ' -f1 > "$f.sha256" || rm -f "$f.sha256" ;; esac
		grep -qE '^[0-9a-fA-F]{64}$' "$f.sha256" 2>/dev/null || rm -f "$f.sha256"
	fi
	[ -z "$sum" ] && [ -s "$f.sha256" ] && sum="$(cat "$f.sha256")"
	if [ -n "$sum" ]; then
		[ "$(sha256_of "$f")" = "$sum" ] || { rm -f "$f"; die "checksum mismatch for $(basename "$f"), removed it: run again"; }
	fi
	lock_set "$key" "$url"
	echo "$f"
}

# resolve KEY: the URL of this component for $PLATFORM, from the lock file
# when offline (or already downloaded), otherwise from the versions.
resolve_url() {
	local key="$1" url ver plat="$PLATFORM" ext name
	url="$(lock_get "$key")"
	if [ -n "$url" ] && { [ "$OFFLINE" = 1 ] || [ -s "$CACHE/$(basename "$url")" ]; }; then
		echo "$url"; return
	fi
	[ "$OFFLINE" = 1 ] && die "no $key in $LOCK: fill the cache first (setup.sh --download-only)"
	case "$key" in
	oss-cad-$plat)
		# Windows builds are .tgz since mid 2026, a self-extracting .exe before
		[ "$plat" = win32-x64 ] && plat=windows-x64
		if [ "$OSS_CAD_RELEASE" = latest ]; then
			url="$(github_asset YosysHQ/oss-cad-suite-build latest "oss-cad-suite-$plat-[0-9]+\.(tgz|exe)")"
		else
			url="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$OSS_CAD_RELEASE/oss-cad-suite-$plat-$(echo "$OSS_CAD_RELEASE" | tr -d -).tgz"
		fi ;;
	riscv-gcc-$plat)
		ext=tar.gz; [ "$plat" = win32-x64 ] && ext=zip
		if [ "$RISCV_GCC_VERSION" = latest ]; then
			url="$(github_asset xpack-dev-tools/riscv-none-elf-gcc-xpack latest "xpack-riscv-none-elf-gcc-[0-9.]+-[0-9]+-$plat\.$ext")"
		else
			ver="$RISCV_GCC_VERSION"
			url="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$ver/xpack-riscv-none-elf-gcc-$ver-$plat.$ext"
		fi ;;
	win-build-tools)
		if [ "$WIN_BUILD_TOOLS_VERSION" = latest ]; then
			url="$(github_asset xpack-dev-tools/windows-build-tools-xpack latest "xpack-windows-build-tools-[0-9.]+-[0-9]+-win32-x64\.zip")"
		else
			ver="$WIN_BUILD_TOOLS_VERSION"
			url="https://github.com/xpack-dev-tools/windows-build-tools-xpack/releases/download/v$ver/xpack-windows-build-tools-$ver-win32-x64.zip"
		fi ;;
	python-win)
		url="https://www.python.org/ftp/python/$PYTHON_WIN_VERSION/python-$PYTHON_WIN_VERSION-embed-amd64.zip" ;;
	pyserial)
		url="$PYSERIAL_WHEEL" ;;
	*) die "internal: unknown component $key" ;;
	esac
	[ -n "$url" ] || die "could not find the $key download on GitHub (no internet, or the GitHub API limit). Pin a version in setup/versions.txt, or try again later."
	echo "$url"
}

get() {   # get KEY [SHA256] -> local archive path
	local url; url="$(resolve_url "$1")"
	fetch "$1" "$url" "${2:-}"
}

# --- download-only / bundle ----------------------------------------------------------

if [ "$MODE" = download ]; then
	say "downloading for $PLATFORM into $CACHE"
	if [ "$WANT_CAD" = 1 ]; then get "oss-cad-$PLATFORM" >/dev/null; ok "OSS CAD Suite"; fi
	if [ "$WANT_GCC" = 1 ]; then get "riscv-gcc-$PLATFORM" >/dev/null; ok "RISC-V GCC"; fi
	get pyserial "$PYSERIAL_SHA256" >/dev/null; ok "pyserial"
	if [ "$PLATFORM" = win32-x64 ]; then
		get win-build-tools >/dev/null; ok "make for Windows"
		get python-win >/dev/null; ok "Python for Windows (used only if none is installed)"
	fi
	if [ "$BUNDLE" = 1 ]; then
		out="$(dirname "$ROOT")/nandtier-offline-$PLATFORM"
		say "packing the repository and the cache"
		( cd "$(dirname "$ROOT")"
		  base="$(basename "$ROOT")"
		  ex=(--exclude="$base/tools" --exclude="$base/local.mk" --exclude="$base/env.sh"
		      --exclude="$base/env.ps1" --exclude='*/build' --exclude='__pycache__' --exclude='.git')
		  if [ "$PLATFORM" = win32-x64 ] && have zip; then
			  rm -f "$out.zip"
			  zip -qr "$out.zip" "$base" -x "$base/tools/*" "$base/local.mk" "*/build/*" "*__pycache__*" "$base/.git/*"
			  echo "$out.zip"
		  else
			  tar czf "$out.tar.gz" "${ex[@]}" "$base"
			  echo "$out.tar.gz"
		  fi ) | while read -r f; do ok "$f ($(du -h "$f" | cut -f1))"; done
		echo
		echo "Copy that archive to the other machines, unpack it, and run there:"
		if [ "$PLATFORM" = win32-x64 ]; then echo "    setup\\setup.bat -Offline"
		else echo "    setup/setup.sh --offline"; fi
	else
		echo
		echo "Done. Install on a machine without internet with:  setup/setup.sh --offline"
	fi
	exit 0
fi

# --- install ----------------------------------------------------------------------

CAD_DIR="$PREFIX/oss-cad-suite"
GCC_DIR="$PREFIX/riscv-gcc"
PYLIB="$PREFIX/pylib"

install_cad() {
	local a; a="$(get "oss-cad-$PLATFORM")"
	local stamp="$CAD_DIR/.nandtier-from"
	if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$(basename "$a")" ]; then ok "OSS CAD Suite already installed"; return; fi
	say "unpacking $(basename "$a") (about 2 GB on disk, takes a minute)"
	rm -rf "$CAD_DIR" "$PREFIX/.cad.tmp"; mkdir -p "$PREFIX/.cad.tmp"
	tar xzf "$a" -C "$PREFIX/.cad.tmp"
	mv "$PREFIX/.cad.tmp/oss-cad-suite" "$CAD_DIR"; rm -rf "$PREFIX/.cad.tmp"
	if [ "${PLATFORM%%-*}" = darwin ]; then
		xattr -dr com.apple.quarantine "$CAD_DIR" 2>/dev/null || true
	fi
	basename "$a" > "$stamp"
	ok "OSS CAD Suite in $CAD_DIR"
}

install_gcc() {
	local a; a="$(get "riscv-gcc-$PLATFORM")"
	local stamp="$GCC_DIR/.nandtier-from"
	if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$(basename "$a")" ]; then ok "RISC-V GCC already installed"; return; fi
	say "unpacking $(basename "$a")"
	rm -rf "$GCC_DIR" "$PREFIX/.gcc.tmp"; mkdir -p "$PREFIX/.gcc.tmp"
	tar xzf "$a" -C "$PREFIX/.gcc.tmp"
	mv "$PREFIX/.gcc.tmp"/xpack-riscv-none-elf-gcc-* "$GCC_DIR"; rm -rf "$PREFIX/.gcc.tmp"
	if [ "${PLATFORM%%-*}" = darwin ]; then
		xattr -dr com.apple.quarantine "$GCC_DIR" 2>/dev/null || true
	fi
	basename "$a" > "$stamp"
	ok "RISC-V GCC in $GCC_DIR"
}

pick_python() {
	local p
	for p in python3 python; do
		if have "$p" && "$p" -c 'import sys; sys.exit(sys.version_info < (3, 6))' 2>/dev/null; then
			command -v "$p"; return
		fi
	done
	for p in "$CAD_DIR/py3bin/python3" "$CAD_DIR/bin/python3"; do
		[ -x "$p" ] && { echo "$p"; return; }
	done
	echo ""
}

install_pyserial() {
	local a; a="$(get pyserial "$PYSERIAL_SHA256")"
	if [ -d "$PYLIB/serial" ]; then ok "pyserial already installed"; return; fi
	rm -rf "$PYLIB"; mkdir -p "$PYLIB"
	"$PY" -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$a" "$PYLIB"
	ok "pyserial in $PYLIB"
}

install_udev() {
	[ "${PLATFORM%%-*}" = linux ] || return 0
	grep -qi microsoft /proc/version 2>/dev/null && { ok "WSL: USB goes through usbipd (see README), no udev rules"; return; }
	local rules=/etc/udev/rules.d/99-nandtier.rules
	[ -f "$rules" ] && { ok "USB rules already installed ($rules)"; return; }
	case "$UDEV" in
	no) return 0 ;;
	ask) ask "Install USB rules so the boards work without sudo (needs sudo)?" || { warn "skipped USB rules: openFPGALoader and the UART may need sudo"; return 0; } ;;
	esac
	have sudo || { warn "no sudo: skipped USB rules"; return 0; }
	sudo tee "$rules" >/dev/null <<'EOF'
# NandTier boards (written by setup/setup.sh)
# Tang Nano 9K / 20K: the on-board debugger shows up as an FT2232 (JTAG + UART)
ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0666"
# ULX3S: FT231X
ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="0666", TAG+="uaccess"
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", MODE="0666"
EOF
	sudo udevadm control --reload-rules 2>/dev/null || true
	sudo udevadm trigger 2>/dev/null || true
	ok "USB rules in $rules (unplug and plug the board once)"
}

write_config() {
	local gcc_path="$1" gcc_name="$2" cad="$3"
	cat > "$ROOT/local.mk" <<EOF
# Written by setup/setup.sh on $(date '+%Y-%m-%d %H:%M'). Run it again to
# update, or edit by hand. A value on the make command line still wins.
RISCV_PATH  ?= $gcc_path
RISCV_NAME  ?= $gcc_name
OSS_CAD     ?= $cad
PYTHON_NAME ?= $PY
GOWIN_HOME  ?= \$(HOME)/gowin/IDE

# the tools first on PATH, for every make in the project
export PATH := $( [ -n "$cad" ] && printf '%s/bin:' "$cad")$gcc_path/bin:\$(PATH)
export PYTHONPATH := $PYLIB\$(if \$(PYTHONPATH),:\$(PYTHONPATH))
EOF
	cat > "$ROOT/env.sh" <<EOF
# NandTier tools in this shell:   source env.sh
# (written by setup/setup.sh; make does not need it, local.mk does the same)
export NANDTIER="$ROOT"
export PATH="$( [ -n "$cad" ] && printf '%s/bin:' "$cad")$gcc_path/bin:\$PATH"
export PYTHONPATH="$PYLIB\${PYTHONPATH:+:\$PYTHONPATH}"
EOF
	ok "wrote local.mk and env.sh"
}

find_existing_gcc() {   # prints "PATH NAME" of an installed RISC-V GCC, if any
	local n p
	for n in riscv-none-elf riscv-none-embed riscv64-unknown-elf riscv32-unknown-elf; do
		if have "$n-gcc"; then
			p="$(dirname "$(dirname "$(command -v "$n-gcc")")")"
			echo "$p $n"; return
		fi
	done
}

check() {
	local gcc_path="$1" gcc_name="$2" cad="$3" bad=0 v
	say "checking"
	if [ -x "$gcc_path/bin/$gcc_name-gcc" ]; then
		ok "$("$gcc_path/bin/$gcc_name-gcc" --version | head -n1)"
	else warn "no RISC-V GCC at $gcc_path/bin/$gcc_name-gcc"; bad=1; fi
	if [ -n "$cad" ]; then
		for t in yosys nextpnr-himbaechel gowin_pack openFPGALoader iverilog; do
			if [ -e "$cad/bin/$t" ]; then
				case "$t" in
				yosys|iverilog) v="$("$cad/bin/$t" -V 2>&1 | head -n1 || true)" ;;
				gowin_pack) v="" ;;
				*) v="$("$cad/bin/$t" --version 2>&1 | head -n1 || true)" ;;
				esac
				ok "$t${v:+: $v}"
			else warn "missing $cad/bin/$t"; bad=1; fi
		done
	fi
	if [ -n "$PY" ] && PYTHONPATH="$PYLIB" "$PY" -c 'import serial' 2>/dev/null; then
		ok "$("$PY" --version 2>&1) with pyserial"
	else warn "python3 with pyserial not found"; bad=1; fi
	have make && ok "$(make --version | head -n1)" || { warn "GNU make is missing: $(make_hint)"; bad=1; }

	if [ "$RUN_TEST" = 1 ] && [ "$bad" = 0 ]; then
		say "building the boot ROM, the launcher and the games (make)"
		if make -C "$ROOT" -s all >"$PREFIX/setup-build.log" 2>&1; then
			ok "firmware built: fw/fw-flash/build/fw-flash.v, fw/games/build/carts.img"
		else
			warn "the build failed, see $PREFIX/setup-build.log"; bad=1
		fi
	fi
	return $bad
}

make_hint() {
	if have apt-get; then echo "sudo apt install make"
	elif have dnf; then echo "sudo dnf install make"
	elif have pacman; then echo "sudo pacman -S make"
	elif [ "${HOST%%-*}" = darwin ]; then echo "xcode-select --install"
	else echo "install GNU make with your package manager"; fi
}

say "NandTier setup on $PLATFORM"
echo "    repository: $ROOT"
echo "    tools:      $PREFIX"
if [ "$OFFLINE" = 1 ]; then echo "    cache:      $CACHE  (offline: no downloads)"; else echo "    cache:      $CACHE"; fi

have tar || die "tar is missing"
have make || warn "GNU make is missing: $(make_hint)"

if [ "$MODE" = install ]; then
	if [ "$WANT_CAD" = 1 ]; then install_cad; fi
	if [ "$WANT_GCC" = 1 ]; then install_gcc; fi
fi

PY="$(pick_python)"
[ -n "$PY" ] || die "no Python 3 found: install python3 (or keep the OSS CAD Suite, which has one)"
if [ "$MODE" = install ]; then install_pyserial; install_udev; fi

# the toolchain to use
if [ -n "$GCC_FROM" ]; then
	n="$(ls "$GCC_FROM/bin/" 2>/dev/null | grep -E '^riscv.*-gcc$' | sed 's/-gcc$//' | head -n1 || true)"
	[ -n "$n" ] || die "no riscv*-gcc in $GCC_FROM/bin"
	GCC_PATH="$(cd "$GCC_FROM" && pwd)"; GCC_NAME="$n"
elif [ -x "$GCC_DIR/bin/riscv-none-elf-gcc" ]; then
	GCC_PATH="$GCC_DIR"; GCC_NAME=riscv-none-elf
else
	read -r GCC_PATH GCC_NAME <<<"$(find_existing_gcc)" || true
	[ -n "${GCC_PATH:-}" ] || { GCC_PATH="$GCC_DIR"; GCC_NAME=riscv-none-elf; }
fi
if [ -x "$CAD_DIR/bin/yosys" ]; then CAD="$CAD_DIR"; else CAD=""; fi

write_config "$GCC_PATH" "$GCC_NAME" "$CAD"

if check "$GCC_PATH" "$GCC_NAME" "$CAD"; then
	echo
	say "ready"
	cat <<EOF
    make                     boot ROM, launcher and games
    make fpga                the bitstream (Tang Nano 9K; BOARD=tangnano20k or ulx3s)
    make fpga-load           load it into the FPGA
    make program COMx=/dev/ttyUSB1   launcher into the flash, games onto the SD card
    make test                the test suite
    source env.sh            the tools in this shell too
EOF
else
	echo
	warn "setup finished with problems (see above)"
	exit 1
fi
