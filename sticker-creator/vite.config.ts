// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import * as sass from 'sass';

// air/OS (../scripts/haiku): WebKit runs no ES module scripts from file:
// pages, so with SIGNAL_AIROS=1 the page is one classic script.
const airos = process.env.SIGNAL_AIROS === '1';

// https://vitejs.dev/config/
export default defineConfig({
  ...(airos
    ? {
        build: {
          modulePreload: false,
          rolldownOptions: {
            output: { format: 'iife', codeSplitting: false },
          },
        },
      }
    : {}),
  css: {
    modules: {
      localsConvention: 'camelCaseOnly',
    },
    preprocessorOptions: {
      scss: {
        // setting the version number is not working for some reason
        fatalDeprecations: Object.values(sass.deprecations)
          .filter(dep => dep.status !== 'obsolete')
          .map(dep => dep.id),
      },
    },
  },
  worker: {
    format: 'es',
  },
  plugins: [
    react(),
    ...(airos
      ? [
          {
            name: 'airos-classic-script',
            enforce: 'post' as const,
            transformIndexHtml: (html: string) =>
              html.replace(/<script type="module" crossorigin/g, '<script defer'),
          },
        ]
      : []),
  ],
});
