---
name: device-verification
description: Install Lumo Browser on a rooted Android device, load extensions, and prove a change works with recorded evidence. Use when asked to install/launch the APK, chase MIUI install or SELinux errors, load ../lumo or the probe extension, run verify.sh or the Lumo end-to-end test, take screenshots/logcat evidence, or confirm the GATE=OK acceptance criteria.
---

# 真机安装与验收

设备基线：Redmi K20 Pro / Android 11 / API 30 / arm64-v8a / Magisk root。
模拟器只做冒烟，**证据必须来自真机**。

## 0. 三条铁律

1. **没有证据 = 没做完**。所有结论落到 `artifacts/verify/<run-id>/`（截图 / logcat / probe.json / summary）。
2. **不要卸载了事**。APK 用仓库 dev key 签名，`pm install -r` 可覆盖升级；卸载会清掉 profile、
   扩展状态和用户脚本开关。
3. **命令行只有一个入口**：`scripts/chromium/flags.sh`。不要手写 `--load-extension`（重复 flag 只生效最后一个）。

## 1. 标准流程

```bash
scripts/chromium/doctor.sh          # 0. 环境（adb 设备 + 源码 + 签名）
scripts/device/install.sh           # 1. push + su pm install（MIUI 兼容路径）
scripts/device/ext-install.sh       # 2. 推扩展 + 写命令行 + set-debug-app + 冷启动
scripts/device/verify.sh            # 3. 30 项探针 + 扩展/SW + 侧栏/关闭回归 + GATE
scripts/verify/lumo-e2e.sh          # 4. Lumo 侧栏 + 本地 mock OpenAI 端到端
```

只想要一张截图：`scripts/device/shot.sh`（默认写入 `artifacts/shots/<ts>.png`）。
只想重启浏览器：`scripts/device/launch.sh`。

## 2. 判定看什么

| 文件 | 判定 |
|---|---|
| `summary.txt` | 必须包含 `GATE=OK` |
| `probe.json` | `meta.fail` 只允许“探针故意未声明权限”的项（offscreen/debugger） |
| `extensions-strings.txt` | 出现 3 个扩展名 + 三个 `Service Worker`（不是「（无效）」） |
| `screen-*.png` | 首页、扩展页、侧栏、popup 四类 |
| `close-panel.txt` | `close_panel=ok` |
| `logcat.txt` | `grep -E "cr_CommandLine|Failed to load extension|PROBE_JSON"` 无异常 |

细节与判定陷阱见 `references/evidence-and-gates.md`。

## 3. 扩展装载（机制）

```
adb push <ext> /sdcard/Android/data/dev.lumo.browser/files/ext/<name>
flags.sh push   → /data/local/tmp/chrome-command-line  (--load-extension=a,b,c)
                → am set-debug-app --persistent dev.lumo.browser
```

- 载荷放 **app 外部目录**：`/data/data` 在 MIUI + SELinux 下不可读，`/data/local` 权限也别扭。
- 命令行只从 `/data/local/tmp` 读，通过 debug-app 握手生效；共享存储里的同名文件会被 `flags.sh` 删除。
- 探针目录带内容哈希（`probe-<sha10>`），避免 Chrome 复用旧扩展脚本缓存。

## 4. 高频故障

见 `references/miui-and-adb.md`。三条最常撞：

1. `adb install` 报 “canceled by user” → MIUI 限制；走 `install.sh` 的 root `pm install`。
2. 扩展列表里没有某个扩展 / 显示「无效」→ 先看 logcat 的 `Failed to load extension`；
   SW 需要被唤醒才显示，打开扩展页后等 5–10 s 再 dump。
3. `scripting.executeScript` 失败 → 当前活动页可能是 `chrome://extensions`（不可注入），
   先导航到普通网页再测。

## 5. CDP（不是必须，但排查很快）

```bash
tools/cdp.py list                      # 目标列表（需要 --remote-debugging-port=9222）
tools/cdp.py eval <target> "location.href"
tools/cdp.py type <target> "text"
```

`verify.sh` 已经在命令行里带了 `--remote-debugging-port=9222`；
手工用完后执行 `scripts/chromium/flags.sh clear` 关掉，避免长期暴露调试端口。

## 6. 禁止

- 用 `setenforce 0` 掩盖 SELinux 权限问题（可以临时验证根因，但不得作为方案）。
- 把扩展放到 `/data/data/<pkg>` 或共享存储的任意位置（前者读不到，后者可被其他 App 篡改）。
- 只贴一句“验证通过”而没有 `summary.txt` / 截图 / probe.json 路径。
- 在没卸载重装的情况下声称“全新安装也正常”（签名与 profile 会影响结论）。

## 7. 参考

- `references/miui-and-adb.md`：MIUI/SELinux/adb 的坑与对应命令
- `references/evidence-and-gates.md`：证据目录结构、30 项探针、判定陷阱
- 仓库内：`docs/03-verification.md`、`docs/02-capabilities.md`
