# 安全策略（SECURITY）

## 1. 报告漏洞

本仓库是自构建的 Chromium 发行配置（补丁 + 脚本），安全边界由上游 Chromium 决定。
请按问题归属选择渠道：

| 问题类型 | 渠道 |
|---|---|
| Chromium 内核漏洞（渲染器、沙箱、V8、Mojo…） | 上游 [Chromium Security](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/)；**不要**只开本仓库 issue |
| 本仓库补丁引入的问题（`patches/`） | 本仓库私有安全报告（GitHub Security Advisory）或维护者私下联系 |
| 构建/签名/扩展装载脚本的问题（`scripts/`） | 同上 |
| dev 签名密钥被误用于正式分发 | 立即按 §4 处理并公开说明 |

报告请包含：影响版本（`chrome://version` 或 `artifacts/cache/kernel-*.txt`）、复现步骤、
设备信息、logcat 片段、以及是否能通过 `--load-extension` 或恶意网页触发。

## 2. 威胁模型（明确的边界）

本项目的定位是**开发/自测发行版**，以下事实必须公开且不要误解：

1. **dev 签名密钥是公开的。** `keys/lumo-dev.jks` 故意入库，密码写在 `keys/README.md`。
   任何人都能签出同包名、同证书的 APK。签名**不提供**任何来源可信性。
   - 官方包校验方式：比对 `artifacts/cache/kernel-*.txt` 里的 `apk sha256`，而不是看证书。
   - 正式分发必须另建 release key（不入库、走 CI secret），并更换包名或卸载重装。
2. **命令行通道只走 `debug-app` 握手。** 扩展与 feature flag 通过
   `/data/local/tmp/chrome-command-line` 注入，需要 `am set-debug-app --persistent` 才生效。
   脚本会主动删除共享存储里的同名文件（`/sdcard/Android/data/<pkg>/files/chrome-command-line`），
   避免任何拥有 all-files 权限的 App 注入 `--load-extension` / `--remote-debugging-port`。
3. **`chrome://extensions` 的“加载未打包”是用户路径**，需要用户显式开启开发者模式；
   与命令行通道相互独立。
4. **用户脚本默认允许（补丁 0008）是产品质量决策，不是安全边界。** 扩展仍需声明
   `userScripts` 权限，用户可在扩展详情页关闭；默认值变更记录在 `patches/README.md`。
5. **不修改 Chromium 的沙箱、站点隔离、权限模型。** 补丁集只涉及 UI 承载点、side panel
   宿主生命周期、GPU 信息收集回退、feature 默认值。

## 3. 已知残留风险

| 风险 | 缓解 |
|---|---|
| dev key 可被伪造 | 只用于自测；发布走 release key；文档不承诺“签名=官方” |
| `--remote-debugging-port=9222` 在验证期间开启 | 仅 `verify.sh` / `lumo-e2e.sh` 使用；验证结束用 `flags.sh clear` |
| 扩展载荷放在 app 外部目录（`Android/data/<pkg>/files/ext`）可被 adb 改写 | 仅开发/验证用；生产应走扩展商店或 CRX 安装流程 |
| 自构建无 PGO、无官方更新通道 | 文档明确（`docs/07-capability-matrix.md`、`docs/09`） |
| MIUI 上 root `pm install` 绕过安装器校验 | 仅本机开发流程；不进入分发路径 |

## 4. 密钥泄露响应

如果 **release key** 泄露（未来引入）：

1. 立刻停止分发，发布公告；
2. 用新 key 重新签包，**更换包名**（同包名不同签名无法覆盖升级）；
3. 在商店提交新版本并说明迁移方式；
4. 保留旧包的哈希清单，供用户校验历史版本。

dev key（`keys/lumo-dev.jks`）“泄露”不需要响应——它本来就是公开的；需要做的是**确认它没有
被用于正式分发**（`apksigner verify --print-certs` 的证书指纹应为
`14:43:04:4D:CF:...:80:52:5E`，且只出现在 debug 产物里）。

## 5. 安全相关阅读

- `docs/08-security-and-hardening.md`：本分支的安全决策与补丁审计
- `keys/README.md`：签名密钥的公开声明
- `docs/03-verification.md`：验收如何避免“看起来通过”
