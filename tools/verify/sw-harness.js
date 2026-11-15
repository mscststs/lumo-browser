'use strict';
/* Node harness: execute sw.js under Node with a fake chrome.* surface.
 *
 * Purpose: catch runtime reference errors and API-shape mistakes that
 * `node --check` cannot. It is NOT a browser test — the fake chrome.* surface
 * reproduces the *shape* of the APIs (promise vs callback, event objects), not
 * their Android behaviour.
 *
 * Usage: node tools/verify/sw-harness.js tools/probe-extension/sw.js
 */

const fs = require('fs');
const vm = require('vm');

const store = { local: new Map(), session: new Map(), sync: new Map() };

function storageArea(map) {
  return {
    async get(keys) {
      if (keys === null || keys === undefined) return Object.fromEntries(map);
      if (typeof keys === 'string') {
        return map.has(keys) ? { [keys]: map.get(keys) } : {};
      }
      if (Array.isArray(keys)) {
        const out = {};
        for (const k of keys) if (map.has(k)) out[k] = map.get(k);
        return out;
      }
      const out = {};
      for (const [k, def] of Object.entries(keys)) out[k] = map.has(k) ? map.get(k) : def;
      return out;
    },
    async set(obj) {
      for (const [k, v] of Object.entries(obj)) map.set(k, v);
    },
    async remove(keys) {
      for (const k of [].concat(keys)) map.delete(k);
    }
  };
}

const listeners = {
  message: [],
  installed: [],
  startup: [],
  navCommitted: [],
  navError: [],
  navCompleted: []
};

const event = (bucket) => ({
  addListener(fn) {
    bucket.push(fn);
  },
  removeListener(fn) {
    const index = bucket.indexOf(fn);
    if (index >= 0) bucket.splice(index, 1);
  }
});

let dynamicRules = [];
let usRegistered = [];

const chrome = {
  runtime: {
    id: 'fakeid',
    lastError: undefined,
    getManifest: () => ({ name: 'Lumo MV3 Probe', version: '0.1.0', manifest_version: 3 }),
    getURL: (p) => 'chrome-extension://fakeid/' + p,
    getPlatformInfo: async () => ({ os: 'android', arch: 'arm64', nacl_arch: 'arm' }),
    onInstalled: event(listeners.installed),
    onStartup: event(listeners.startup),
    onMessage: event(listeners.message),
    sendMessage: (msg, cb) => cb && cb({ ok: true })
  },
  storage: {
    local: storageArea(store.local),
    session: storageArea(store.session),
    sync: storageArea(store.sync)
  },
  alarms: {
    async create(name) {
      this._last = { name };
    },
    async getAll() {
      return this._last ? [this._last] : [];
    },
    async clear() {
      this._last = null;
      return true;
    }
  },
  tabs: {
    async query() {
      return [{ id: 7, url: 'https://example.com/', title: 'Example', status: 'complete' }];
    },
    async create(props) {
      return { id: 99, url: props.url };
    },
    async update() {
      return {};
    },
    async remove() {},
    sendMessage: (id, msg, cb) => cb && cb({ pong: true })
  },
  scripting: {
    async executeScript() {
      return [{ result: { title: 'Example', url: 'https://example.com/', isolatedMarker: true } }];
    }
  },
  cookies: { async getAll() { return [{ name: 'a' }]; } },
  notifications: {
    getPermissionLevel(cb) { cb('granted'); },
    create(id, opts, cb) { cb(id); },
    clear(id, cb) { cb(true); }
  },
  contextMenus: {
    removeAll(cb) { cb(); },
    create(props, cb) { cb(); }
  },
  webNavigation: {
    onCommitted: event(listeners.navCommitted),
    onErrorOccurred: event(listeners.navError),
    onCompleted: event(listeners.navCompleted)
  },
  declarativeNetRequest: {
    async getDynamicRules() { return dynamicRules.slice(); },
    async updateDynamicRules({ removeRuleIds = [], addRules = [] }) {
      dynamicRules = dynamicRules.filter((r) => !removeRuleIds.includes(r.id));
      dynamicRules.push(...addRules);
    }
  },
  userScripts: {
    async getScripts(filter) {
      if (filter && filter.ids) return usRegistered.filter((s) => filter.ids.includes(s.id));
      return usRegistered.slice();
    },
    async register(scripts) { usRegistered.push(...scripts); },
    async unregister(filter) {
      if (filter && filter.ids) usRegistered = usRegistered.filter((s) => !filter.ids.includes(s.id));
    }
  },
  sidePanel: {
    _options: {},
    async getOptions() { return { ...this._options }; },
    async setOptions(o) { this._options = { ...this._options, ...o }; }
  },
  downloads: { download() {}, search() {} },
  i18n: { getUILanguage: () => 'zh-CN', getMessage: (k) => (k === '@@ui_locale' ? 'zh_CN' : '') },
  action: {
    async setBadgeText(o) { this._badge = o.text; },
    async setBadgeBackgroundColor() {},
    async setIcon() {}
  }
};

global.chrome = chrome;
global.self = global;
Object.defineProperty(global, 'navigator', { value: { userAgent: 'node-harness', platform: 'Linux armv8l' }, configurable: true });
if (typeof global.ImageData !== 'function') {
  global.ImageData = class ImageData {
    constructor(data, w, h) {
      this.data = data;
      this.width = w;
      this.height = h;
    }
  };
}

const target = process.argv[2] || 'tools/probe-extension/sw.js';
const code = fs.readFileSync(target, 'utf8');
vm.runInThisContext(code, { filename: target });

(async () => {
  const deadline = Date.now() + 8000;
  let latest = null;
  while (Date.now() < deadline) {
    latest = store.local.get('probe:latest');
    if (latest) break;
    await new Promise((r) => setTimeout(r, 50));
  }
  if (!latest) {
    console.error('HARNESS FAIL: probe:latest never written');
    process.exit(1);
  }
  const meta = store.local.get('probe:meta');
  console.log('meta:', JSON.stringify({ trigger: meta && meta.trigger, pass: meta && meta.pass, fail: meta && meta.fail, total: meta && meta.total }));
  for (const item of latest) {
    console.log((item.ok ? 'PASS' : 'FAIL').padEnd(4), item.api.padEnd(36), item.ok ? item.detail : item.error);
  }
  const expectedItems = 30;
  if (latest.length !== expectedItems) {
    console.error('HARNESS FAIL: expected ' + expectedItems + ' items, got ' + latest.length);
    process.exit(1);
  }

  // message path: probe:run must produce trigger=message
  const handler = listeners.message[0];
  await new Promise((resolve) => {
    handler({ type: 'probe:run' }, {}, (response) => {
      console.log('probe:run ->', response.ok, response.payload && response.payload.meta.trigger);
      resolve();
    });
  });

  // content:ready path
  await new Promise((resolve) => {
    handler({ type: 'content:ready', url: 'https://example.com/' }, { tab: { id: 7 } }, (response) => {
      console.log('content:ready ->', response.ok, JSON.stringify(store.local.get('probe:content:last')));
      resolve();
    });
  });

  // dnr effect path: simulate the blocked navigation
  async function dnrEffect(fire) {
    let navTab = null;
    const originalCreate = chrome.tabs.create;
    chrome.tabs.create = async (props) => {
      navTab = await originalCreate(props);
      return navTab;
    };
    const responsePromise = new Promise((resolve) => {
      handler({ type: 'probe:dnr-effect' }, {}, resolve);
    });
    // Give the SW a tick to install its watcher + create the tab, then fire the
    // navigation event while the probe is still awaiting the outcome.
    await new Promise((resolve) => setTimeout(resolve, 50));
    chrome.tabs.create = originalCreate;
    fire(navTab);
    return responsePromise;
  }

  // Note: the watcher is installed before tabs.create resolves in sw.js, but
  // here the mocked create resolves instantly, so we fire after the call and
  // rely on the event listeners being installed synchronously by then.
  const blockedResponse = await dnrEffect((navTab) => {
    for (const fn of listeners.navError.slice()) {
      fn({ frameId: 0, tabId: navTab.id, url: 'https://example.com/blocked-by-dnr', error: 'net::ERR_BLOCKED_BY_CLIENT' });
    }
  });
  console.log('probe:dnr-effect(blocked) ->', JSON.stringify(blockedResponse));
  if (!blockedResponse.ok || blockedResponse.payload.blocked !== true) {
    console.error('HARNESS FAIL: expected blocked=true');
    process.exit(1);
  }

  const allowedResponse = await dnrEffect((navTab) => {
    for (const fn of listeners.navCompleted.slice()) {
      fn({ frameId: 0, tabId: navTab.id, url: 'https://example.com/blocked-by-dnr' });
    }
  });
  console.log('probe:dnr-effect(allowed) ->', JSON.stringify(allowedResponse));
  if (!allowedResponse.ok || allowedResponse.payload.blocked !== false) {
    console.error('HARNESS FAIL: expected blocked=false');
    process.exit(1);
  }

  const finalLatest = store.local.get('probe:latest');
  const meta2 = store.local.get('probe:meta');
  if (!meta2 || meta2.trigger !== 'message' || meta2.total !== expectedItems) {
    console.error('HARNESS FAIL: expected meta.trigger=message after probe:run');
    process.exit(1);
  }
  // The mock surface only implements the original API set; probes for newer
  // APIs (offscreen/tabGroups/webRequest/identity/capture) are expected to fail
  // here and are validated on device instead.
  const passCount = finalLatest.filter((i) => i.ok).length;
  if (passCount < 20) {
    console.error('HARNESS FAIL: expected >= 20 passing probes with the mock surface, got ' + passCount);
    process.exit(1);
  }

  console.log('HARNESS OK');
})();
