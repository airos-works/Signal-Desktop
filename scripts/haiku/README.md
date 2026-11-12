# Signal Desktop on air/OS

This branch (`airos`, on upstream's release tags) builds Signal Desktop as an
air/OS (Haiku) app. It runs on [Aurora](https://github.com/airos-works/aurora),
which gives Electron apps Electron's API on Node.js and draws their windows
with Summit's WebKit engine. The package puts Signal in Deskbar's
Applications folder.

Tested without an account: Signal starts from Deskbar, creates its
encrypted database (SQLCipher), connects to Signal's servers through
libsignal and shows the QR code that links it to a phone. Messaging after
linking needs a Signal account on a phone and has not been tested on air/OS
yet. Not available: voice and video calls. RingRTC is WebRTC, which is
not built for Haiku; `files/ringrtc-native.js` stands in for its native
module, so starting a call fails with a message and incoming calls do not
ring.

## How the port works

- **JavaScript** (`build.sh`, Linux): the upstream build (protobufs, emoji,
  rolldown bundles, styles, locales) and a stage of the app as
  electron-builder would pack it, with the production `node_modules`
  (`stage-modules.mjs`). With `SIGNAL_AIROS=1`, rolldown also builds
  `bundles/preload/haiku.js` (`rolldown.preload.ts`): the main window's
  preload in one file. Aurora bundles a `sandbox: false` preload's CommonJS
  modules into the page and serves Node.js's built-in and native modules from
  the main process; libsignal-client is an ES module package, so the page
  gets it ready-made. On air/OS the window uses that preload
  (`app/main.main.ts`, `OS.isAirOS()`), without upstream's `node:vm`
  code-cache wrapper.
- **Native modules** (`native.sh`, Linux, per architecture): libsignal's
  Node.js bridge (Rust with BoringSSL and tokio) and node-sqlcipher (SQLCipher,
  its Rust crypto provider and FTS5 tokenizer, N-API glue), built from
  upstream's sources at the versions `package.json` names, with air/OS's
  cross SDK and nightly Rust (airos-ci `sdk/build-rust.sh`). Two fixes are
  applied to libsignal's dependencies: linkme (neon's export table) learns
  that Haiku's linker is GNU ld, and mio is 1.2.4 or later (earlier ones make
  blocking sockets on Haiku, and the chat connection never comes up).
- **Package** (`cross.sh`, Linux): the stage, the native modules where
  node-gyp-build finds them, and a launcher made from Aurora's `aurora-host`
  with Signal's icon (`files/Signal.hvif`, traced from upstream's PNG),
  signature `application/x-vnd.signal-desktop` and its `sgnl:` and
  `signalcaptcha:` links (`files/Signal.rdef.in`). The app runs as Linux
  (`files/aurora.json`: `AURORA_PLATFORM=linux`), the nearest of Signal's
  platforms.

Signal's builds expire 90 days after their commit
(`scripts/get-expire-time.mjs`), and Signal's servers stop accepting old
versions: follow upstream's releases.

## Building

air/OS CI builds the packages on every push to `airos`
(`.github/workflows/airos.yml`, airos-ci `build_signal_desktop`) for x86_64
and arm64, into the package pool the images take Signal from. By hand, on
Linux with the air/OS cross SDK:

```sh
# the Node.js and pnpm of package.json (engines, devEngines)
pnpm install --frozen-lockfile --ignore-scripts
scripts/haiku/build.sh release/haiku
AIROS_SDK=/data1/airos/sdk/x86_64/env.sh RUST_ENV=<airos-ci>/env-x86_64.sh \
  NODE_HEADERS=<node-v22 headers> PROTOC=<protoc> LIBCLANG_PATH=/usr/lib/llvm-18/lib \
  scripts/haiku/native.sh x86_64 release/haiku-native-x86_64
SIGNAL_NATIVE=release/haiku-native-x86_64 HAIKU_HOST_TOOLS=<tools> \
  HAIKU_MIME_DB=<mime_db> AURORA_HOST_BINARY=<aurora-host> \
  scripts/haiku/cross.sh x86_64 release/haiku release/packages
```

`native.sh` and `cross.sh` describe their settings at the top. The package
requires `aurora` 0.4 or later and Node.js 22 (`cmd:node`).

To run a stage without packaging it, copy `release/haiku/app` and the native
modules to air/OS and start it with `aurora`:

```sh
AURORA_PLATFORM=linux AURORA_PAGE_CONSOLE=1 aurora /path/to/app
```

Signal keeps its data in `~/config/settings/Signal` (`logs/main.log` is the
main process's log, `logs/app.log` the window's).
