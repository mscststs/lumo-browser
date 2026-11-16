# 当前状态（2026-11-16 03:25 设备时间）

产品名：**Lumo**　包名：`dev.lumo.browser`　内核：Chromium 160.0.8157.0（official，arm64）

## 已实现并验证

| 能力 | 状态 | 证据 |
|---|---|---|
| 自构建 APK | ✅ 344MB | `artifacts/apk/lumo-a-*.apk` |
| 品牌化 | ✅ 应用名 Lumo / 包名 dev.lumo.browser / 图标 | `scripts/chromium/brand.sh` |
| GPU | ✅ ES2 回退运行（Adreno/ANGLE ES3 失败不再崩） | `patches/0006` |
| 扩展装载 | ✅ 上游 debug-app 握手（`/data/local/tmp` + `am set-debug-app`） | `scripts/device/ext-install.sh` |
| 三个扩展 + 探针 | ✅ Lumo 1.0.27 / Lumo MV3 Probe / Lumo 用户脚本管理器 | `chrome://extensions` |
| Service Worker | ✅ 均在运行 | 扩展页「检查视图」 |
| **手机 side panel = 可拖拽 Bottom Sheet** | ✅ peek(64dp) / 收起(45%) / 展开(75%)，页面始终可见可交互，面板不销毁 | `artifacts/verify/sheet2-*.png` |
| **平板/宽屏 side panel = 桌面式并排 + 可拖拽宽度** | ✅ 右侧 540px，页宽不受影响；拖动分隔条调整 | `artifacts/verify/tablet-panel.png` |
| 扩展 popup（工具栏气泡） | ✅ 用户脚本管理器的 popup 正常显示 | `artifacts/verify/us-popup2.png` |
| `chrome.userScripts` | ✅ 默认开放（可关），注册 + 真实执行成功 | `artifacts/verify/userscript-proof.png`（页面出现 `LUMO_USERSCRIPT_OK`） |
| `scripting.executeScript` | ✅ 隔离世界注入并返回 | 探针 `isolatedMarker: true` |
| MV3 探针 | ✅ **30/30**（`docs/07-capability-matrix.md`） | `PROBE_JSON` |
| Lumo AI 端到端 | ✅ 侧栏 → provider → 流式回复（本地 mock OpenAI） | `scripts/verify/lumo-e2e.sh`、`artifacts/verify/lumo-e2e-*` |
| 关闭侧栏不崩溃 | ✅ 连续 3 次开/关，进程存活（`patches/0011`） | `closecycle-*`、`summary.txt` 的 `close_panel=ok` |
| `chrome://extensions` 管理页 | ✅ 开发者模式 / 加载未打包 / 打包 / 更新 | 截图 |

## 关键补丁

| 补丁 | 内容 |
|---|---|

| 0002 | 手机扩展工具栏（容器 + ToolbarPhone 接收 coordinator + 去掉 tablet 强转） |
| 0003 | 默认启用 Android side panel（含手动改宽 feature） |
| 0005 | 尊重 `--disable-features=Vulkan` |
| 0006 | GPU 信息收集允许 ES2 回退 |
| 0008 | `userScripts` 改为默认允许（可关闭） |
| 0009 | popup 无内联按钮时回退到扩展容器作为锚点 |
| 0010 | **side panel 双形态**：窄屏 Bottom Sheet（拖拽/peek），宽屏并排可调宽；跨 600dp 断点自动关闭面板，重开即用新形态 |
| 0011 | 关闭侧栏时的容器 detach 修复（不再闪退）；隐藏侧栏 UI 时同步隐藏底部抽屉 |

## 验收命令与证据

```bash
scripts/device/verify.sh
# → artifacts/verify/<run>/screen-02-extensions.png（三个扩展 + Service Worker 状态）
# → probe.json（22/24）
# → screen-03-sidepanel.png（手机底部抽屉打开 Lumo 侧栏）
```

宽屏验证方法与证据：

```bash
adb shell wm size 2160x1600; adb shell wm density 240   # 模拟平板（1440dp 宽）
# 打开扩展菜单 → Lumo → 右侧并排面板 + 可拖拽分隔条
adb shell wm size reset; adb shell wm density reset
```
截图：`artifacts/verify/tablet-panel.png`

## 下一步

1. Lumo 侧栏接入真实模型后的端到端验证（需用户提供 provider key）。
2. 工具栏 action 图标的固定/排序体验打磨。
3. 设置页增加「允许用户脚本」开关（当前默认开）。
4. 发布流水线（签名、更新、Play/侧载策略）。
