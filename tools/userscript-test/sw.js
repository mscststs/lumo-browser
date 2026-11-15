// Registers a user script in the USER_SCRIPT world. The script mutates the DOM
// so the harness can assert on rendered text (not just on API availability).
const SCRIPT_ID = 'lumo-userscript-runtime-test';

async function register() {
  try {
    const existing = await chrome.userScripts.getScripts({ ids: [SCRIPT_ID] });
    if (existing && existing.length) await chrome.userScripts.unregister({ ids: [SCRIPT_ID] });
  } catch (e) {
    console.warn('[lumo-userscript-test] cleanup failed', e);
  }
  await chrome.userScripts.register([{
    id: SCRIPT_ID,
    matches: ['https://example.com/*'],
    js: [{ code: "document.body.insertAdjacentHTML('afterbegin','<div id=\"lumo-userscript-proof\">LUMO_USERSCRIPT_OK</div>');" }],
    world: 'USER_SCRIPT',
    runAt: 'document_idle'
  }]);
  console.log('[lumo-userscript-test] registered', SCRIPT_ID);
}

chrome.runtime.onInstalled.addListener(register);
chrome.runtime.onStartup.addListener(register);
register();
