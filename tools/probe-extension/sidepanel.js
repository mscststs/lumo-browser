'use strict';

/* Minimal interactive side panel: proves the panel document gets a live DOM
 * and JS event loop, and that it can round-trip a message to a content script. */

const $ = (id) => document.getElementById(id);
const openedAt = Date.now();
let visibilityChanges = 0;

function send(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, (response) => {
      const err = chrome.runtime.lastError;
      if (err) {
        reject(new Error(err.message || 'runtime.lastError'));
        return;
      }
      resolve(response);
    });
  });
}

function sendToTab(tabId, message, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('tabs.sendMessage timeout')), timeoutMs || 2500);
    chrome.tabs.sendMessage(tabId, message, (response) => {
      clearTimeout(timer);
      const err = chrome.runtime.lastError;
      if (err) {
        reject(new Error(err.message || 'runtime.lastError'));
        return;
      }
      resolve(response);
    });
  });
}

function renderState() {
  $('k-visibility').textContent = document.visibilityState;
  $('k-hidden').textContent = String(document.hidden);
  $('k-focus').textContent = String(document.hasFocus());
  $('k-opened').textContent = new Date(openedAt).toISOString();
  $('k-changes').textContent = String(visibilityChanges);
  $('k-id').textContent = chrome.runtime.id;
}

function showPing(value) {
  $('ping-out').textContent =
    typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}

async function pingContent() {
  const btn = $('btn-ping');
  btn.disabled = true;
  showPing('发送中…');
  try {
    const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (!tabs.length) throw new Error('没有活动标签页');
    const tab = tabs[0];
    const response = await sendToTab(tab.id, { type: 'lumo:ping' }, 2500);
    showPing({ tabId: tab.id, tabUrl: tab.url || '', response });
  } catch (e) {
    showPing('Ping 失败: ' + (e && e.message ? e.message : String(e)));
  } finally {
    btn.disabled = false;
  }
}

async function runProbe() {
  const btn = $('btn-run');
  const out = $('probe-out');
  btn.disabled = true;
  out.textContent = '运行中…';
  try {
    const response = await send({ type: 'probe:run' });
    if (!response || !response.ok) throw new Error((response && response.error) || 'probe:run failed');
    const meta = response.payload.meta || {};
    out.textContent = JSON.stringify(
      {
        pass: meta.pass,
        fail: meta.fail,
        total: meta.total,
        durationMs: meta.durationMs,
        runAt: meta.runAt,
        trigger: meta.trigger
      },
      null,
      2
    );
  } catch (e) {
    out.textContent = '运行失败: ' + (e && e.message ? e.message : String(e));
  } finally {
    btn.disabled = false;
  }
}

document.addEventListener('visibilitychange', () => {
  visibilityChanges += 1;
  renderState();
});

$('btn-ping').addEventListener('click', pingContent);
$('btn-run').addEventListener('click', runProbe);

renderState();
