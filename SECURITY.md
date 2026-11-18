# 安全策略（SECURITY）

## 1. 报告漏洞

| 问题类型 | 渠道 |
|---|---|
| Chromium 内核（渲染器、沙箱、V8、Mojo…） | 上游 [Chromium Security](https://www.chromium.org/Home/chromium-security/reporting-security-bugs/)；不要只开本仓库 issue |
| 本仓库补丁（`patches/`）、脚本、签名 | GitHub Security Advisory 或维护者私下联系 |

报告请附：影响版本（`chrome://version` 或 `artifacts/cache/kernel-*.txt`）、复现步骤、设备信息、
logcat 片段，以及是否能通过恶意网页或 `--load-extension` 触发。

## 2. 威胁模型

本仓库是**开发/自测发行版**，以下事实是设计前提，不要误解：

1. **dev 签名密钥是公开的**（`keys/lumo-dev.jks`，口令写在 `keys/README.md`）。
   任何人可签同包名、同证书的 APK，签名**不提供**来源可信性。
   - 校验包的方式：比对 `artifacts/cache/kernel-*.txt` 里的 `apk sha256`，而不是看证书。
   - 正式分发必须另建 release key（不入库，走 CI secret），并更换包名或卸载重装。
2. **命令行通道只走 debug-app 握手**，不读共享存储。
   - 文件：`/data/local/tmp/chrome-command-line`，需要 `am set-debug-app --persistent` 才生效。
   - 共享存储里的同名文件（`/sdcard/Android/data/<pkg>/files/chrome-command-line`）由 `flags.sh` 主动删除：
     该目录任何拥有 all-files 权限的应用都能写，而 flag 里包含 `--load-extension`、
     `--remote-debugging-port` 等，等于任意代码执行入口。
3. **扩展载荷目录是开发期机制**。`/sdcard/Android/data/<pkg>/files/ext/` 可被 adb 改写，
   仅用于装载未打包扩展；正式分发应走扩展商店或 CRX 安装流程。
4. **`userScripts` 默认允许是产品决策，不是安全边界**（补丁 0008）。
   扩展仍须声明 `userScripts` 权限，用户可在扩展详情页关闭；关闭后 API 返回明确错误。
5. **不修改 Chromium 的沙箱、站点隔离、权限模型**。补丁只涉及 UI 承载点、side panel 宿主生命周期、
   GPU 信息收集回退、feature 默认值。

## 3. 补丁的安全约束

| 补丁 | 约束 |
|---|---|
| 0002 / 0009 | 只增加/接线 UI 承载点与锚点，不改变扩展权限模型 |
| 0003 | 仅翻转 feature 默认值，可用 `--disable-features` 回退 |
| 0005 / 0006 | GPU 路径只在用户显式 opt-out 或驱动不支持时回退，不放宽站点隔离 |
| 0008 | `userScripts` 默认允许，但权限声明与用户开关仍然生效 |
| 0010 / 0011 | 窄屏宿主挂在 Activity 内容视图；关闭时必须从当前父容器 detach，且不销毁扩展 WebContents |

## 4. 已知残留风险

| 风险 | 缓解 |
|---|---|
| dev key 可被伪造 | 只用于自测；正式分发走 release key；文档不承诺"签名=官方" |
| `--remote-debugging-port=9222` 在验证期开启 | 仅 `verify.sh` / `lumo-e2e.sh` 使用；结束后 `scripts/chromium/flags.sh clear` |
| 无 PGO、无官方更新通道 | 明确为自构建发行版的限制 |
| MIUI 上 root `pm install` 绕过安装器校验 | 仅本机开发流程，不进入分发路径 |
| 手机工具栏未注册 width consumer | 暂不内联固定 action（走扩展菜单），若实现需补 measure 逻辑 |

## 5. 密钥泄露响应

release key（未来引入）泄露时：

1. 停止分发并公告；
2. 用新 key 重签，**更换包名**（同包名不同签名无法覆盖升级）；
3. 商店提交新版本并说明迁移；
4. 保留旧包哈希清单供用户校验。

dev key 泄露无需响应（它本来就公开）；需要确认的是它**没有**被用于正式分发：
`apksigner verify --print-certs` 的 SHA-256 应为
`14:43:04:4D:CF:72:11:1D:14:6C:28:A4:ED:27:E8:C7:D8:4A:63:32:76:4B:DF:13:87:17:AE:A5:18:80:52:5E`。

## 6. 相关

`keys/README.md`（签名边界与操作）、`docs/02-capabilities.md`（能力边界）、
`docs/03-verification.md`（验收口径）、`docs/04-ui-behaviour.md`（侧栏生命周期）。
