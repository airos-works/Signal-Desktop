#!/bin/bash
# Copyright 2026 air/OS contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Makes the signal_desktop package for x86_64 or arm64 on Linux:
#   scripts/haiku/cross.sh ARCH [stage directory] [output directory]
# from a stage that build.sh made (the app's JavaScript, the same on every
# architecture) and the native modules native.sh built for ARCH:
#   SIGNAL_NATIVE      native.sh's output for ARCH (libsignal_client.node,
#                      node_sqlcipher.node)
#   AIROS_SDK          an air/OS cross SDK's env.sh for ARCH (CROSS, SYSROOT),
#                      default /data1/airos/sdk/ARCH/env.sh
#   HAIKU_HOST_TOOLS   a Haiku build's host tools (rc, xres, resattr, mimeset,
#                      package) and HAIKU_MIME_DB its MIME database; the
#                      tools keep attributes in that build's own store
#   AURORA_HOST_BINARY aurora-host for ARCH (the aurora package's
#                      data/aurora/aurora-host), Aurora 0.4 or later
# Prints the package's path last. The package requires aurora and Node.js 22
# or later (cmd:node).
set -euo pipefail
ARCH=${1:?usage: cross.sh x86_64|arm64 [stage directory] [output directory]}
case $ARCH in
	x86_64) NODE_ARCH=x64 ;;
	arm64) NODE_ARCH=arm64 ;;
	*) echo "unknown architecture $ARCH" >&2; exit 1 ;;
esac
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
STAGE=$(cd -- "${2:-$ROOT/release/haiku}" && pwd)
OUT=${3:-$STAGE/packages}
# (the SDK's env.sh first: it names its own build's TOOLS and MIMEDB)
. "${AIROS_SDK:-/data1/airos/sdk/$ARCH/env.sh}"
TOOLS=${HAIKU_HOST_TOOLS:?a Haiku build's objects/linux/x86_64/release/tools}
MIMEDB=${HAIKU_MIME_DB:?a Haiku build's objects/common/data/mime_db/mime_db}
HOST_BINARY=${AURORA_HOST_BINARY:?aurora-host for ARCH}
NATIVE=${SIGNAL_NATIVE:?native.sh output for ARCH}
for module in libsignal_client.node node_sqlcipher.node; do
	[[ -f $NATIVE/$module ]] || { echo "no $module in $NATIVE" >&2; exit 1; }
done
VERSION=$(cat "$STAGE/VERSION")
# The package's revision: raise it for a new package of the same version
# (pkgman does not replace an installed package with an equal version).
REVISION=1
NAME=Signal
WORK=$(mktemp -d "${TMPDIR:-/tmp}/signal-$ARCH.XXXXXX")
trap '"$TOOLS/rm_attrs" -rf "$WORK" 2>/dev/null || rm -rf "$WORK"' EXIT
PKG=$WORK/package
APP=$PKG/apps/Signal

mkdir -p "$APP" "$PKG/data/deskbar/menu/Applications" "$PKG/data/licenses"
cp -a "$STAGE/app" "$APP/app"
cp "$STAGE/files/aurora.json" "$APP/aurora.json"

echo "== Native modules ($(tr '\n' ' ' < "$NATIVE/VERSIONS" 2>/dev/null))"
# Where node-gyp-build looks: prebuilds/<platform>-<arch>. The app runs as
# Linux (AURORA_PLATFORM); a Node.js that says haiku finds the same files.
modules=$APP/app/node_modules/@signalapp
for module in libsignal-client:libsignal_client sqlcipher:node_sqlcipher; do
	package=${module%%:*}
	file=${module##*:}
	prebuilds=$modules/$package/prebuilds
	mkdir -p "$prebuilds/linux-$NODE_ARCH"
	cp "$NATIVE/$file.node" "$prebuilds/linux-$NODE_ARCH/@signalapp+$package.node"
	ln -s "linux-$NODE_ARCH" "$prebuilds/haiku-$NODE_ARCH"
done

echo "== Launcher"
cp "$HOST_BINARY" "$APP/$NAME"
"${CROSS}strip" --strip-debug "$APP/$NAME"
IFS=. read -r major middle minor <<< "${VERSION%%-*}"
sed -e "s/@MAJOR@/$major/; s/@MIDDLE@/$middle/; s/@MINOR@/${minor:-0}/; s/@VERSION@/$VERSION/" \
	"$STAGE/files/Signal.rdef.in" > "$WORK/Signal.rdef"
"$TOOLS/rc/rc" -I "$STAGE/files" -o "$WORK/launcher.rsrc" "$WORK/Signal.rdef"
"$TOOLS/xres" -o "$APP/$NAME" "$WORK/launcher.rsrc"
# on Haiku xres and mimeset give the file its attributes; here resattr does
"$TOOLS/resattr/resattr" -O -o "$APP/$NAME" "$WORK/launcher.rsrc"
(cd "$PKG" && "$TOOLS/mimeset" --all -f --mimedb "$MIMEDB" "apps/Signal/$NAME")
# Deskbar: Applications > Signal
ln -s "../../../../apps/Signal/$NAME" "$PKG/data/deskbar/menu/Applications/$NAME"
# Signal Desktop is AGPL v3; the base system has no such licence text
cp "$STAGE/LICENSE" "$PKG/data/licenses/GNU AGPL v3"

cat > "$PKG/.PackageInfo" <<INFO
name			signal_desktop
version			$VERSION-$REVISION
architecture	$ARCH
summary			"Private messaging: Signal on your desktop"
description		"Signal Desktop links to the Signal app on your phone: messages, \\
groups, stories and attachments, end-to-end encrypted. \\
This is an unofficial air/OS port: it runs on Aurora (Electron's API on \\
Node.js and the system's WebKit engine). Voice and video calls are not \\
available."
packager		"air/OS contributors"
vendor			"air/OS"
copyrights		{ "2013-2026 Signal Messenger, LLC" }
licenses		{ "GNU AGPL v3" }
urls			{ "https://github.com/airos-works/Signal-Desktop" }
provides {
	signal_desktop = $VERSION
	app:Signal = $VERSION
}
requires {
	haiku
	aurora >= 0.4
	cmd:node >= 22
}
INFO
mkdir -p "$OUT"
FILE=$OUT/signal_desktop-$VERSION-$REVISION-$ARCH.hpkg
rm -f "$FILE"
"$TOOLS/package/package" create -q -C "$PKG" "$FILE"
echo "$FILE"
