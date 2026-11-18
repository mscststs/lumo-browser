# 变更日志（CHANGELOG）

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
本项目的内核版本号独立于 Chromium（当前基线 `160.0.8157.0`）。

## [Unreleased]

### Added

- `scripts/chromium/flags.sh`：设备侧命令行（feature flags / `--load-extension`）的唯一入口，
  提供 `compose|push|show|clear|presets`。
- `scripts/chromium/cache.sh`：内核身份 manifest（版本/clang/depot_tools/args.gn/patch sha/APK sha）
  与 `out/<dir>` 的 snapshot/restore。
- `scripts/chromium/keys.sh` 与 `keys/`：稳定 dev 签名密钥（公开、仅 debug），
  使 `pm install -r` 可覆盖升级而不丢 profile。
- `scripts/chromium/doctor.sh`：环境预检（源码/工具链/设备/签名/磁盘）。
- `scripts/chromium/patchwork.sh`：在“没有 commit 的 Chromium 工作树”里写补丁
  （snapshot → 编辑 → export → revert），替代不可用的 `git diff` / `git checkout --`。
- `.agents/skills/`：`chromium-android-build`、`chromium-patch-set`、`device-verification`。
- `docs/09-build-iteration.md`：构建成本的实测数据与三层迭代模型。
- `docs/adr/`：路线、补丁集、签名密钥三个决策记录。
- `tools/verify/check-repo.sh`：仓库卫生检查（脚本语法、补丁编号、文档链接、skills 结构）。
- 项目元文件：`LICENSE`、`NOTICE`、`CONTRIBUTING.md`、`SECURITY.md`、`Makefile`、
  `.editorconfig`、`.gitattributes`、PR 模板。

### Changed

- `build.sh`：out 目录按 flavor 隔离（FAST/official 不再共用，避免切换触发全量重建）；
  自动复用旧 `out/lumo-rel`；APK 内容未变化时不再重复归档 350 MB 副本；
  输出单次构建耗时；新增 `DRY_RUN=1`。
- `brand.sh` / `render-icons.py`：写文件前做内容比对，消除无意义的 mtime 抖动与资源重编。
- `ext-install.sh` / `run.sh` / `verify.sh`：统一走 `flags.sh`，不再各自手写命令行。
- `AGENTS.md`、`README.md`、`docs/README.md`、`patches/README.md` 全面重写/校正。
- CI：增加 `check-repo.sh`（脚本语法、补丁编号与格式、文档链接、skills 结构）。

### Fixed

- `tools/probe-dump.py`：MV3 worker 空闲退出后导不出探针结果（现在会用 `probe.html` 唤醒、
  再恢复原标签页并激活 http(s) 页面；`/json/new` 在本 build 返回 500，改用 `Page.navigate`）。
- 探针 `sw.js`：同一 SW 内重复运行 `userScripts.register` 会因“无变更”报错，改为先 unregister。
- `verify.sh`：GATE 不再依赖扩展页的 `Service Worker` 文本（a11y 树里没有），
  改为探针 payload（≥90%）+ 侧栏渲染 + 关闭回归；修掉 `grep -c` 空结果导致的算术错误。
- `patches/README.md` 的状态表与仓库实际不一致（0002/0003 早已落地）。
- `docs/00-strategy-and-start.md` §5 中“两个配置复用同一个 out 目录”的错误建议。
- `tools/__pycache__/*.pyc` 曾被误入库；已从索引移除并加入 `.gitignore`。

## [0.1.0] — 2026-11-16

首个可用基线：Chromium `160.0.8157.0`（official，arm64），包名 `dev.lumo.browser`。

### Added

- 8 个补丁：手机扩展工具栏（0002）、Android side panel 默认开启（0003）、
  Vulkan opt-out 尊重（0005）、GPU ES2 回退（0006）、`userScripts` 默认允许（0008）、
  popup 锚点回退（0009）、side panel 双形态（0010）、关闭 detach 修复（0011）。
- 品牌化流水线（`brand.sh` + `render-icons.py`，自适应图标三层 + 单色图标）。
- 30 项 MV3 探针扩展与真机验收脚本（`scripts/device/verify.sh`，`GATE=OK`）。
- Lumo AI 侧栏端到端验证（`scripts/verify/lumo-e2e.sh` + `tools/mock-openai.py`）。

### Verified on device

- MV3 探针 30/30；两个参考扩展 Service Worker 正常。
- 手机侧栏 = 可拖拽底部抽屉；宽屏 = 并排 + 可调宽；关闭不崩溃。
- 用户脚本注册与执行、popup/options 页面正常。
