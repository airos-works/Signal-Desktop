// Copyright 2026 air/OS contributors
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';

// RingRTC's native module on air/OS, which has none: RingRTC is WebRTC, and
// WebRTC is not built for Haiku. This stands in for
// @signalapp/ringrtc/dist/ringrtc/Native.js (scripts/haiku/cross.sh puts it
// there), so Signal starts and everything but calls works:
// - setup calls (call endpoint, assets, self id, stats interval, events) do
//   nothing;
// - there are no audio devices;
// - everything that would start, join, peek or manage a call throws, which
//   RingRTC's JavaScript turns into a rejected request or a failed call.

const UNAVAILABLE = 'Voice and video calls are not available on air/OS';

function unavailable() {
  throw new Error(UNAVAILABLE);
}

const harmless = new Set([
  'cm_setSelfUuid',
  'cm_addAsset',
  'cm_processEvents',
  'cm_setRtcStatsInterval',
  'cm_logBookmarkMessage',
  'cm_setVoiceProcessingEnabled',
  'cm_updateDataMode',
  'cm_setDataMode',
  'cm_signalingMessageSent',
  'cm_signalingMessageSendFailed',
  'cm_receivedHttpResponse',
  'cm_httpRequestFailed',
  'cm_receivedCallMessage',
  'cm_receivedOffer',
  'cm_receivedAnswer',
  'cm_receivedIceCandidates',
  'cm_receivedHangup',
  'cm_receivedBusy',
  'cm_deleteGroupCallClient',
]);

const native = {
  callEndpointPropertyKey: '__airosCallEndpoint',
  createCallEndpoint() {
    return Object.freeze({ airos: true });
  },
  cm_getAudioInputs() {
    return [];
  },
  cm_getAudioOutputs() {
    return [];
  },
  // A call id from a group call's era id (Rust: a hash of the string). Only
  // used to name calls that cannot happen here; any stable 64-bit value does.
  callIdFromEra(era) {
    let hash = 0xcbf29ce484222325n;
    for (const byte of new TextEncoder().encode(String(era))) {
      hash ^= BigInt(byte);
      hash = BigInt.asUintN(64, hash * 0x100000001b3n);
    }
    return hash;
  },
};

const proxy = new Proxy(native, {
  get(target, name) {
    if (Object.prototype.hasOwnProperty.call(target, name)) {
      return target[name];
    }
    if (typeof name !== 'string') {
      return undefined;
    }
    if (harmless.has(name)) {
      return function nothing() {
        return undefined;
      };
    }
    return unavailable;
  },
});
// As the TypeScript-compiled original exports it (Service.js reads
// Native.default).
native.__esModule = true;
native.default = proxy;
module.exports = proxy;
