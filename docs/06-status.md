# 当前状态（2026-11-16 · 最终验收）

产品名 **Lumo**　包名 `dev.lumo.browser`　内核 Chromium **160.0.8157.0**（official，arm64）

## 验收（全新安装后重跑，非增量状态）

| 项 | 结果 | 证据 |
|---|---|---|
| APK 安装启动（卸载后重装） | ✅ | `artifacts/apk/lumo-a-20261116-1254.apk` |
| MV3 探针 | ✅ **30/30** | `artifacts/verify/20261116-130705/probe.json` |
| 扩展加载 + Service Worker | ✅ 3/3 | `extensions-strings.txt`（三个 `Service Worker`） |
| Lumo 侧栏 AI 端到端 | ✅ provider → 流式回复（mock OpenAI） | `artifacts/verify/lumo-e2e-20261116-130954/screen-lumo-e2e.png` |
| 用户脚本管理器 popup | ✅ 显示当前站点脚本状态 | `artifacts/verify/final-us-popup.png` |
| 用户脚本注册与执行 | ✅ 页面渲染 `LUMO_USERSCRIPT_OK` | `userscript-proof.png` |
| 手机侧栏 = 可拖拽底部抽屉 | ✅ peek/收起/展开；页面可见可交互 | `sheet2-*.png`、`rot6-d-narrow-open.png` |
| 平板/宽屏 = 并排 + 可调宽 | ✅ 618px 侧栏，页面不遮挡 | `rot5-b-wide.png`、`rot6-c-wide-open.png` |
| 关闭侧栏不崩溃 | ✅ 连续开关 + 自动回归 | `close-panel.txt` = `close_panel=ok` |
| 验收硬门槛 | ✅ `GATE=OK` | `summary.txt` |

## 构建流水线

```
scripts/chromium/extract.sh      GCS tarball → ~/chromium/src（无 git 依赖）
scripts/chromium/cipd-deps.sh    NDK/SDK/JDK/androidx/build-tools（表由 DEPS 生成）
scripts/chromium/fetch-dep.sh    googlesource +archive 补齐缺失的 git 依赖
scripts/chromium/fetch-tree.sh   仓库子目录（+archive/<tag>/<path>.tar.gz）
scripts/chromium/toolchain.sh    clang + LASTCHANGE + gclient_args.gni
scripts/chromium/build.sh a      补丁 → 品牌化 → gn → siso → artifacts/apk/
```

## 补丁（8 个）

| 补丁 | 作用 |
|---|---|
| 0002 | 手机扩展工具栏（容器 + ToolbarPhone 接收 coordinator + 去掉 tablet 强转） |
| 0003 | 启用 Android side panel（+手动改宽），verbose 日志保持关闭 |
| 0005 | 尊重 `--disable-features=Vulkan` |
| 0006 | GPU 信息收集允许 ES2 回退（老 Adreno 驱动不再整浏览器崩溃） |
| 0008 | `chrome.userScripts` 默认允许（详情页可关） |
| 0009 | popup 无内联按钮时回退到扩展容器锚点 |
| 0010 | side panel 双形态（底部抽屉 / 并排可调宽），断点切换安全关闭 |
| 0011 | 关闭/隐藏侧栏的容器 detach 修复（不再闪退） |

## 验证命令

```bash
scripts/device/verify.sh          # 30 项探针 + 扩展/SW + 侧栏 + 关闭回归 + GATE
scripts/verify/lumo-e2e.sh        # Lumo 侧栏 + mock OpenAI 流式回复
tools/cdp.py list|eval|type       # CDP（--remote-debugging-port=9222）
bash tools/verify/check-static.sh # 探针扩展静态检查 + SW 冒烟
```

## 已知限制

- 跨 600dp 断点（旋转/桌面模式改尺寸）会关闭侧栏，重新打开按新形态呈现。
- 手机工具栏暂未内联固定动作图标（动作走扩展菜单；popup 已正常）。
- Lumo 的 AI 需要用户自己的 provider key（端到端用本地 mock 证明链路）。
- `nativeMessaging` / `desktopCapture` / `devtools.*` 面板为平台限制，未纳入承诺。
