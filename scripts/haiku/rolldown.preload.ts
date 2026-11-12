// Copyright 2026 air/OS contributors
// SPDX-License-Identifier: AGPL-3.0-only

// The main window's preload for air/OS (bundles/preload/haiku.js), built when
// SIGNAL_AIROS=1 (scripts/haiku/build.sh).
//
// On air/OS Signal runs on Aurora: its pages are WebKit pages, and Aurora
// bundles a preload's CommonJS modules into the page itself, with Node.js's
// built-in modules and native modules served by the main process. Aurora's
// bundler reads CommonJS only, and libsignal-client is an ES module package,
// so this preload is complete: everything but Node.js's built-in modules and
// Electron is in it, in one file.
//
// - libsignal-client's native module is loaded from the app's
//   node_modules by its path (in the main process, through Aurora).
// - RingRTC's native module (WebRTC, which Haiku does not have) is
//   scripts/haiku/files/ringrtc-native.js: everything but calls works.
// - mute-state-change (macOS) is a stand-in that reports no mute state.
// - The modules for macOS and Windows only are left out.

import { builtinModules } from 'node:module';
import { join } from 'node:path';
import type { RolldownOptions, RolldownPluginOption } from 'rolldown';

const FILES = join(import.meta.dirname, 'files');

const builtins = new Set([
  ...builtinModules,
  ...builtinModules.map(name => `node:${name}`),
]);

export function airosPreload(defaults: RolldownOptions): RolldownOptions {
  return {
    ...defaults,
    input: { 'preload/haiku': 'ts/windows/main/preload.preload.ts' },
    platform: 'node',
    // The page's engine is WebKit, not Chromium: lower what it may not have
    // yet (`using` declarations).
    transform: {
      ...defaults.transform,
      target: 'es2024',
    },
    external: id =>
      builtins.has(id) ||
      id === 'electron' ||
      id === 'original-fs' ||
      // macOS and Windows only, and loaded only there
      id === '@indutny/mac-screen-share' ||
      id === '@indutny/simple-windows-notifications' ||
      id === '@signalapp/windows-ucv' ||
      id === 'fs-xattr' ||
      id === 'fsevents' ||
      id === 'mac-screen-capture-permissions' ||
      // tests only (rolldown.config.ts leaves them out of every bundle)
      id === 'mocha' ||
      id.endsWith('preload_test.preload.ts'),
    plugins: [
      ...((defaults.plugins as Array<RolldownPluginOption>) ?? []),
      {
        name: 'airos-preload',
        resolveId(source: string, importer: string | undefined) {
          if (
            source === './Native' &&
            importer?.includes(`${join('@signalapp', 'ringrtc')}`)
          ) {
            return join(FILES, 'ringrtc-native.js');
          }
          if (source === '@signalapp/mute-state-change') {
            return join(FILES, 'mute-state-change.js');
          }
          return null;
        },
        transform(code: string, id: string) {
          // libsignal-client finds its native module next to its own
          // files; here they are in the app's node_modules.
          if (
            id.includes(`${join('@signalapp', 'libsignal-client')}`) &&
            id.endsWith(join('dist', 'Native.js'))
          ) {
            const from = '`${import.meta.dirname}/../`';
            if (!code.includes(from)) {
              throw new Error(
                'libsignal-client: the native module load changed'
              );
            }
            return code.replace(
              from,
              "require('node:path').join(__dirname, '..', '..', 'node_modules', '@signalapp', 'libsignal-client')"
            );
          }
          return null;
        },
      },
    ],
    output: {
      ...defaults.output,
      codeSplitting: false,
    },
  };
}
