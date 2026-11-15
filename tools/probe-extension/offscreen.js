// Minimal offscreen document used to prove chrome.offscreen lifecycle support.
document.getElementById('status').textContent = 'offscreen-ready';
chrome.runtime.sendMessage({ type: 'offscreen:ready' }).catch(() => {});
