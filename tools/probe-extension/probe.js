'use strict';

/* Results panel for the probe extension. Reads probe:latest from storage and
 * renders it; the only side effects are an explicit rerun and an export. */

const $ = (id) => document.getElementById(id);

const state = { meta: null, results: [] };

function send(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, (response) => {
      const err = chrome.runtime.lastError;
      if (err) {
        reject(new Error(err.message || 'runtime.lastError'));
        return;
      }
      if (!response) {
        reject(new Error('no response from service worker'));
        return;
      }
      resolve(response);
    });
  });
}

function fmtTime(ms) {
  if (!ms) return '—';
  try {
    return new Date(ms).toISOString().replace('T', ' ').replace('.000Z', 'Z');
  } catch (e) {
    return String(ms);
  }
}

function setText(id, text) {
  const el = $(id);
  if (el) el.textContent = text;
}

function renderMeta() {
  const manifest = chrome.runtime.getManifest();
  setText('manifest-line', 'manifest: ' + manifest.name + ' v' + manifest.version + ' / probe v0.1.0');
  setText('ua-line', 'UA: ' + navigator.userAgent);

  const meta = state.meta;
  if (!meta) {
    setText('run-line', '最近运行: —');
    return;
  }
  const trigger = meta.trigger ? ' · trigger=' + meta.trigger : '';
  const platform = meta.platform ? ' · ' + meta.platform : '';
  setText('run-line', '最近运行: ' + fmtTime(meta.runAt) + trigger + platform);
}

function renderStats() {
  const results = state.results;
  const pass = results.filter((row) => row && row.ok).length;
  const fail = results.length - pass;
  setText('stat-pass', String(pass));
  setText('stat-fail', String(fail));
  setText('stat-total', String(results.length));
  const meta = state.meta || {};
  setText('stat-ms', typeof meta.durationMs === 'number' ? String(meta.durationMs) : '—');
  setText(
    'summary-line',
    String(pass) + ' pass / ' + String(fail) + ' fail / ' + String(results.length) + ' total'
  );
}

function cell(label, text, className) {
  const td = document.createElement('td');
  td.setAttribute('data-label', label);
  if (className) td.className = className;
  td.textContent = text;
  return td;
}

function renderRows() {
  const tbody = $('rows');
  tbody.textContent = '';
  const results = state.results;

  if (!results.length) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 4;
    td.className = 'empty';
    td.textContent = '还没有探针结果。点击「重新运行」。';
    tr.appendChild(td);
    tbody.appendChild(tr);
    return;
  }

  for (const item of results) {
    if (!item) continue;
    const tr = document.createElement('tr');

    const api = cell('api', String(item.api || '?'), 'api');

    const ok = document.createElement('td');
    ok.setAttribute('data-label', 'ok');
    const pill = document.createElement('span');
    pill.className = 'pill ' + (item.ok ? 'ok' : 'fail');
    pill.textContent = item.ok ? 'PASS' : 'FAIL';
    ok.appendChild(pill);

    const detail = cell('detail', String(item.detail || '—'), 'detail');
    const error = cell('error', item.error ? String(item.error) : '—', 'error');

    tr.appendChild(api);
    tr.appendChild(ok);
    tr.appendChild(detail);
    tr.appendChild(error);
    tbody.appendChild(tr);
  }
}

function renderAll() {
  renderMeta();
  renderStats();
  renderRows();
}

async function loadContentLast() {
  try {
    const stored = await chrome.storage.local.get(['probe:content:last']);
    const record = stored['probe:content:last'];
    const el = $('content-last');
    if (!el) return;
    if (!record) {
      el.textContent = '—（还没有页面触发 content:ready；先访问一个 http(s) 页面）';
      return;
    }
    el.textContent =
      fmtTime(record.ts) + ' · tab=' + String(record.tabId) + ' · ' + String(record.url || '');
  } catch (e) {
    setText('content-last', '读取失败: ' + (e && e.message ? e.message : String(e)));
  }
}

async function load() {
  try {
    const stored = await chrome.storage.local.get(['probe:latest', 'probe:meta']);
    state.results = stored['probe:latest'] || [];
    state.meta = stored['probe:meta'] || null;
  } catch (e) {
    state.results = [];
    state.meta = { runAt: Date.now(), error: String(e && e.message ? e.message : e) };
  }
  renderAll();
  await loadContentLast();
}

function applyPayload(payload) {
  if (!payload) return;
  if (Array.isArray(payload.results)) state.results = payload.results;
  if (payload.meta) state.meta = payload.meta;
  renderAll();
}

async function rerun() {
  const btn = $('btn-run');
  const original = btn.textContent;
  btn.disabled = true;
  btn.textContent = '运行中…';
  try {
    const response = await send({ type: 'probe:run' });
    if (!response.ok) throw new Error(response.error || 'probe:run failed');
    applyPayload(response.payload);
    await loadContentLast();
  } catch (e) {
    setText('run-line', '运行失败: ' + (e && e.message ? e.message : String(e)));
  } finally {
    btn.disabled = false;
    btn.textContent = original;
  }
}

function exportJson() {
  const payload = {
    exportedAt: new Date().toISOString(),
    manifest: chrome.runtime.getManifest(),
    userAgent: navigator.userAgent,
    meta: state.meta,
    results: state.results
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = 'probe-result.json';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

function wire() {
  $('btn-run').addEventListener('click', rerun);
  $('btn-export').addEventListener('click', exportJson);
}

wire();
load();
