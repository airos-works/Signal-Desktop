#!/bin/bash
# Copyright 2026 air/OS contributors
# SPDX-License-Identifier: AGPL-3.0-only
#
# Builds Signal Desktop for air/OS (Haiku) on Linux and stages it for packaging:
#   scripts/haiku/build.sh [stage directory]      (default: release/haiku)
# Run after `pnpm install --frozen-lockfile --ignore-scripts` with the Node.js
# of .nvmrc. The JavaScript is the same on every architecture: the stage holds
# the app as electron-builder would pack it (without Electron and without the
# native modules) and the packaging files; scripts/haiku/cross.sh adds the
# native modules for x86_64 or arm64 and makes the package.
# SKIP_COMPILE=1 stages the bundles already built. See scripts/haiku/README.md.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
STAGE=${1:-$ROOT/release/haiku}
HAIKU=$ROOT/scripts/haiku

cd "$ROOT"
# Builds expire 90 days after their commit (scripts/get-expire-time.mjs).
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git show -s --format=%ct 2>/dev/null || date +%s)}
export SIGNAL_ENV=production
if [[ ${SKIP_COMPILE:-0} != 1 ]]; then
	# What `pnpm install` would have built: the workspace's own packages.
	pnpm --filter @signalapp/types run build
	pnpm --filter @signalapp/windows-ucv run build
	pnpm run build:acknowledgments
	# `pnpm run generate`, step by step: npm-run-all runs npm, which refuses
	# this repository's devEngines. The database schema document is left out
	# (it needs Linux's native modules and is not part of the app).
	# SIGNAL_AIROS=1: rolldown also builds the main window's preload for
	# Aurora (scripts/haiku/rolldown.preload.ts).
	export SIGNAL_AIROS=1
	for step in build:protobuf build:emoji-data build:rolldown:prod build:icu-types \
			build:compact-locales build:styles:prod get-expire-time build:policy-files; do
		pnpm run "$step"
	done
	pnpm --dir sticker-creator run build
fi

rm -rf "$STAGE"
APP=$STAGE/app
mkdir -p "$APP"
# electron-builder's "files" (package.json "build"), without Electron's parts.
cp package.json "$APP/"
mkdir -p "$APP/config"
cp config/default.json config/production.json config/local-production.json "$APP/config/"
cp -a bundles "$APP/"
cp background.html about.html screenShare.html pdf.html permissions_popup.html \
	debug_log.html loading.html call_diagnostic.html "$APP/"
for page in background about screenShare pdf permissions_popup debug_log loading call_diagnostic; do
	[[ -f $APP/$page.html ]] || { echo "missing $page.html" >&2; exit 1; }
done
# The other windows' pages load classic scripts (rolldown.preload.ts
# airosDom): WebKit runs no ES module scripts from file: pages.
for page in "$APP"/*.html; do
	sed -i -E 's#<script type="module" src="bundles/dom/([A-Za-z]+)\.js"></script>#<script defer src="bundles/dom-haiku/\1.js"></script>#' "$page"
	! grep -q 'type="module"' "$page" || { echo "$page still loads an ES module" >&2; exit 1; }
	for script in $(grep -o 'bundles/dom-haiku/[A-Za-z]*\.js' "$page"); do
		[[ -f $APP/$script ]] || { echo "no $script for $page: build with SIGNAL_AIROS=1" >&2; exit 1; }
	done
done
mkdir -p "$APP/_locales"
(cd build/compact-locales && find . -name values.json -o -name keys.json | cpio -pdm --quiet "$APP/_locales")
mkdir -p "$APP/stylesheets"
cp stylesheets/*.css "$APP/stylesheets/"
cp -a images fonts "$APP/"
mkdir -p "$APP/sounds"
find sounds -maxdepth 1 -type f -exec cp {} "$APP/sounds/" \;
mkdir -p "$APP/build/icons/png"
cp build/icons/png/512x512.png "$APP/build/icons/png/"
for file in available-locales locale-display-names country-display-names dns-fallback \
		optional-resources jumbomoji emoji-data; do
	cp "build/$file.json" "$APP/build/"
done
mkdir -p "$APP/sticker-creator"
cp -a sticker-creator/dist "$APP/sticker-creator/"
! grep -q 'type="module"' "$APP/sticker-creator/dist/index.html" \
	|| { echo "the sticker creator still loads an ES module: build with SIGNAL_AIROS=1" >&2; exit 1; }
# The package.json electron-builder writes: the environment of the build.
node -e '
const fs = require("fs");
const file = process.argv[1];
const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
pkg.environment = "production";
delete pkg.devDependencies; delete pkg.scripts; delete pkg.build;
fs.writeFileSync(file, JSON.stringify(pkg, null, 2) + "\n");
' "$APP/package.json"
# The main window's preload for Aurora, in one file (rolldown.preload.ts).
[[ -f $APP/bundles/preload/haiku.js ]] || { echo "no bundles/preload/haiku.js: build with SIGNAL_AIROS=1" >&2; exit 1; }
node "$HAIKU/stage-modules.mjs" "$APP"
# RingRTC's native module is WebRTC, which Haiku has none of: its stand-in
# (also in the page's preload) for the main process and its workers.
cp "$HAIKU/files/ringrtc-native.js" "$APP/node_modules/@signalapp/ringrtc/dist/ringrtc/Native.js"

# What cross.sh uses.
cp -a "$HAIKU/files" "$STAGE/files"
cp LICENSE "$STAGE/LICENSE"
node -p 'require("./package.json").version' > "$STAGE/VERSION"
echo "Staged $(cat "$STAGE/VERSION") in $STAGE"
