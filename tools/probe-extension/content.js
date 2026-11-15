'use strict';

/*
 * Isolated-world content script.
 *
 * 1. Marks the isolated world with window.__lumoProbe (invisible to page JS).
 * 2. Mirrors a DOM marker so testpage.html can prove injection from page JS.
 * 3. Answers {type:'lumo:ping'} from the SW / side panel / popup.
 * 4. Announces itself to the SW once per document.
 * 5. Relays an explicitly namespaced page -> extension message so
 *    testpage.html can trigger the DNR effectiveness test.
 */

const PROBE_DOM_ATTR = 'data-lumo-probe';

try {
  window.__lumoProbe = { world: 'isolated', ts: Date.now(), url: location.href };
} catch (e) {
  /* ignore: some documents have frozen globals */
}

try {
  if (document.documentElement) {
    document.documentElement.setAttribute(PROBE_DOM_ATTR, 'isolated');
  } else {
    document.addEventListener(
      'readystatechange',
      () => {
        try {
          document.documentElement.setAttribute(PROBE_DOM_ATTR, 'isolated');
        } catch (e) {
          /* ignore */
        }
      },
      { once: true }
    );
  }
} catch (e) {
  /* ignore */
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || typeof message !== 'object') return;
  if (message.type === 'lumo:ping') {
    sendResponse({
      pong: true,
      world: 'isolated',
      url: location.href,
      ts: Date.now(),
      domMarker: document.documentElement
        ? document.documentElement.getAttribute(PROBE_DOM_ATTR)
        : null
    });
  }
});

// Page-world bridge: only for the namespaced test page.
window.addEventListener('message', (event) => {
  if (event.source !== window) return;
  const data = event.data;
  if (!data || typeof data !== 'object' || data.source !== 'lumo-probe-page') return;

  if (data.type === 'ping') {
    window.postMessage(
      {
        source: 'lumo-probe-content',
        type: 'pong',
        payload: { world: 'isolated', url: location.href, ts: Date.now() }
      },
      '*'
    );
    return;
  }

  if (data.type === 'dnr-effect') {
    chrome.runtime.sendMessage({ type: 'probe:dnr-effect' }, (response) => {
      const err = chrome.runtime.lastError;
      window.postMessage(
        {
          source: 'lumo-probe-content',
          type: 'dnr-effect-result',
          payload: err ? { ok: false, error: err.message } : response
        },
        '*'
      );
    });
  }
});

try {
  chrome.runtime.sendMessage({ type: 'content:ready', url: location.href }, () => {
    // Reading lastError prevents "Unchecked runtime.lastError" noise.
    void chrome.runtime.lastError;
  });
} catch (e) {
  /* ignore */
}
