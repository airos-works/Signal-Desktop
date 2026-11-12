// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import semver from 'semver';

function createIsPlatform(
  platform: typeof process.platform,
  osRelease: string
): (minVersion?: string) => boolean {
  return minVersion => {
    if (process.platform !== platform) {
      return false;
    }
    if (minVersion === undefined) {
      return true;
    }

    return semver.gte(osRelease, minVersion);
  };
}

export type OSType = {
  getClassName: () => string;
  getName: () => string;
  isLinux: (minVersion?: string) => boolean;
  isLinuxAppImage: () => boolean;
  isMacOS: (minVersion?: string) => boolean;
  isMAS: () => boolean;
  isWindows: (minVersion?: string) => boolean;
  // air/OS (Haiku), where Signal runs on Aurora: Electron's API on Node.js
  // and Summit's WebKit. process.platform is "linux" there (Linux is the
  // nearest of Signal's platforms); this tells the two apart.
  isAirOS: () => boolean;
};

export function isAirOS(): boolean {
  return typeof process.versions?.aurora === 'string';
}

export function getOSFunctions(osRelease: string): OSType {
  const isMacOS = createIsPlatform('darwin', osRelease);
  const isLinux = createIsPlatform('linux', osRelease);
  const isWindows = createIsPlatform('win32', osRelease);

  const isLinuxAppImage = (): boolean => {
    return process.platform === 'linux' && process.env.APPIMAGE != null;
  };

  const getName = (): string => {
    if (isAirOS()) {
      return 'air/OS';
    }
    if (isMacOS()) {
      return 'macOS';
    }
    if (isWindows()) {
      return 'Windows';
    }
    return 'Linux';
  };

  const getClassName = (): string => {
    if (isMacOS()) {
      return 'os-macos';
    }
    if (isWindows()) {
      // oxlint-disable-next-line signal-desktop/enforce-class-name-has-styles
      return 'os-windows';
    }
    // oxlint-disable-next-line signal-desktop/enforce-class-name-has-styles
    return 'os-linux';
  };

  return {
    getClassName,
    getName,
    isLinux,
    isLinuxAppImage,
    isMacOS,
    isMAS: () => process.mas,
    isWindows,
    isAirOS,
  };
}
