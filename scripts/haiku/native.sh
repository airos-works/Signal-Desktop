#!/bin/bash
# Copyright 2026 air/OS contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Cross-builds Signal's native modules for air/OS (Haiku) on Linux:
#   scripts/haiku/native.sh ARCH OUT      (ARCH: x86_64 or arm64)
# into OUT/libsignal_client.node and OUT/node_sqlcipher.node, from the
# sources of the versions package.json names:
#   @signalapp/libsignal-client  github.com/signalapp/libsignal, tag v<version>
#                                (Rust: the Node.js bridge, BoringSSL, tokio)
#   @signalapp/sqlcipher         github.com/signalapp/node-sqlcipher, tag
#                                v<version> (SQLCipher, its Rust crypto
#                                provider and FTS5 tokenizer, N-API glue)
# RingRTC (WebRTC) is not built: files/ringrtc-native.js stands in for it.
#
# Needs:
#   AIROS_SDK      an air/OS cross SDK's env.sh for ARCH (CROSS, SYSROOT,
#                  UNWIND_SPECS), default /data1/airos/sdk/ARCH/env.sh
#   RUST_ENV       airos-ci sdk/build-rust.sh's env-ARCH.sh: a nightly Rust
#                  with rust-src (std is built for the Haiku target here)
#   RUST_TARGET_PATH  for arm64, the directory with aarch64-unknown-haiku.json
#                  (airos-ci sdk/targets)
#   NODE_HEADERS   Node.js's headers (a node-vX-headers tarball, unpacked)
#   PROTOC         protoc 3.12 or later (libsignal's build runs it)
#   LIBCLANG_PATH  a directory with libclang.so (bindgen, for BoringSSL)
#   SIGNAL_NATIVE_WORK  sources and Cargo's build trees, kept between builds
#                  (default: release/haiku-native); CARGO_HOME, Cargo's
#                  crates (default: <work>/cargo)
set -euo pipefail
ARCH=${1:?usage: native.sh x86_64|arm64 OUT}
OUT=${2:?usage: native.sh x86_64|arm64 OUT}
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=${SIGNAL_NATIVE_WORK:-$ROOT/release/haiku-native}
. "${AIROS_SDK:-/data1/airos/sdk/$ARCH/env.sh}"
# (RUST_ENV names the toolchain's own CARGO_HOME: the crates go here instead)
CARGO_HOME=${CARGO_HOME:-$WORK/cargo}
crates=$CARGO_HOME
targets=${RUST_TARGET_PATH:-}
. "${RUST_ENV:?sdk/build-rust.sh env-ARCH.sh}"
export CARGO_HOME=$crates
# (and the caller's target directory over the one it was written with)
[[ -z $targets ]] || export RUST_TARGET_PATH=$targets
: "${NODE_HEADERS:?Node.js headers}" "${PROTOC:?protoc}" "${LIBCLANG_PATH:?a directory with libclang.so}"
export PROTOC LIBCLANG_PATH
export PATH="$(dirname "$PROTOC"):$PATH"
case $ARCH in
	x86_64|arm64) ;;
	*) echo "unknown architecture $ARCH" >&2; exit 1 ;;
esac
mkdir -p "$WORK" "$OUT"
WORK=$(cd "$WORK" && pwd)
OUT=$(cd "$OUT" && pwd)

version() {
	node -p "require('$ROOT/package.json').dependencies['$1']"
}
LIBSIGNAL_VERSION=$(version @signalapp/libsignal-client)
SQLCIPHER_VERSION=$(version @signalapp/sqlcipher)

# source <repository> <tag> <directory>: a shallow clone of the tag, once.
source_tree() {
	if [[ ! -d $3/.git ]] || [[ $(git -C "$3" describe --tags --exact-match 2>/dev/null) != "$2" ]]; then
		rm -rf "$3"
		git clone -q --depth 1 --branch "$2" "$1" "$3"
	fi
}

# The compilers with the SDK's sysroot, as commands without arguments.
BIN=$WORK/bin-$ARCH
mkdir -p "$BIN"
printf '#!/bin/sh\nexec %sgcc --sysroot=%s -specs=%s "$@"\n' "$CROSS" "$SYSROOT" "$UNWIND_SPECS" > "$BIN/haiku-cc"
printf '#!/bin/sh\nexec %sg++ --sysroot=%s -specs=%s "$@"\n' "$CROSS" "$SYSROOT" "$UNWIND_SPECS" > "$BIN/haiku-c++"
chmod 755 "$BIN/haiku-cc" "$BIN/haiku-c++"

# BoringSSL's CMake build (boring-sys) for Haiku: the target named in a
# toolchain file, so CMake never takes the build machine for it, and without
# BoringSSL's tests and benchmarks (their configure checks would run Haiku
# programs here).
TOOLCHAIN=$WORK/haiku-$ARCH.cmake
case $ARCH in
	x86_64) processor=x86_64 ;;
	arm64) processor=aarch64 ;;
esac
cat > "$TOOLCHAIN" <<CMAKE
set(CMAKE_SYSTEM_NAME Haiku)
set(CMAKE_SYSTEM_PROCESSOR $processor)
set(CMAKE_C_COMPILER $BIN/haiku-cc)
set(CMAKE_CXX_COMPILER $BIN/haiku-c++)
set(CMAKE_ASM_COMPILER $BIN/haiku-cc)
set(CMAKE_FIND_ROOT_PATH $SYSROOT)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(BUILD_TESTING OFF CACHE BOOL "no BoringSSL tests for Haiku" FORCE)
CMAKE

# Cargo for the Haiku target: std built here (a tier 3 target), linked by the
# SDK's GCC; C and C++ (BoringSSL, SQLCipher's crypto) with the same.
triple=${RUST_TARGET//-/_}
cargo_env() {
	export CARGO_UNSTABLE_BUILD_STD=std,panic_unwind
	export "CARGO_TARGET_${triple^^}_LINKER=$BIN/haiku-cc"
	export "CC_$triple=$BIN/haiku-cc" "CXX_$triple=$BIN/haiku-c++" "AR_$triple=${CROSS}ar"
	export "CMAKE_TOOLCHAIN_FILE_$triple=$TOOLCHAIN"
	# bindgen parses BoringSSL's headers for the target, with GCC's own
	# headers (stddef.h) as clang has none of its own for Haiku.
	export "BINDGEN_EXTRA_CLANG_ARGS_$triple=--sysroot=$SYSROOT --target=$RUST_TARGET -isystem $(${CROSS}gcc -print-file-name=include)"
	RUSTFLAGS=""
	if [[ $ARCH == arm64 ]]; then
		: "${RUST_TARGET_PATH:?the directory with aarch64-unknown-haiku.json}"
		export RUST_TARGET_PATH
		RUSTFLAGS="-Zunstable-options --cfg aes_armv8"
	fi
	export RUSTFLAGS
}

echo "== libsignal $LIBSIGNAL_VERSION ($ARCH)"
LIBSIGNAL=$WORK/libsignal-$LIBSIGNAL_VERSION
source_tree https://github.com/signalapp/libsignal.git "v$LIBSIGNAL_VERSION" "$LIBSIGNAL"
(
	cargo_env
	cd "$LIBSIGNAL"
	# linkme (neon's export table) places its slices with the linker's
	# __start_/__stop_ section symbols on ELF systems; its list of those does
	# not name Haiku, whose linker (GNU ld) is the same. A patched copy of
	# the locked linkme-impl replaces it ([patch.crates-io], local to this tree).
	if ! grep -q '^linkme-impl = ' Cargo.toml; then
		cargo fetch -q
		impl_version=$(awk '/^name = "linkme-impl"$/ { getline; gsub(/"/, "", $3); print $3 }' Cargo.lock)
		impl_source=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/"linkme-impl-$impl_version" | head -1)
		rm -rf haiku-linkme-impl
		cp -r "$impl_source" haiku-linkme-impl
		sed -i 's/target_os = "linux"/target_os = "linux", target_os = "haiku"/g' haiku-linkme-impl/src/declaration.rs
		[[ $(grep -c 'target_os = "haiku"' haiku-linkme-impl/src/declaration.rs) -ge 8 ]] \
			|| { echo "linkme-impl $impl_version: its platform lists changed" >&2; exit 1; }
		sed -i '/^\[patch.crates-io\]$/a linkme-impl = { path = "haiku-linkme-impl" }' Cargo.toml
	fi
	# mio before 1.2.4 makes blocking sockets on Haiku (its new_socket sets
	# O_NONBLOCK only on the systems it lists), and tokio then waits in
	# read(): the chat connection never comes up. 1.2.4 fixed that.
	mio=$(awk '/^name = "mio"$/ { getline; gsub(/"/, "", $3); print $3 }' Cargo.lock)
	if [[ $(printf '1.2.4\n%s\n' "$mio" | sort -V | head -1) != 1.2.4 ]]; then
		cargo update -q -p mio --precise 1.2.4
	fi
	# as libsignal's node/build_node_bridge.py builds it for release
	export CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_DEBUG=0
	RUSTFLAGS="$RUSTFLAGS --cfg tokio_unstable" \
		cargo build --release --target "$RUST_TARGET" -p libsignal-node \
		--features log/release_max_level_info --target-dir "$WORK/libsignal-target"
)
"${CROSS}objcopy" -S "$WORK/libsignal-target/$RUST_TARGET/release/libsignal_node.so" "$OUT/libsignal_client.node"

echo "== node-sqlcipher $SQLCIPHER_VERSION ($ARCH)"
SQLCIPHER=$WORK/node-sqlcipher-$SQLCIPHER_VERSION
source_tree https://github.com/signalapp/node-sqlcipher.git "v$SQLCIPHER_VERSION" "$SQLCIPHER"
BUILD=$WORK/sqlcipher-$ARCH
mkdir -p "$BUILD"
(
	cargo_env
	export "CFLAGS_$triple=-Wa,--noexecstack"
	cd "$SQLCIPHER/deps/extension"
	cargo build --release --target "$RUST_TARGET" --target-dir "$WORK/sqlcipher-target"
)
# node-addon-api: the version the app's lockfile installed
ADDON_API=$(node -p "const fs = require('fs'), path = require('path');
path.dirname(require.resolve('node-addon-api/package.json',
  { paths: [fs.realpathSync('$ROOT/node_modules/@signalapp/sqlcipher')] }))")
# SQLite's settings: deps/sqlcipher/sqlcipher.gyp's first 'defines' list
DEFINES=$(awk "/'defines': \\[/ { n++ } n == 1" "$SQLCIPHER/deps/sqlcipher/sqlcipher.gyp" | sed '/\]/q' \
	| grep -o "'[A-Z_][A-Za-z0-9_=-]*'" | tr -d "'" | sed 's/^/-D/' | tr '\n' ' ')
[[ $DEFINES == *SQLITE_HAS_CODEC* ]] || { echo "sqlcipher.gyp: no SQLCipher defines found" >&2; exit 1; }
# shellcheck disable=SC2086
"$BIN/haiku-cc" -O3 -fPIC -std=c99 -w -DNDEBUG $DEFINES -I"$SQLCIPHER/deps/sqlcipher" \
	-c "$SQLCIPHER/deps/sqlcipher/sqlite3.c" -o "$BUILD/sqlite3.o"
# shellcheck disable=SC2086
"$BIN/haiku-c++" -O3 -fPIC -std=c++17 -DNDEBUG -DNAPI_DISABLE_CPP_EXCEPTIONS -DNODE_ADDON_API_DISABLE_DEPRECATED \
	-fvisibility=hidden $DEFINES -I"$NODE_HEADERS/include/node" -I"$ADDON_API" -I"$SQLCIPHER/deps/sqlcipher" \
	-I"$SQLCIPHER/deps/extension/target" -I"$SQLCIPHER/src" -c "$SQLCIPHER/src/addon.cc" -o "$BUILD/addon.o"
"$BIN/haiku-c++" -shared -o "$BUILD/node_sqlcipher.node" "$BUILD/addon.o" "$BUILD/sqlite3.o" \
	"$WORK/sqlcipher-target/$RUST_TARGET/release/libsignal_sqlcipher_extension.a" \
	-Wl,-Bsymbolic -Wl,--exclude-libs,ALL -lbsd -lnetwork
"${CROSS}strip" -o "$OUT/node_sqlcipher.node" "$BUILD/node_sqlcipher.node"

printf '%s\n' "libsignal-client $LIBSIGNAL_VERSION" "sqlcipher $SQLCIPHER_VERSION" > "$OUT/VERSIONS"
ls -l "$OUT"
