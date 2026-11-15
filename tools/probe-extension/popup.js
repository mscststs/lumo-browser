'use strict';

/* Toolbar popup: quick pass/fail glance + rerun + jump to options page. */

const $ = (id) => document.getElementById(id);

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

function renderStats(meta) {
  if (!meta) {
    $('hint').textContent = '还没有探针结果，点击「重新运行」。';
    return;
  }
  $('stat-pass').textContent = String(meta.pass);
  $('stat-fail').textContent = String(meta.fail);
  $('hint').textContent =
    '最近运行 trigger=' + String(meta.trigger || '?') + ' · ' + String(meta.durationMs || 0) + 'ms';
}

async function load() {
  const manifest = chrome.runtime.getManifest();
  $('manifest-line').textContent = manifest.name + ' v' + manifest.version;
  try {
    const stored = await chrome.storage.local.get(['probe:meta']);
    renderStats(stored['probe:meta'] || null);
  } catch (e) {
    $('hint').textContent = '读取失败: ' + (e && e.message ? e.message : String(e));
  }
}

async function rerun() {
  const btn = $('btn-run');
  btn.disabled = true;
  btn.textContent = '运行中…';
  try {
    const response = await send({ type: 'probe:run' });
    if (!response || !response.ok) throw new Error((response && response.error) || 'probe:run failed');
    renderStats(response.payload.meta);
  } catch (e) {
    $('hint').textContent = '运行失败: ' + (e && e.message ? e.message : String(e));
  } finally {
    btn.disabled = false;
    btn.textContent = '重新运行';
  }
}

$('btn-run').addEventListener('click', rerun);
$('btn-open').addEventListener('click', () => {
  chrome.runtime.openOptionsPage();
});

load();
