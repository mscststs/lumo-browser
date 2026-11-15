# 产品差异点：手机侧栏与用户脚本开关

这一篇定义 **v0.1 我们自己要写的两块能力**。上游已有的（扩展系统、扩展菜单、`chrome://extensions`、
DNR、SW 生命周期）不在此列。

## 1. 手机端 side panel

### 上游现状（已核实）

| 层 | 文件 | 说明 |
|---|---|---|
| 容器 UI | `chrome/browser/ui/side_panel/android/java/.../SidePanelContainerCoordinator.java` | Android 侧栏容器（bottom sheet 形态） |
| 开关 | `.../AndroidSidePanelEnabledFn.java` → `ChromeFeatureList.sEnableAndroidSidePanel` | 默认 **disabled** |
| 扩展内容 | `chrome/browser/ui/android/extensions/side_panel/internal/extension_side_panel_coordinator_android.cc` | 用 `ExtensionViewHostFactory::CreateSidePanelHost` 把 `sidepanel.html` 装进 `SidePanelNativeView` |
| 管理器 | `.../extension_side_panel_manager_bridge.cc` | 把 `extensions::ExtensionSidePanelManager` 接到 `SidePanelRegistry` |
| API | `chrome.sidePanel.getOptions/setOptions/open/...` | feature 层含 `desktop_android`，探针实测 `getOptions/setOptions` 通过 |

**结论**：`patches/0003-enable-android-side-panel.patch` 打开 feature 后，扩展侧栏的 C++/Java 链路是完整的；
我们只需要验证竖屏体验，并按需调形态。

### 我们要做的

1. **入口**
   - 扩展 action 点击：若扩展声明了 `side_panel.default_path` 且 `getOptions().enabled`，打开面板；
   - 扩展菜单（`ExtensionsMenuCoordinator`）里给每个有面板的扩展提供「打开侧栏」；
   - 记住最近一次打开的面板（per-tab）。
2. **形态**（竖屏优先）
   - 竖屏：`BottomSheet` 占屏 65%，可拖拽到 90%/关闭；键盘弹出时避让；
   - 横屏/平板：右侧 360dp 抽屉；
   - 面板内的 `window.innerWidth` 要真实反映容器宽度（扩展常按宽度做响应式）。
3. **手势与手势校验**
   - `chrome.sidePanel.open()` 在桌面要求用户手势；Android 上由我们判断：最近 1s 内有真实触摸 → 放行，否则记录并忽略。
4. **生命周期**
   - 切 tab 时按 scope 复用/重建（`SidePanelEntryScope` 上游已支持）；
   - 关闭面板不销毁扩展 host 的 `localStorage`（与桌面一致）。

### 验收

- `../lumo` 的 `sidepanel.html` 能在手机上打开、渲染、读取当前页；
- 关闭再打开，扩展侧栏的 UI 状态不丢；
- 面板宽度变化时 `innerWidth` 变化（用 probe 扩展的 sidepanel 页面打印）。

## 2. 用户脚本开关（`chrome.userScripts`）

### 现状

- `chrome.userScripts` 在 feature 层无平台限制，但**运行时要求用户显式开启**（Chrome 138+ 的
  "Allow User Scripts"）。Titanium 上没有暴露这个开关，探针实测 `chrome.userScripts 未暴露`。
- `../lumo-userscript-manager` 的 `minimum_chrome_version: 138`，核心功能完全依赖这个 API。

### 我们要做的

1. 设置页加「允许用户脚本（高级）」开关，落到与上游一致的 pref（`extensions.user_scripts_allowed`
   等，具体字段在 `extensions/browser/user_script_manager.cc` / `extension_prefs` 中确认）。
2. `chrome://extensions` 的扩展详情里加同样的开关（上游桌面版在扩展详情页）。
3. 首次安装带 `userScripts` 权限的扩展时，给一次明确的解释性提示（不打断流程）。
4. 开关关闭时，`chrome.userScripts` 相关调用返回明确错误（与桌面语义一致），而不是静默失败。

### 验收

- 开关关闭：probe 的 `userScripts.getScripts` 返回 "not allowed" 类错误；
- 开关打开：`register` 成功，并在测试页执行用户脚本（userscript manager 的 UI 显示运行日志）。

## 3. 交付顺序

1. 自构建 APK 跑通 `chrome://extensions` + 扩展加载（当前阶段）；
2. 打开 side panel feature，验证 `getOptions/setOptions` + 面板渲染；
3. 做动作入口与竖屏形态；
4. 做 userScripts 开关；
5. 再回头做工具栏 action 图标容器（`patches/0002`）与品牌化。
