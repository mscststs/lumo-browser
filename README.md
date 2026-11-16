# Lumo Browser

Android Chromium 内核 + 完整 MV3 扩展支持的移动浏览器。当前基线：**Chromium 160.0.8157.0**，
包名 `dev.lumo.browser`，应用名 **Lumo**。

一等公民扩展：

- [`../lumo`](../lumo)：AI 侧栏助手（sidePanel + scripting + tabs + webNavigation + DNR + cookies）
- [`../lumo-userscript-manager`](../lumo-userscript-manager)：MV3 用户脚本管理器（`chrome.userScripts` + GM API）

## 能力（真机实测，Redmi K20 Pro / Android 11 / arm64）

| 能力 | 状态 |
|---|---|
| Chromium 内核自构建（GCS tarball → CIPD → `gn`/`siso`） | ✅ 344MB APK |
| MV3 API 探针 | ✅ 30/30（[矩阵](docs/07-capability-matrix.md)） |
| 扩展管理（手机底部弹层 / `chrome://extensions` / popup） | ✅ |
| 手机 side panel = 可拖拽底部抽屉（peek/收起/展开） | ✅ |
| 平板 side panel = 并排 + 可拖拽宽度 | ✅ |
| Lumo 侧栏端到端（provider → 流式回复） | ✅ 见 `scripts/verify/lumo-e2e.sh` |
| 用户脚本注册与执行 / popup / 「允许运行用户脚本」开关 | ✅ |

## 快速开始

```bash
scripts/chromium/extract.sh        # 首次：GCS tarball → ~/chromium/src
scripts/chromium/cipd-deps.sh      # CIPD 依赖（NDK/SDK/JDK/androidx…）
scripts/chromium/toolchain.sh      # clang + LASTCHANGE + gclient_args
scripts/chromium/build.sh a        # 打补丁 + 品牌化 + gn + siso → artifacts/apk/

scripts/device/install.sh          # MIUI root 安装
scripts/device/verify.sh           # 30 项探针 + 扩展/侧栏/关闭回归，产出证据
scripts/verify/lumo-e2e.sh         # Lumo 侧栏 + mock OpenAI 端到端
```

构建/补丁细节见 [docs/01-architecture.md](docs/01-architecture.md)，补丁清单见 [patches/README.md](patches/README.md)。
