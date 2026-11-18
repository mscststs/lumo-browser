# 补丁解剖（结构、注释、门控）

## 1. 文件格式

`patches/` 里的是**工作树 diff**（`git apply` 直接可用），不是 `git format-patch` 邮件格式：

```
--- a/chrome/browser/ui/side_panel/android/side_panel_native_view_android.cc
+++ b/chrome/browser/ui/side_panel/android/side_panel_native_view_android.cc
@@ -12,6 +12,7 @@
   ...
```

规则：

- 路径以 `a/`、`b/` 开头，相对 Chromium 源码根（`~/chromium/src`）。
- 新建文件用 `--- /dev/null`；删除用 `+++ /dev/null`。
- 不做空白/行尾/重排等无关修改；hunk 上下文默认 3 行即可。
- 一个文件一个补丁主题；跨文件时确认每个文件都必要。

生成方式（源码树**没有 commit**，`git diff` 不可用）：

```bash
scripts/chromium/patchwork.sh start patches/0012-what.patch <path...>
# 编辑 ~/chromium/src 下的文件
scripts/chromium/patchwork.sh export
scripts/chromium/patchwork.sh revert      # 恢复 pristine（补丁已保存）
scripts/chromium/patchwork.sh finish
```

## 2. 注释风格

补丁本身就是文档。每个非平凡 hunk 上方写清三件事：

1. **上游为什么没有**（缺挂载点？默认值？平台假设？）
2. **我们在哪个调用点接线**（类名/方法名，便于升级时定位）
3. **怎么关掉/回滚**（feature 名、flag 名、开关项）

示例（来自 `0002`）：

```xml
+        <!-- Lumo: host the extension toolbar (actions + extensions menu) on
+             phones. Upstream only ships this ViewStub in toolbar_tablet.xml,
+             which left `ExtensionsMenuCoordinator` without an anchor and made
+             the overflow menu's "open extensions menu" entry crash. -->
```

示例（来自 `0008`，说明策略变更与边界）：

```cpp
+  // Lumo: user scripts are opt-out rather than opt-in. Chrome ships the
+  // `userScripts` API disabled until the user flips a per-extension toggle that
+  // only appears after the API is already available, which leaves
+  // userscript-manager style extensions permanently broken on a fresh install.
+  // Extensions still have to declare the `userScripts` permission, and users
+  // can turn the toggle off again.
```

## 3. 门控（推荐写法）

结构性/行为类补丁应尽量能被运行时关闭，便于灰度与回滚。

**声明 feature**（C++，Android 特有 behaviour 放这里）：

```cpp
// chrome/browser/flags/android/chrome_feature_list.cc
BASE_FEATURE(kLumoSidePanelBottomSheet, base::FEATURE_ENABLED_BY_DEFAULT);
// 并加入 kFeaturesExposedToJava（若 Java 侧要读）
```

**C++ 读取**：

```cpp
if (base::FeatureList::IsEnabled(kLumoSidePanelBottomSheet)) { ... }
```

**Java 读取**：

```java
if (ChromeFeatureList.isEnabled(ChromeFeatureList.LUMO_SIDE_PANEL_BOTTOM_SHEET)) { ... }
```

**验证可关**：

```bash
LUMO_DISABLE_FEATURES=LumoSidePanelBottomSheet scripts/chromium/flags.sh push
scripts/device/launch.sh && scripts/device/shot.sh   # 形态应回到上游行为
```

注意：`base::Feature` 的**编译默认值**是产品行为；命令行覆盖只在 `am set-debug-app`
握手/可调试运行时生效。两者都要写进补丁注释。

## 4. 何时不该用补丁

| 需求 | 更合适的做法 |
|---|---|
| 只是想让某个上游 feature 默认开 | 先加编译默认值，同时保留 `--disable-features` 回归能力；不要为此重写 UI 代码 |
| 产品界面/交互（侧栏内容、设置页、商店） | 扩展（`../lumo` 等）或独立 Compose 界面 |
| 日志/调试开关 | 运行时 flag，不打补丁 |
| 上游已在更新的功能 | 升级 Chromium，而不是打补丁维护两份实现 |

## 5. 补丁审计清单

- [ ] `git apply --check` 在干净树通过（`apply-patches.sh` 会验证）
- [ ] 只改必要文件；无格式噪音
- [ ] 注释写清 upstream 缺口 + 接线点 + 回滚方式
- [ ] 默认值只有一处定义（不要同时散落在 Java/C++/xml）
- [ ] `patches/README.md` 状态表已更新
- [ ] 真机回归（`GATE=OK`）或明确说明只需单点验证
