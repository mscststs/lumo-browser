#!/usr/bin/env bash
# Static checks for the probe extension + verify manifest.
# No browser required: node --check, JSON parsing, CSP/external-resource grep,
# and a manifest/weight consistency check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT="$ROOT/tools/probe-extension"
VERIFY="$ROOT/tools/verify"
fail=0

note() { printf '  %s\n' "$*"; }
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; fail=1; }

echo "== node --check =="
if ! command -v node >/dev/null 2>&1; then
  bad "node 不可用，无法执行 node --check"
else
  while IFS= read -r file; do
    if node --check "$file" >/dev/null 2>&1; then
      ok "node --check ${file#"$ROOT"/}"
    else
      bad "node --check ${file#"$ROOT"/}"
      node --check "$file" || true
    fi
  done < <(find "$EXT" -name '*.js' -type f | sort)
fi

echo "== JSON =="
for file in "$EXT/manifest.json" "$VERIFY/manifest.json"; do
  if python3 -m json.tool "$file" >/dev/null; then
    ok "json ${file#"$ROOT"/}"
  else
    bad "json ${file#"$ROOT"/}"
  fi
done

echo "== CSP / 外部资源 =="
if grep -RInE '(src|href)="(https?:)?//' "$EXT" --include='*.html' --include='*.css'; then
  bad "发现外链资源（src/href 指向 // 或 http(s)）"
else
  ok "HTML/CSS 无外链资源"
fi

if grep -RInE '<script[^>]*>[^<]' "$EXT" --include='*.html'; then
  bad "发现内联 <script>（MV3 CSP 只允许 script-src 'self'）"
else
  ok "无内联 <script>"
fi

if grep -RInE 'eval\(|new Function|[^a-zA-Z_.]Function\(' "$EXT" --include='*.js'; then
  bad "发现 eval / new Function"
else
  ok "无 eval / new Function"
fi

if grep -RInE 'import\s*\(|from [\x27"][^\x27"]+[\x27"]' "$EXT" --include='*.js'; then
  note "提示：以上为 import 匹配，确认是本地相对路径即可"
else
  ok "无 ESM/远程 import"
fi

echo "== manifest 结构 =="
if python3 - "$EXT/manifest.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
errors = []
if m.get('manifest_version') != 3:
    errors.append('manifest_version != 3')
if m.get('name') != 'Lumo MV3 Probe':
    errors.append('name 不是 "Lumo MV3 Probe"')
if m.get('version') != '0.1.0':
    errors.append('version 不是 0.1.0')
required_perms = {
    'storage', 'unlimitedStorage', 'tabs', 'scripting', 'sidePanel',
    'webNavigation', 'declarativeNetRequest', 'declarativeNetRequestWithHostAccess',
    'cookies', 'downloads', 'notifications', 'alarms', 'contextMenus',
    'userScripts', 'clipboardWrite', 'activeTab',
}
missing = required_perms - set(m.get('permissions', []))
if missing:
    errors.append('缺少 permissions: ' + ', '.join(sorted(missing)))
if m.get('host_permissions') != ['<all_urls>']:
    errors.append('host_permissions 必须是 ["<all_urls>"]')
if m.get('background', {}).get('service_worker') != 'sw.js':
    errors.append('background.service_worker != sw.js')
if m.get('action', {}).get('default_popup') != 'popup.html':
    errors.append('action.default_popup != popup.html')
if m.get('options_ui', {}).get('page') != 'probe.html' or m.get('options_ui', {}).get('open_in_tab') is not True:
    errors.append('options_ui.page/open_in_tab 不正确')
if m.get('side_panel', {}).get('default_path') != 'sidepanel.html':
    errors.append('side_panel.default_path != sidepanel.html')
if errors:
    print('  ' + '\n  '.join(errors))
    sys.exit(1)
print('  manifest 字段符合约定')
PY
then
  ok "manifest 结构"
else
  bad "manifest 结构"
fi

echo "== verify 清单 =="
if python3 - "$VERIFY/manifest.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
items = m.get('items') or []
required = [
    'ext_installed', 'sw_running', 'storage_rw', 'alarms', 'notifications',
    'tabs_query', 'scripting_execute', 'content_script_isolated',
    'runtime_messaging', 'dnr_dynamic_rules', 'dnr_block_effective', 'cookies',
    'webnavigation_events', 'contextmenus', 'action_badge', 'user_scripts_api',
    'side_panel_open', 'side_panel_interactive', 'options_page', 'popup_page',
    'service_worker_wakeup',
]
errors = []
ids = [i.get('id') for i in items]
for rid in required:
    if rid not in ids:
        errors.append('缺少条目: ' + rid)
if len(ids) != len(set(ids)):
    errors.append('id 重复')
for item in items:
    if not item.get('title') or not isinstance(item.get('weight'), int) or not item.get('how'):
        errors.append('条目字段不完整: ' + str(item.get('id')))
total = sum(i.get('weight', 0) for i in items)
if total != m.get('total_weight'):
    errors.append(f'weight 合计 {total} != total_weight {m.get("total_weight")}')
if errors:
    print('  ' + '\n  '.join(errors))
    sys.exit(1)
print(f'  {len(items)} 条，weight 合计 {total}')
PY
then
  ok "verify 清单"
else
  bad "verify 清单"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "静态检查未通过"
  exit 1
fi

if command -v node >/dev/null 2>&1; then
  echo "== SW 冒烟（Node + 假 chrome.* 表面，非浏览器测试）=="
  HARNESS_OUT="$(mktemp)"
  if node "$VERIFY/sw-harness.js" "$EXT/sw.js" >"$HARNESS_OUT" 2>&1; then
    tail -n 4 "$HARNESS_OUT"
    ok "SW 冒烟：全部探针项产出，probe:run/content:ready/dnr-effect 路径可用"
  else
    cat "$HARNESS_OUT"
    bad "SW 冒烟失败"
  fi
  rm -f "$HARNESS_OUT"
else
  note "跳过 SW 冒烟（node 不可用）"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "检查未通过"
  exit 1
fi
echo "静态检查全部通过"
