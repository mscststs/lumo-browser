# 补丁集

规则：

- 文件名：`NNNN-area-short-title.patch`，按序应用（`scripts/chromium/apply-patches.sh`）。
- 一个补丁只做一件事；标题行写 `[area] 为什么`；正文引用上游文件路径或 crbug。
- 生成方式：在 `~/chromium/src` 里改完 → `git diff > patches/NNNN-....patch`（tarball 无 git 时先 `git init && git add -A && git commit`）。
- 验收：`scripts/chromium/apply-patches.sh` 在干净源码上 `git apply --check` 全绿。

计划中的补丁（按优先级）：

| # | 名称 | 目的 | 状态 |
|---|---|---|---|
| 0001 | command-line-external-files | 允许从 app 外部目录读 `chrome-command-line`，CI 免 `set-debug-app`、免 root | TODO |
| 0002 | phone-extensions-toolbar | `toolbar_phone.xml` 加 `extensions_toolbar_container_stub` + `ToolbarPhone` 接线（参考 tablet） | TODO |
| 0003 | extensions-page-mobile | `chrome://extensions` 移动端视口/触摸/卡片宽度 | TODO |
| 0005 | gpu-respect-vulkan-optout | 尊重 `--disable-features=Vulkan`，避免 WebGPU interop 强拉 Vulkan | 已有 |
| 0006 | gpu-es2-fallback | GPU 信息收集允许 ES2 回退（老 Adreno 驱动不致整浏览器崩溃） | 已有 |
| 0008 | userscripts-optout | `chrome.userScripts` 默认允许（可关），否则用户脚本管理器不可用 | 已有 |
| 0009 | popup-container-anchor | popup 无内联按钮时用扩展容器做锚点（手机不丢 popup） | 已有 |
| 0010 | sidepanel-bottom-sheet | 窄屏 bottom sheet（拖拽/peek），宽屏并排可调宽 | 已有 |

品牌化不在 patch 里，由 `scripts/chromium/brand.sh` + `chrome_public_manifest_package` 完成（二进制图标不适合文本补丁）。
