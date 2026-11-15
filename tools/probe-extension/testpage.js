'use strict';

/* Page-world test harness. This file runs in the *page* world, so it has no
 * access to chrome.*; everything goes through the namespaced postMessage bridge
 * implemented by content.js. */

(function () {
  const $ = (id) => document.getElementById(id);

  function setText(id, value) {
    const el = $(id);
    if (el) el.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  }

  /* ---------------- 1. injection markers ---------------- */

  function checkMarkers() {
    const windowMarker = window.__lumoProbe;
    const domMarker = document.documentElement.getAttribute('data-lumo-probe');
    setText(
      'k-world',
      windowMarker
        ? '可见: ' + JSON.stringify(windowMarker) + '（若可见说明隔离世界失效）'
        : '不可见（预期：隔离世界对页面不可见）'
    );
    setText(
      'k-dom',
      domMarker ? '可见: ' + domMarker : '不可见（content script 未注入或未运行）'
    );
  }

  /* ---------------- 2. page <-> content bridge ---------------- */

  function bridgePing() {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        window.removeEventListener('message', onMessage);
        reject(new Error('bridge timeout 2500ms（content script 可能未注入）'));
      }, 2500);

      function onMessage(event) {
        if (event.source !== window) return;
        const data = event.data;
        if (!data || data.source !== 'lumo-probe-content' || data.type !== 'pong') return;
        clearTimeout(timer);
        window.removeEventListener('message', onMessage);
        resolve(data.payload);
      }

      window.addEventListener('message', onMessage);
      window.postMessage({ source: 'lumo-probe-page', type: 'ping' }, '*');
    });
  }

  async function onBridgeClick() {
    setText('bridge-out', '发送中…');
    try {
      const payload = await bridgePing();
      setText('bridge-out', { ok: true, payload });
    } catch (e) {
      setText('bridge-out', '失败: ' + (e && e.message ? e.message : String(e)));
    }
  }

  /* ---------------- 3. DNR: fetch attempt ---------------- */

  async function onFetchClick() {
    const started = Date.now();
    setText('dnr-out', 'fetch 中…');
    try {
      const response = await fetch('https://example.com/blocked-by-dnr', {
        cache: 'no-store',
        mode: 'cors'
      });
      setText('dnr-out', {
        result: 'request completed (DNR 未 block)',
        status: response.status,
        ms: Date.now() - started
      });
    } catch (e) {
      setText('dnr-out', {
        result: 'fetch rejected（可能是 DNR block，也可能是 CORS/网络）',
        error: e && e.message ? e.message : String(e),
        ms: Date.now() - started,
        note: '仅凭 fetch 无法区分 block 与 CORS，请用导航探测'
      });
    }
  }

  /* ---------------- 4. DNR: navigation probe ---------------- */

  function dnrNavigationProbe() {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        window.removeEventListener('message', onMessage);
        reject(new Error('导航探测 timeout 12000ms（SW 未响应或 webNavigation 事件缺失）'));
      }, 12000);

      function onMessage(event) {
        if (event.source !== window) return;
        const data = event.data;
        if (!data || data.source !== 'lumo-probe-content') return;
        if (data.type !== 'dnr-effect-result') return;
        clearTimeout(timer);
        window.removeEventListener('message', onMessage);
        resolve(data.payload);
      }

      window.addEventListener('message', onMessage);
      window.postMessage({ source: 'lumo-probe-page', type: 'dnr-effect' }, '*');
    });
  }

  async function onDnrClick() {
    setText('dnr-out', '导航探测中（会短暂打开一个后台标签页）…');
    try {
      const payload = await dnrNavigationProbe();
      let verdict = '未知';
      if (payload && payload.ok) {
        const outcome = payload.payload || {};
        if (outcome.blocked === true) {
          verdict = 'DNR 生效：net::ERR_BLOCKED_BY_CLIENT';
        } else if (outcome.blocked === false && outcome.error) {
          verdict = '未判定（导航失败但不是 DNR block，error=' + outcome.error + '）';
        } else if (outcome.blocked === false) {
          verdict = 'DNR 未生效：导航正常完成';
        } else {
          verdict = 'DNR 未判定（timeout，见 raw.navEvents 与 webNavigation 事件计数）';
        }
      } else {
        verdict = '探测失败';
      }
      setText('dnr-out', { verdict, raw: payload });
    } catch (e) {
      setText('dnr-out', '失败: ' + (e && e.message ? e.message : String(e)));
    }
  }

  function onNavigateClick() {
    window.location.assign('https://example.com/blocked-by-dnr');
  }

  /* ---------------- wire ---------------- */

  $('btn-bridge').addEventListener('click', onBridgeClick);
  $('btn-fetch').addEventListener('click', onFetchClick);
  $('btn-dnr').addEventListener('click', onDnrClick);
  $('btn-navigate').addEventListener('click', onNavigateClick);

  checkMarkers();
  // content script may still be at document_start; re-check shortly after load.
  window.addEventListener('load', checkMarkers);
  setTimeout(checkMarkers, 500);
})();
