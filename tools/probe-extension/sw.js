'use strict';

/*
 * Lumo MV3 Probe — service worker
 *
 * Runs a capability probe over the chrome.* surface that ../lumo and
 * ../lumo-userscript-manager depend on. Every item is wrapped in try/catch with
 * a per-item 2s timeout so one hanging API cannot stall the whole run.
 *
 * Result shape per item: { api, ok, detail, error }
 *   ok      = capability actually usable (not merely "the probe ran")
 *   detail  = short human/machine readable evidence string
 *   error   = null, or "Name: message"
 *
 * `ok:false` is a finding, not a crash: offscreen/debugger are expected to be
 * false here because their permissions are intentionally not declared.
 */

const PROBE_VERSION = '0.1.0';
const ITEM_TIMEOUT_MS = 2000;
const NAV_TIMEOUT_MS = 8000;
const KEEP_LOG_COUNT = 5;

const LOG_PREFIX = 'probe:';
const KEY_LATEST = 'probe:latest';
const KEY_META = 'probe:meta';
const KEY_CONTENT_LAST = 'probe:content:last';

const DNR_TEMP_RULE_ID = 9100;
const DNR_TEST_RULE_ID = 9101;
const DNR_TEST_URL = 'https://example.com/blocked-by-dnr';

const bootCount = { module: 0 };
let runningProbe = null;
let lastResults = null;

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */

function describeError(err) {
  if (!err) return 'unknown error';
  if (typeof err === 'string') return err;
  const name = err.name || 'Error';
  const message = err.message || String(err);
  return name + ': ' + message;
}

function clip(value, max) {
  const limit = max || 300;
  let text;
  if (typeof value === 'string') {
    text = value;
  } else if (value === undefined) {
    text = 'undefined';
  } else {
    try {
      text = JSON.stringify(value);
    } catch (e) {
      text = String(value);
    }
  }
  if (typeof text !== 'string') text = String(text);
  return text.length > limit ? text.slice(0, limit) + '…' : text;
}

function withTimeout(promise, ms, label) {
  let timer = null;
  const timeout = new Promise((resolve, reject) => {
    timer = setTimeout(() => {
      reject(new Error('timeout after ' + ms + 'ms (' + label + ')'));
    }, ms);
  });
  return Promise.race([Promise.resolve(promise), timeout]).finally(() => {
    if (timer !== null) clearTimeout(timer);
  });
}

// Wrap a callback-style chrome API so runtime.lastError becomes a rejection.
function callbackApi(invoke) {
  return new Promise((resolve, reject) => {
    let settled = false;
    try {
      invoke((result) => {
        if (settled) return;
        settled = true;
        const err = chrome.runtime.lastError;
        if (err) reject(new Error(err.message || 'runtime.lastError'));
        else resolve(result);
      });
    } catch (e) {
      if (!settled) {
        settled = true;
        reject(e);
      }
    }
  });
}

function hasFunction(target, name) {
  try {
    return !!target && typeof target[name] === 'function';
  } catch (e) {
    return false;
  }
}

// chrome.webNavigation.onCommitted 等是事件对象，不是函数。
function isEventObject(value) {
  return !!value && typeof value === 'object' && typeof value.addListener === 'function';
}

/* ------------------------------------------------------------------ */
/* event bookkeeping (registered at top level so events are never lost) */
/* ------------------------------------------------------------------ */

const netEvents = {
  registered: false,
  registerError: null,
  committed: 0,
  errors: 0,
  completed: 0,
  lastUrl: '',
  lastError: ''
};

try {
  chrome.webNavigation.onCommitted.addListener((details) => {
    if (details.frameId !== 0) return;
    netEvents.committed += 1;
    netEvents.lastUrl = details.url || '';
  });
  chrome.webNavigation.onErrorOccurred.addListener((details) => {
    if (details.frameId !== 0) return;
    netEvents.errors += 1;
    netEvents.lastError = details.error || '';
    netEvents.lastUrl = details.url || '';
  });
  chrome.webNavigation.onCompleted.addListener((details) => {
    if (details.frameId !== 0) return;
    netEvents.completed += 1;
    netEvents.lastUrl = details.url || '';
  });
  netEvents.registered = true;
} catch (e) {
  netEvents.registerError = describeError(e);
}

/* ------------------------------------------------------------------ */
/* DNR test rule (persistent, used by testpage.html)                   */
/* ------------------------------------------------------------------ */

async function ensureTestBlockRule() {
  const rules = await chrome.declarativeNetRequest.getDynamicRules();
  const present = rules.some((rule) => rule.id === DNR_TEST_RULE_ID);
  if (present) return { added: false, total: rules.length };
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: [DNR_TEST_RULE_ID],
    addRules: [
      {
        id: DNR_TEST_RULE_ID,
        priority: 1,
        action: { type: 'block' },
        condition: {
          urlFilter: '||example.com/blocked-by-dnr',
          resourceTypes: ['main_frame', 'xmlhttprequest', 'sub_frame']
        }
      }
    ]
  });
  const after = await chrome.declarativeNetRequest.getDynamicRules();
  return { added: true, total: after.length };
}

/* ------------------------------------------------------------------ */
/* probe items                                                         */
/* ------------------------------------------------------------------ */

async function probeRuntimeGetManifest() {
  const m = chrome.runtime.getManifest();
  return clip(m.name + '@' + m.version + ' mv' + m.manifest_version, 120);
}

async function probeRuntimeGetUrl() {
  return chrome.runtime.getURL('probe.html');
}

async function probeRuntimeId() {
  if (!chrome.runtime.id) throw new Error('chrome.runtime.id empty');
  return chrome.runtime.id;
}

async function probeRuntimePlatform() {
  const info = await chrome.runtime.getPlatformInfo();
  return clip(info);
}

async function probeStorageLocal() {
  const key = 'probe:roundtrip:local';
  const value = 'v' + Date.now();
  await chrome.storage.local.set({ [key]: value });
  const got = await chrome.storage.local.get(key);
  if (got[key] !== value) throw new Error('readback mismatch: ' + clip(got[key], 80));
  return 'set+get ok (' + value + ')';
}

async function probeStorageSession() {
  if (!chrome.storage.session) throw new Error('chrome.storage.session undefined');
  const key = 'probe:roundtrip:session';
  const value = 's' + Date.now();
  await chrome.storage.session.set({ [key]: value });
  const got = await chrome.storage.session.get(key);
  if (got[key] !== value) throw new Error('readback mismatch');
  return 'set+get ok (' + value + ')';
}

async function probeStorageSync() {
  if (!chrome.storage.sync) throw new Error('chrome.storage.sync undefined');
  const key = 'probe:roundtrip:sync';
  const value = 'y' + Date.now();
  await chrome.storage.sync.set({ [key]: value });
  const got = await chrome.storage.sync.get(key);
  if (got[key] !== value) throw new Error('readback mismatch');
  return 'set+get ok (' + value + ')';
}

async function probeAlarms() {
  if (!chrome.alarms) throw new Error('chrome.alarms undefined');
  const name = 'probe-alarm';
  await chrome.alarms.create(name, { delayInMinutes: 1 });
  const all = await chrome.alarms.getAll();
  const found = all.some((alarm) => alarm.name === name);
  await chrome.alarms.clear(name);
  if (!found) throw new Error('created alarm not returned by getAll (n=' + all.length + ')');
  return 'create+getAll+clear ok (n=' + all.length + ')';
}

async function probeTabsQuery() {
  const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tabs.length) throw new Error('no active tab in lastFocusedWindow');
  const tab = tabs[0];
  return clip({ id: tab.id, url: tab.url, title: tab.title, status: tab.status });
}

async function probeTabsCreateUpdate() {
  if (!hasFunction(chrome.tabs, 'create')) throw new Error('chrome.tabs.create missing');
  if (!hasFunction(chrome.tabs, 'update')) throw new Error('chrome.tabs.update missing');
  return 'create+update 函数存在（未实际调用，避免开新标签）';
}

async function probeScriptingExecute() {
  if (!chrome.scripting || !hasFunction(chrome.scripting, 'executeScript')) {
    throw new Error('chrome.scripting.executeScript missing');
  }
  const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tabs.length) throw new Error('no active tab to inject into');
  const tab = tabs[0];
  const url = tab.url || '';
  if (!/^https?:/i.test(url)) {
    throw new Error('active tab not injectable: scheme of ' + clip(url, 120));
  }
  const injections = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => ({
      title: document.title,
      url: location.href,
      isolatedMarker: !!window.__lumoProbe
    })
  });
  const first = (injections && injections[0] && injections[0].result) || null;
  if (!first) throw new Error('executeScript returned no result');
  return clip({ title: first.title, isolatedMarker: first.isolatedMarker });
}

async function probeCookies() {
  if (!chrome.cookies) throw new Error('chrome.cookies undefined');
  const cookies = await chrome.cookies.getAll({});
  return 'getAll ok (n=' + cookies.length + ')';
}

async function probeNotifications() {
  if (!chrome.notifications) throw new Error('chrome.notifications undefined');
  const level = await callbackApi((cb) => chrome.notifications.getPermissionLevel(cb));
  if (level !== 'granted') throw new Error('permission level=' + clip(level, 40));
  const id = 'probe-note-' + Date.now();
  await callbackApi((cb) =>
    chrome.notifications.create(
      id,
      {
        type: 'basic',
        iconUrl: chrome.runtime.getURL('icons/probe-128.png'),
        title: 'Lumo MV3 Probe',
        message: 'notifications.create ok',
        priority: 0
      },
      cb
    )
  );
  await callbackApi((cb) => chrome.notifications.clear(id, cb));
  return 'permission=granted, create+clear ok';
}

async function probeContextMenus() {
  if (!chrome.contextMenus) throw new Error('chrome.contextMenus undefined');
  await callbackApi((cb) => chrome.contextMenus.removeAll(cb));
  const id = await new Promise((resolve, reject) => {
    try {
      chrome.contextMenus.create(
        {
          id: 'lumo-probe-item',
          title: 'Lumo Probe',
          contexts: ['page', 'selection', 'link']
        },
        () => {
          const err = chrome.runtime.lastError;
          if (err) reject(new Error(err.message || 'contextMenus.create failed'));
          else resolve('lumo-probe-item');
        }
      );
    } catch (e) {
      reject(e);
    }
  });
  return 'removeAll+create ok (id=' + id + ')';
}

async function probeWebNavigationEvents() {
  if (!chrome.webNavigation) throw new Error('chrome.webNavigation undefined');
  if (!isEventObject(chrome.webNavigation.onCommitted)) {
    throw new Error('chrome.webNavigation.onCommitted 不是事件对象');
  }
  if (!isEventObject(chrome.webNavigation.onErrorOccurred)) {
    throw new Error('chrome.webNavigation.onErrorOccurred 不是事件对象');
  }
  if (!netEvents.registered) {
    throw new Error('listener registration failed: ' + clip(netEvents.registerError, 160));
  }
  return clip({
    listeners: 'onCommitted/onErrorOccurred/onCompleted',
    committed: netEvents.committed,
    errors: netEvents.errors,
    completed: netEvents.completed,
    lastUrl: netEvents.lastUrl
  });
}

async function probeDnrDynamicRules() {
  if (!chrome.declarativeNetRequest) throw new Error('chrome.declarativeNetRequest undefined');
  const before = await chrome.declarativeNetRequest.getDynamicRules();
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: [DNR_TEMP_RULE_ID],
    addRules: [
      {
        id: DNR_TEMP_RULE_ID,
        priority: 1,
        action: { type: 'block' },
        condition: {
          urlFilter: '||lumo-probe-temp.example',
          resourceTypes: ['main_frame']
        }
      }
    ]
  });
  const during = await chrome.declarativeNetRequest.getDynamicRules();
  const added = during.some((rule) => rule.id === DNR_TEMP_RULE_ID);
  await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: [DNR_TEMP_RULE_ID] });
  const after = await chrome.declarativeNetRequest.getDynamicRules();
  const removed = !after.some((rule) => rule.id === DNR_TEMP_RULE_ID);
  if (!added) throw new Error('temp rule not visible in getDynamicRules');
  if (!removed) throw new Error('temp rule still present after remove');
  return 'add+get+remove ok (before=' + before.length + ', after=' + after.length + ')';
}

async function probeUserScriptsGet() {
  if (!chrome.userScripts) {
    throw new Error('chrome.userScripts 未暴露（需 userScripts 权限 + 用户开关/developer mode）');
  }
  if (!hasFunction(chrome.userScripts, 'getScripts')) {
    throw new Error('chrome.userScripts.getScripts missing');
  }
  const scripts = await chrome.userScripts.getScripts();
  return 'getScripts ok (n=' + scripts.length + ')';
}

async function probeUserScriptsRegister() {
  if (!chrome.userScripts) {
    throw new Error('chrome.userScripts 未暴露（需 userScripts 权限 + 用户开关/developer mode）');
  }
  if (!hasFunction(chrome.userScripts, 'register')) {
    throw new Error('chrome.userScripts.register missing');
  }
  const id = 'lumo-probe-userscript';
  try {
    await chrome.userScripts.register([
      {
        id,
        matches: ['https://example.com/*'],
        js: [{ code: 'window.__lumoProbeUserscript = 1;' }],
        runAt: 'document_start'
      }
    ]);
    const registered = await chrome.userScripts.getScripts({ ids: [id] });
    if (!registered || registered.length === 0) {
      throw new Error('register returned but getScripts cannot see it');
    }
  } finally {
    try {
      await chrome.userScripts.unregister({ ids: [id] });
    } catch (e) {
      /* leave cleanup failure out of the probe verdict */
    }
  }
  return 'register+getScripts+unregister ok';
}

async function probeSidePanel() {
  if (!chrome.sidePanel) throw new Error('chrome.sidePanel undefined');
  if (!hasFunction(chrome.sidePanel, 'getOptions')) throw new Error('getOptions missing');
  if (!hasFunction(chrome.sidePanel, 'setOptions')) throw new Error('setOptions missing');
  const before = await chrome.sidePanel.getOptions({});
  await chrome.sidePanel.setOptions({ path: 'sidepanel.html', enabled: true });
  const after = await chrome.sidePanel.getOptions({});
  if (!after || after.path !== 'sidepanel.html') {
    throw new Error('setOptions not reflected: ' + clip(after, 120));
  }
  return clip({ before, after });
}

async function probeDownloads() {
  if (!chrome.downloads) throw new Error('chrome.downloads undefined');
  if (!hasFunction(chrome.downloads, 'download')) throw new Error('downloads.download missing');
  if (!hasFunction(chrome.downloads, 'search')) throw new Error('downloads.search missing');
  return 'download/search 函数存在（未实际下载）';
}

async function probeI18n() {
  if (!chrome.i18n) throw new Error('chrome.i18n undefined');
  const lang = chrome.i18n.getUILanguage();
  const locale = chrome.i18n.getMessage('@@ui_locale');
  if (!lang) throw new Error('getUILanguage returned empty');
  return 'getUILanguage=' + clip(lang, 40) + ' @@ui_locale=' + clip(locale, 40);
}

async function probeActionBadgeIcon() {
  if (!chrome.action) throw new Error('chrome.action undefined');
  await chrome.action.setBadgeText({ text: 'P' });
  await chrome.action.setBadgeBackgroundColor({ color: '#2563eb' });
  // path form is the canonical MV3 call; imageData is worth probing separately
  // because SW-side ImageData/OffscreenCanvas support varies on Android.
  await chrome.action.setIcon({ path: { 128: 'icons/probe-128.png' } });
  let imageDataDetail = 'skipped';
  try {
    if (typeof ImageData !== 'function') throw new Error('ImageData 在 SW 中不可用');
    const imageData = new ImageData(new Uint8ClampedArray([37, 99, 235, 255]), 1, 1);
    await chrome.action.setIcon({ imageData });
    imageDataDetail = 'ok';
  } catch (e) {
    imageDataDetail = 'failed: ' + describeError(e);
  }
  await chrome.action.setBadgeText({ text: '' });
  return 'setBadgeText+setIcon(path) ok, setIcon(imageData)=' + imageDataDetail;
}

async function probeOffscreen() {
  if (!chrome.offscreen) {
    throw new Error('chrome.offscreen 未暴露（manifest 未声明 offscreen 权限）');
  }
  if (!hasFunction(chrome.offscreen, 'createDocument')) throw new Error('createDocument missing');
  return 'createDocument 存在（未实际创建，避免副作用）';
}

async function probeDebugger() {
  if (!chrome.debugger) {
    throw new Error('chrome.debugger 未暴露（manifest 未声明 debugger 权限）');
  }
  if (!hasFunction(chrome.debugger, 'attach')) throw new Error('debugger.attach missing');
  return 'attach 存在（未实际 attach）';
}


/* --- extra MV3 surface (Lumo Browser matrix) ------------------------------ */

async function probeCookiesWrite() {
  const url = 'https://example.com/';
  await chrome.cookies.set({ url, name: 'lumo_probe', value: '1', path: '/' });
  const got = await chrome.cookies.get({ url, name: 'lumo_probe' });
  await chrome.cookies.remove({ url, name: 'lumo_probe' });
  if (!got || got.value !== '1') throw new Error('cookie round-trip failed');
  return `set/get/remove ok (value=${got.value})`;
}

async function probeTabGroups() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab || tab.id == null) return 'no active tab (API exposed)';
  if (!/^https?:/.test(tab.url || '')) return `active tab not web (${tab.url || 'unknown'}); API exposed`;
  const groupId = await chrome.tabs.group({ tabIds: [tab.id] });
  await chrome.tabGroups.update(groupId, { title: 'lumo-probe', color: 'blue' });
  const groups = await chrome.tabGroups.query({ title: 'lumo-probe' });
  await chrome.tabs.ungroup([tab.id]);
  return `group+update+query+ungroup ok (found=${groups.length})`;
}

async function probeWebRequestEvents() {
  const events = { before: 0, completed: 0 };
  const onBefore = () => { events.before += 1; };
  const onCompleted = () => { events.completed += 1; };
  chrome.webRequest.onBeforeRequest.addListener(onBefore, { urls: ['<all_urls>'] });
  chrome.webRequest.onCompleted.addListener(onCompleted, { urls: ['<all_urls>'] });
  try {
    await fetch('https://example.com/?lumo_probe=1', {
      cache: 'no-store',
      signal: AbortSignal.timeout(1200)
    });
  } catch (e) { /* offline/slow is fine: the listeners are what we are testing */ }
  await new Promise((r) => setTimeout(r, 200));
  chrome.webRequest.onBeforeRequest.removeListener(onBefore);
  chrome.webRequest.onCompleted.removeListener(onCompleted);
  return `listeners registered; onBeforeRequest=${events.before}, onCompleted=${events.completed}`;
}

async function probeMainWorldScripting() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab || tab.id == null || !/^https?:/.test(tab.url || '')) {
    return `skipped (active tab: ${tab ? tab.url : 'none'})`;
  }
  const [res] = await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    world: 'MAIN',
    func: () => {
      window.__lumoMainWorld = 42;
      return { marker: window.__lumoMainWorld, isIsolated: typeof chrome === 'undefined' };
    }
  });
  return JSON.stringify(res.result);
}

async function probeOffscreenDocument() {
  if (!chrome.offscreen) throw new Error('chrome.offscreen not exposed');
  const existing = await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] });
  if (!existing.length) {
    await chrome.offscreen.createDocument({
      url: 'offscreen.html',
      // `TESTING` requires a command-line switch; DOM_SCRAPING works on release builds.
      reasons: ['DOM_SCRAPING'],
      justification: 'MV3 capability probe'
    });
  }
  const contexts = await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] });
  await chrome.offscreen.closeDocument();
  return `create+getContexts+close ok (contexts=${contexts.length})`;
}

async function probeIdentityApi() {
  if (!chrome.identity) throw new Error('chrome.identity not exposed');
  return `launchWebAuthFlow exists=${typeof chrome.identity.launchWebAuthFlow === 'function'}`;
}

async function probeCaptureVisibleTab() {
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!tab || tab.windowId == null) return 'no window';
  try {
    const dataUrl = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'jpeg', quality: 40 });
    return `captured ${Math.round((dataUrl || '').length / 1024)}KB`;
  } catch (e) {
    throw new Error(describeError(e));
  }
}

const PROBE_ITEMS = [
  ['runtime.getManifest', probeRuntimeGetManifest],
  ['runtime.getURL', probeRuntimeGetUrl],
  ['runtime.id', probeRuntimeId],
  ['runtime.getPlatformInfo', probeRuntimePlatform],
  ['storage.local set+get', probeStorageLocal],
  ['storage.session set+get', probeStorageSession],
  ['storage.sync set+get', probeStorageSync],
  ['alarms.create+getAll', probeAlarms],
  ['tabs.query(active)', probeTabsQuery],
  ['tabs.create/update(exists)', probeTabsCreateUpdate],
  ['scripting.executeScript', probeScriptingExecute],
  ['cookies.getAll', probeCookies],
  ['notifications.create', probeNotifications],
  ['contextMenus.create', probeContextMenus],
  ['webNavigation.events', probeWebNavigationEvents],
  ['declarativeNetRequest.dynamicRules', probeDnrDynamicRules],
  ['userScripts.getScripts', probeUserScriptsGet],
  ['userScripts.register', probeUserScriptsRegister],
  ['sidePanel.getOptions/setOptions', probeSidePanel],
  ['downloads.download(exists)', probeDownloads],
  ['i18n.getMessage', probeI18n],
  ['action.setBadgeText/setIcon', probeActionBadgeIcon],
  ['offscreen.createDocument', probeOffscreenDocument],
  ['debugger.attach(exists)', probeDebugger],
  ['cookies.set/get/remove', probeCookiesWrite],
  ['tabGroups.group+update+query', probeTabGroups],
  ['webRequest.events', probeWebRequestEvents],
  ['scripting.executeScript(MAIN)', probeMainWorldScripting],
  ['identity.launchWebAuthFlow', probeIdentityApi],
  ['tabs.captureVisibleTab', probeCaptureVisibleTab]
];

/* ------------------------------------------------------------------ */
/* runner                                                              */
/* ------------------------------------------------------------------ */

async function runProbe(trigger) {
  const startedAt = Date.now();
  const items = [];

  for (const [api, fn] of PROBE_ITEMS) {
    const record = { api, ok: false, detail: '', error: null };
    try {
      const detail = await withTimeout(fn(), ITEM_TIMEOUT_MS, api);
      record.ok = true;
      record.detail = clip(detail);
    } catch (e) {
      record.ok = false;
      record.detail = 'probe failed';
      record.error = describeError(e);
    }
    items.push(record);
  }

  const pass = items.filter((item) => item.ok).length;
  const fail = items.length - pass;
  const meta = {
    probeVersion: PROBE_VERSION,
    schema: 1,
    trigger: String(trigger || 'unknown'),
    runAt: startedAt,
    durationMs: Date.now() - startedAt,
    pass,
    fail,
    total: items.length,
    manifest: chrome.runtime.getManifest().version,
    ua: navigator.userAgent,
    platform: (typeof navigator.platform === 'string' && navigator.platform) || '',
    bootCount: bootCount.module,
    dnrTestRuleId: DNR_TEST_RULE_ID,
    dnrTestUrl: DNR_TEST_URL
  };

  lastResults = items;
  // Machine-readable single line for `adb logcat | grep PROBE_JSON`.
  // Chrome mirrors service-worker console output to logcat as "CONSOLE(...)".
  console.log('PROBE_JSON ' + JSON.stringify({ meta, results: items }));
  const storageKey = LOG_PREFIX + startedAt;
  await chrome.storage.local.set({
    [storageKey]: items,
    [KEY_LATEST]: items,
    [KEY_META]: meta
  });
  await pruneLogs();

  try {
    await chrome.action.setBadgeText({ text: fail === 0 ? 'OK' : String(fail) });
    await chrome.action.setBadgeBackgroundColor({ color: fail === 0 ? '#15803d' : '#b91c1c' });
  } catch (e) {
    /* badge is itself a probe item; ignore */
  }

  try {
    await ensureTestBlockRule();
  } catch (e) {
    /* recorded by the DNR item when it matters */
  }

  return { meta, results: items };
}

function startProbe(trigger) {
  if (runningProbe) return runningProbe;
  runningProbe = runProbe(trigger)
    .catch((e) => ({
      meta: { trigger: String(trigger || 'unknown'), runAt: Date.now(), error: describeError(e) },
      results: lastResults || []
    }))
    .finally(() => {
      runningProbe = null;
    });
  return runningProbe;
}

// `probe:run` must produce a run whose meta.trigger is "message", so wait out
// any in-flight boot/install probe first instead of joining it.
async function runProbeNow(trigger) {
  if (runningProbe) {
    try {
      await runningProbe;
    } catch (e) {
      /* the fresh run below reports its own errors */
    }
  }
  return startProbe(trigger);
}

async function getLatest() {
  if (lastResults) {
    const stored = await chrome.storage.local.get([KEY_META]);
    return { meta: stored[KEY_META] || null, results: lastResults };
  }
  const stored = await chrome.storage.local.get([KEY_LATEST, KEY_META]);
  return { meta: stored[KEY_META] || null, results: stored[KEY_LATEST] || [] };
}

async function pruneLogs() {
  try {
    const all = await chrome.storage.local.get(null);
    const keys = Object.keys(all)
      .filter((key) => /^probe:\d+$/.test(key))
      .sort();
    const excess = keys.slice(0, Math.max(0, keys.length - KEEP_LOG_COUNT));
    if (excess.length) await chrome.storage.local.remove(excess);
  } catch (e) {
    /* pruning is best-effort */
  }
}

/* ------------------------------------------------------------------ */
/* DNR effectiveness test (navigates a throwaway tab)                  */
/* ------------------------------------------------------------------ */

// Listeners are installed BEFORE the tab is created, otherwise a fast
// ERR_BLOCKED_BY_CLIENT can land before the waiter exists. Filtering is by URL
// (only this probe navigates to DNR_TEST_URL), so no tab id is needed.
function watchDnrNavigation(timeoutMs) {
  let settled = false;
  let timer = null;
  let resolveFn = null;

  const matchesTarget = (url) => typeof url === 'string' && url.indexOf('/blocked-by-dnr') !== -1;

  function cleanup() {
    if (timer !== null) {
      clearTimeout(timer);
      timer = null;
    }
    try {
      chrome.webNavigation.onErrorOccurred.removeListener(onError);
      chrome.webNavigation.onCompleted.removeListener(onCompleted);
    } catch (e) {
      /* listeners may not have been added */
    }
  }

  function finish(outcome) {
    if (settled) return;
    settled = true;
    cleanup();
    if (resolveFn) resolveFn(outcome);
  }

  function onError(details) {
    if (details.frameId !== 0 || !matchesTarget(details.url)) return;
    finish({
      blocked: details.error === 'net::ERR_BLOCKED_BY_CLIENT',
      error: details.error || 'unknown',
      url: details.url || ''
    });
  }

  function onCompleted(details) {
    if (details.frameId !== 0 || !matchesTarget(details.url)) return;
    finish({ blocked: false, error: null, url: details.url || '' });
  }

  const promise = new Promise((resolve) => {
    resolveFn = resolve;
  });

  try {
    chrome.webNavigation.onErrorOccurred.addListener(onError);
    chrome.webNavigation.onCompleted.addListener(onCompleted);
    timer = setTimeout(() => finish({ blocked: null, error: 'timeout', url: DNR_TEST_URL }), timeoutMs);
  } catch (e) {
    finish({ blocked: null, error: 'listener error: ' + describeError(e), url: DNR_TEST_URL });
  }

  return { promise, cancel: () => finish({ blocked: null, error: 'cancelled', url: DNR_TEST_URL }) };
}

async function runDnrEffectTest() {
  await ensureTestBlockRule();
  const waiter = watchDnrNavigation(NAV_TIMEOUT_MS);
  let tab = null;
  try {
    tab = await chrome.tabs.create({ url: DNR_TEST_URL, active: false });
  } catch (e) {
    waiter.cancel();
    throw e;
  }
  if (!tab || typeof tab.id !== 'number') {
    waiter.cancel();
    throw new Error('tabs.create did not return a tab id');
  }
  const outcome = await waiter.promise;
  try {
    await chrome.tabs.remove(tab.id);
  } catch (e) {
    /* tab may already be gone */
  }
  return {
    url: DNR_TEST_URL,
    ruleId: DNR_TEST_RULE_ID,
    blocked: outcome.blocked,
    error: outcome.error,
    navEvents: { committed: netEvents.committed, completed: netEvents.completed, errors: netEvents.errors }
  };
}

/* ------------------------------------------------------------------ */
/* lifecycle + messaging                                               */
/* ------------------------------------------------------------------ */

chrome.runtime.onInstalled.addListener(() => {
  bootCount.module += 1;
  startProbe('onInstalled');
});

chrome.runtime.onStartup.addListener(() => {
  bootCount.module += 1;
  startProbe('onStartup');
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || typeof message !== 'object' || typeof message.type !== 'string') return;

  if (message.type === 'probe:run') {
    runProbeNow('message').then(
      (payload) => sendResponse({ ok: true, payload }),
      (e) => sendResponse({ ok: false, error: describeError(e) })
    );
    return true;
  }

  if (message.type === 'probe:latest') {
    getLatest().then(
      (payload) => sendResponse({ ok: true, payload }),
      (e) => sendResponse({ ok: false, error: describeError(e) })
    );
    return true;
  }

  if (message.type === 'probe:dnr-effect') {
    runDnrEffectTest().then(
      (outcome) => sendResponse({ ok: true, payload: outcome }),
      (e) => sendResponse({ ok: false, error: describeError(e) })
    );
    return true;
  }

  if (message.type === 'content:ready') {
    const record = {
      url: (message && message.url) || '',
      tabId: sender && sender.tab ? sender.tab.id : null,
      ts: Date.now()
    };
    chrome.storage.local
      .set({ [KEY_CONTENT_LAST]: record })
      .catch(() => {})
      .then(() => sendResponse({ ok: true }))
      .catch(() => sendResponse({ ok: false }));
    return true;
  }

  return;
});

/* Boot probe: every service-worker evaluation runs one, which is also the
 * evidence used for `service_worker_wakeup` (meta.runAt advances on wake). */
bootCount.module += 1;
startProbe('boot');

// Expose for debugging from a devtools console attached to the SW.
self.lumoProbe = { run: () => startProbe('manual'), latest: getLatest, dnrEffect: runDnrEffectTest };
