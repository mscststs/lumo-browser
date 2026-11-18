# 补丁集（patches/）

对**未修改的 Chromium 源码**按序应用的最小侵入补丁。每条都能单独审计、单独删除、单独回滚。

## 规则

- 文件名 `NNNN-area-short-title.patch`，按序应用（`scripts/chromium/apply-patches.sh`），编号只增不减。
- 一个补丁只做一件事；注释写清 **上游为什么没有**、**我们在哪个调用点接线**、**怎么关掉/回滚**。
- 生成方式：`scripts/chromium/patchwork.sh`（源码树没有 commit，`git diff` 不可用）：
  ```bash
  scripts/chromium/patchwork.sh start patches/0012-area-what.patch <path...>
  # 编辑 ~/chromium/src 下的文件
  scripts/chromium/patchwork.sh export          # 写出补丁
  scripts/chromium/patchwork.sh revert          # 恢复 pristine（补丁保留）
  ```
- 改了补丁内容必须删掉对应的 `$CHROMIUM_SRC/.lumo-patches/<name>.stamp`，否则会被跳过。
- 新补丁必须在本文件登记（CI 检查覆盖与编号）。
- 品牌化不在 patch 里：`scripts/chromium/brand.sh` + `chrome_public_manifest_package`（二进制图标不适合文本补丁）。

## 清单（8 个）

| # | 名称 | 类型 | 目的 | 门控 / 回滚 |
|---|---|---|---|---|
| 0002 | phone-extensions-toolbar | 结构性 | `toolbar_phone.xml` 加 `extensions_toolbar_container_stub` + `ToolbarPhone` 接线（上游只有 tablet 有），去掉 tablet 强转 | 编译期；无独立开关（扩展 UI 整体可用 `--disable-features` 关） |
| 0003 | enable-android-side-panel | 默认值 | `kEnableAndroidSidePanel` / `...ManualResizing` 默认 ENABLED | ✅ `LUMO_DISABLE_FEATURES=EnableAndroidSidePanel scripts/chromium/flags.sh push` |
| 0005 | gpu-respect-vulkan-optout | 逻辑 | 尊重 `--disable-features=Vulkan`，避免 WebGPU interop 强拉 Vulkan | ✅ 命令行 |
| 0006 | gpu-es2-fallback | 逻辑 | GPU 信息收集允许 ES2 回退，老 Adreno 驱动不再整浏览器崩溃 | 自动（无开关） |
| 0008 | userscripts-optout | 默认值 | `chrome.userScripts` 默认允许（扩展仍需声明权限，用户可在详情页关） | 扩展详情页开关 |
| 0009 | popup-container-anchor | 结构性 | 扩展 popup 无内联按钮时回退到扩展容器锚点（手机上不丢 popup） | 编译期 |
| 0010 | sidepanel-bottom-sheet | 结构性 | 窄屏底部抽屉（拖拽/peek）+ 宽屏并排可调宽，跨断点安全关闭 | 断点 600dp（随窗口宽度） |
| 0011 | sidepanel-close-detach | 逻辑 | 关闭侧栏时容器可能挂在 Activity 内容视图上 → 改为“从当前父容器移除”，修复闪退 | 编译期 |

编号 `0001` / `0004` / `0007` 从未落地（被合并或放弃），**不要复用**。

## 运行时开关优先

进补丁前先过三问（`docs/09-build-iteration.md` §3）：能做扩展吗 → 上游已有代码只是默认值不对吗 →
上游真的缺代码吗？只有第三问成立才新增 patch。

- 默认值翻转类（如 0003）**必须**同时能用命令行覆盖，方便不重编译做回归；但**不要**因此删除补丁：
  命令行只在 `am set-debug-app` 握手/可调试时生效，编译默认值才是产品默认。
- 结构性补丁（0002/0009/0010/0011）应在注释里写清对应的接线点与门控点，便于以后包进 feature flag。
- 补丁改 Java 按 ~2 min 估，改 C++ 按 ~25 s 估（实测见 `docs/09`）。

## 新增 / 修改补丁

1. 基线绿：`scripts/chromium/apply-patches.sh && scripts/chromium/build.sh a`。
2. `patchwork.sh start` → 改源码 → `patchwork.sh export`。
3. `(cd ~/chromium/src && git apply --check <patch>)`；`patchwork.sh revert`；`apply-patches.sh` 重放。
4. 构建 + 真机证据（`scripts/device/verify.sh` → `GATE=OK`）。
5. 更新本文件表格；若涉及成本/流程，同步 `docs/09`；若删除补丁，同步 `docs/06`、`AGENTS.md`。

## 审计清单

- [ ] `git apply --check` 在干净树通过
- [ ] 只包含必要 hunks，无空白/重排噪音
- [ ] 注释：上游缺口 + 接线点 + 回滚方式
- [ ] 默认值只在一处定义
- [ ] 本文件已登记，编号连续
- [ ] 真机回归或明确说明只需单点验证

详细规范见 `.agents/skills/chromium-patch-set/`（`patch-anatomy.md`、`rebase-playbook.md`）。
