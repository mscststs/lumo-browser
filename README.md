# Lumo Browser

基于 Chromium 的 Android 浏览器构建仓库：官方 tarball + 8 个补丁 + 构建/验证工具链。

## 结构

```
.agents/skills/   agent 手册（构建 / 补丁 / 真机验证）
.github/          CI 与 PR 模板
keys/             dev 签名密钥（仅 debug）
patches/          Chromium 补丁，按编号顺序应用
scripts/
  chromium/       取源码、依赖、工具链、打补丁、构建、签名、flags、缓存、诊断
  device/         安装、启动、扩展装载、验收、截图
  verify/         端到端验证（侧栏 + mock OpenAI）
  lib/            common.sh、signing.env
tools/            CDP、MV3 探针扩展、mock server、仓库检查
docs/             架构、验收、能力矩阵、迭代、ADR
artifacts/        （gitignored）APK、验证证据
```

产物：`artifacts/apk/lumo-<config>-<ts>.apk`；Chromium 源码与构建树在仓库外（`~/chromium/src`）。

## 功能

**内核（`patches/`，8 个）**

| # | 内容 |
|---|---|
| 0002 | 手机工具栏扩展承载点（`toolbar_phone.xml` + `ToolbarPhone` 接线） |
| 0003 | Android side panel 与手动调宽默认开启 |
| 0005 | 尊重 `--disable-features=Vulkan` |
| 0006 | GPU 信息收集允许 ES2 回退 |
| 0008 | `chrome.userScripts` 默认允许（扩展详情页可关） |
| 0009 | 扩展 popup 容器锚点回退 |
| 0010 | side panel 双形态：窄屏底部抽屉 / 宽屏并排可调宽 |
| 0011 | 关闭侧栏时从当前父容器 detach |

**扩展与验收**

- MV3 探针扩展：30 项 API（`tools/probe-extension/`、`tools/verify/manifest.json`）
- 参考扩展装载：`../lumo`、`../lumo-userscript-manager`
- 真机验收：`scripts/device/verify.sh`（探针 + 侧栏 + 关闭回归 → `GATE`）
- 端到端：`scripts/verify/lumo-e2e.sh` + `tools/mock-openai.py`

**构建工具**

- `build.sh`：补丁 → 签名 → 品牌化 → `gn gen` → siso 增量 → 归档
- `flags.sh`：设备命令行（`--enable-features` / `--load-extension`）
- `cache.sh`：内核身份 manifest、`out/` 快照与恢复
- `patchwork.sh`：源码树无 commit 时的补丁生成/回滚
- `doctor.sh`：环境预检

## 命令

```bash
make help                                  # 全部入口
scripts/chromium/build.sh a                # 增量构建（FAST=1）
FAST=0 scripts/chromium/build.sh a         # official
scripts/device/install.sh                  # 装机
scripts/device/ext-install.sh              # 装载参考扩展
scripts/device/verify.sh                   # 真机验收
scripts/chromium/flags.sh presets          # 运行时可切换 feature
bash tools/verify/check-repo.sh            # 仓库卫生（CI 同款）
```

## 文档

[docs/](docs/README.md) · [AGENTS.md](AGENTS.md) · [.agents/skills/](.agents/skills/) ·
[patches/README.md](patches/README.md) · [scripts/README.md](scripts/README.md) ·
[tools/README.md](tools/README.md) · [CONTRIBUTING.md](CONTRIBUTING.md) ·
[SECURITY.md](SECURITY.md) · [keys/README.md](keys/README.md)

## 许可

MIT，见 [LICENSE](LICENSE)；`patches/` 的 hunks 属 Chromium BSD-3-Clause，见 [NOTICE](NOTICE)。
