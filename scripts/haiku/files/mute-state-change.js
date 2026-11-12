// Copyright 2026 air/OS contributors
// SPDX-License-Identifier: AGPL-3.0-only

// @signalapp/mute-state-change on air/OS: the system mute state is a macOS
// API, so there is none to read or set (as on Linux, where the module's
// native part does not load either).

export function isMuted() {
  return undefined;
}

export function setIsMuted() {
  // nothing to set
}

export function subscribe() {
  // no changes ever come
}

export function unsubscribe() {
  // nothing was subscribed
}
