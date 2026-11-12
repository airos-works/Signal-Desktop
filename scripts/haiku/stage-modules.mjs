// Copyright 2026 air/OS contributors
// SPDX-License-Identifier: AGPL-3.0-only
// @ts-check

// Copies the app's production node_modules into a stage, flat, as
// electron-builder's "files" would ship them:
//   node scripts/haiku/stage-modules.mjs <stage app directory>
// The dependencies of package.json (and of each module, recursively) come
// from pnpm's node_modules, resolved from where each module really is.
// Native binaries built for other systems (prebuilds, build/) stay out; the
// Haiku ones are added by scripts/haiku/cross.sh.

import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
} from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { createRequire } from 'node:module';

const root = join(import.meta.dirname, '..', '..');
const out = process.argv[2];
if (!out) {
  throw new Error('usage: stage-modules.mjs <stage app directory>');
}

// What the electron-builder configuration leaves out of every module.
const SKIP_NAMES = new Set([
  'CHANGELOG.md',
  'README.md',
  'README',
  'readme.md',
  'readme',
  'test',
  '__tests__',
  'tests',
  'powered-test',
  'example',
  'examples',
  'benchmark',
  '.bin',
  '.cache',
  'prebuilds',
  'build',
  'node_modules',
]);
const SKIP_EXTENSIONS = [
  '.d.ts',
  '.d.ts.map',
  '.js.map',
  '.gypi',
  '.cpp',
  '.mm',
  '.cc',
  '.c',
  '.h',
  '.hpp',
  '.ts',
  '.map',
  '.d.mts',
  '.d.cts',
];

/** @param {string} directory */
function packageJsonOf(directory) {
  return JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8'));
}

/**
 * The directory of package `name` as `from` resolves it.
 * @param {string} name
 * @param {string} from
 */
function resolvePackage(name, from) {
  let directory = from;
  for (;;) {
    const candidate = join(directory, 'node_modules', name);
    if (existsSync(join(candidate, 'package.json'))) {
      return realpathSync(candidate);
    }
    const parent = dirname(directory);
    if (parent === directory) {
      return null;
    }
    directory = parent;
  }
}

/** @type {Map<string, string>} name -> source directory */
const modules = new Map();

/**
 * @param {string} from
 * @param {Record<string, string>} dependencies
 * @param {boolean} optional
 */
function visit(from, dependencies, optional) {
  for (const name of Object.keys(dependencies ?? {})) {
    const directory = resolvePackage(name, from);
    if (!directory) {
      if (optional) {
        continue;
      }
      throw new Error(`${name} (needed by ${from}) is not installed`);
    }
    const existing = modules.get(name);
    if (existing) {
      if (existing !== directory) {
        // Two versions of one module: the first (nearest the app) wins;
        // flat node_modules has room for one.
        const a = packageJsonOf(existing).version;
        const b = packageJsonOf(directory).version;
        if (a !== b) {
          console.warn(
            `note: ${name} ${a} is staged, ${b} (for ${relative(root, from)}) is not`
          );
        }
      }
      continue;
    }
    modules.set(name, directory);
    const pkg = packageJsonOf(directory);
    visit(directory, pkg.dependencies, false);
    visit(directory, pkg.optionalDependencies, true);
  }
}

const app = packageJsonOf(root);
visit(root, app.dependencies, false);
visit(root, app.optionalDependencies, true);

for (const [name, source] of [...modules].sort()) {
  const target = join(out, 'node_modules', name);
  mkdirSync(dirname(target), { recursive: true });
  cpSync(source, target, {
    recursive: true,
    dereference: true,
    filter: file => {
      const rel = relative(source, file);
      if (rel === '') {
        return true;
      }
      const parts = rel.split(sep);
      if (parts.some(part => SKIP_NAMES.has(part))) {
        return false;
      }
      return !SKIP_EXTENSIONS.some(extension => file.endsWith(extension));
    },
  });
}
console.log(`staged ${modules.size} modules in ${join(out, 'node_modules')}`);

// Every staged module still has its entry point (nothing it runs was in a
// directory left out above).
const stagedRequire = createRequire(join(out, 'package.json'));
for (const name of modules.keys()) {
  const pkg = packageJsonOf(join(out, 'node_modules', name));
  if (pkg.main || pkg.exports) {
    try {
      stagedRequire.resolve(name);
    } catch (error) {
      if (error.code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') {
        throw new Error(`${name}: ${error.message}`);
      }
    }
  }
}
