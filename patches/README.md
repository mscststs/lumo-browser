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
| 0004 | branding | 应用名/包名/图标（`dev.lumo.browser`） | TODO |
| 0005 | lumo-compat | lumo 静默加载失败的根因修复（待复现） | TODO |
