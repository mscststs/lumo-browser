# 安全与加固（自构建分支）

本仓库对 Chromium 打了 8 个补丁。下面记录与安全相关的取舍，以及为什么某些"方便"的通道被移除。

## 1. 扩展装载 / 命令行 flag：不使用共享存储

早期补丁（已删除的 `0001`）从 `/sdcard/Android/data/<pkg>/files/chrome-command-line` 读取 Chrome 命令行。
问题：该目录在 **shared media** 上，任何拥有「所有文件访问权限」的应用都能写入，而 flag 里包括
`--load-extension`、`--remote-debugging-port`、`--ignore-certificate-errors` 等，等于任意代码执行入口。

现在改为上游本来就支持的 **debug-app 握手**：

```bash
adb shell "printf 'chrome --load-extension=/sdcard/.../ext/lumo\n' > /data/local/tmp/chrome-command-line"
adb shell su -c "am set-debug-app --persistent dev.lumo.browser"
```

该路径需要 ADB/root 才能写，普通应用无法影响；补丁集中不再有"从共享存储读 flag"的代码。

## 2. 扩展载荷目录（仅开发/验证）

`scripts/device/*` 把扩展推到 `/sdcard/Android/data/<pkg>/files/ext/`，这是**开发期机制**：
Chrome 自己安装扩展时会复制进 profile，不会执行共享存储里的脚本。正式发布不要依赖此路径。

## 3. 用户脚本默认允许（`0008`）

`chrome.userScripts` 上游是显式 opt-in，但开关只有在 API 已可用时才显示（鸡生蛋问题），导致
userscript-manager 新装即不可用。补丁把默认值改为允许，并在扩展详情页保留「允许运行用户脚本」开关，
用户可随时关闭。安全边界仍是 MV3 权限模型：只有声明 `userScripts` 权限的扩展能注册脚本。

## 4. Side panel 宿主与关闭路径（`0010` / `0011`）

- 窄屏把面板挂在 Activity 内容视图（bottom sheet overlay），`0011` 让 `SideUiCoordinator` 从"当前父容器"
  detach，避免 `addView` 崩溃；关闭时不销毁扩展 WebContents。
- 隐藏侧栏 UI（如进入标签页切换器）时同步隐藏底部抽屉，避免浮层遮挡。
- 跨 600dp 断点（旋转/桌面模式改尺寸）时自动关闭面板，重新打开即按新形态呈现，避免两套布局系统竞争。

## 5. 审查与残留风险

`artifacts/agents/patch-review.md` 是一轮独立审查的记录。已处理：H1（本文件 §1）、H2（隐藏联动）、
M2（宽屏把手占位）、M3（resize handle 清理）、M4（断点切换）、L1（日志 flag 关闭）、L4（APK 选取）、
L5（工具链缺失即失败）、L7（品牌化断言）。

仍未处理（可接受/待办）：
- M1：手机工具栏未注册 width consumer（当前真机表现为只有扩展菜单按钮、无内联动作，popup 走容器锚点回退；
  若以后要内联固定动作，需要按 M1 的建议补 measure 逻辑）。
- M5：popup 以扩展容器为锚点时的位置微调。
- `tools/verify/manifest.json` 的加权评分尚未接入 `verify.sh`（当前用 30 项探针 + 扩展/SW/关闭回归硬门槛）。
