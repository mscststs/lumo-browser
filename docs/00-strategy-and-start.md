# Lumo Browser 起点分析（MV3 移动端浏览器）

日期：2026-11-15　基线：Chromium `main` = 160.0.8164　依据：`docs/mv3-research-report.md`（内部调研报告）+ 本轮源码复核

本文不是报告的复述，而是**复核 + 更正 + 落地起点**。所有「确认」项都给了可复现的源码位置；所有「估算」都标注了。

---

## 0. 结论先行

| 决策 | 内容 |
|---|---|
| 路线 | **C：Chromium + `is_desktop_android`**。不做 WebView 运行时（路线 A），不做 GeckoView（路线 B），不做云浏览器（路线 D）。 |
| 起点 | **先构建 vanilla `is_desktop_android` APK，量出真实缺口**，再决定 patch 集。不要一上来 fork Titanium。 |
| 与报告的最大差异 | 报告写于「上游只有 API、没有 Android 扩展 UI」的判断上（结论 5.4：「有 API 但缺 UI/空实现」）。**当前 trunk 已推翻这一判断**：Android 扩展 UI 栈（工具栏协调器、扩展菜单、站点权限页、安装对话框、side panel bridge + contents、extension window controller、developer-private bridge）已随 `enable_extensions_core` 全部编译，且由 **tablet 工具栏**承载。 |
| 因此工作重心 | 不是「实现 MV3」，而是 ①**手机形态的承载点**（phone 工具栏没有扩展容器，这是上游唯一硬缺口）②**产品化**（安装流程、权限 UX、商店/侧载策略）③**稳定性 patch 与 rebase 流水线**。 |
| 外壳语言 | **Kotlin + Compose**，不是 Flutter。理由见 §4。 |
| 首周产出 | 一份「实测缺口表」（不是估算百分比）+ 可跑的自构建 APK + 两个自研 MV3 扩展的加载结果。 |

---

## 1. 报告核对结果

### 1.1 已逐条确认（可复现）

| 报告结论 | 核对方式 | 结果 |
|---|---|---|
| `enable_desktop_android_extensions = is_desktop_android`，`enable_extensions_core = enable_extensions \|\| enable_desktop_android_extensions` | `extensions/buildflags/buildflags.gni:48-74` | ✅ 原文一致，且两者都在 `declare_args()` 内（**可从 args.gn 覆盖**，见 §5） |
| feature 条目覆盖 ≈89%（341 中 305） | 用报告附录 D 脚本对 5 个 feature 文件重算 | ✅ 341/305，完全复现：`chrome/_api_features` 137→128、`extensions/_api_features` 112→91、`_manifest_features` 81→76 + 11→10 |
| `sidePanel` permission feature 含 `desktop_android` | `chrome/common/extensions/api/_permission_features.json` | ✅ `platforms: ["chromeos","desktop_android","linux","mac","win"]` |
| `nativeMessaging` 有独立 `desktop_android` 条目 + feature flag | `extensions/common/api/_permission_features.json:478-489` + `extensions/common/extension_features.cc:98` | ✅ `platforms:["desktop_android"]`, `feature_flag:"ApiDesktopAndroidNativeMessaging"`，且 `kApiDesktopAndroidNativeMessaging` **默认 ENABLED**，`...BypassExtensionAllowlist` 默认 disabled |
| `scripting` / `offscreen` / `userScripts` / `declarativeNetRequest` / `webRequest` 无平台限制 | 同上脚本 | ✅ 均为 OPEN |
| WebView 新增真隔离世界 API | `androidx/webkit/.../WebViewFeature.java:985`(`JS_INJECTION_IN_FRAME_AND_WORLD`)、`WebViewCompat.java:900`(`getExecutionWorld`)、`:957`(`addJavaScriptOnEvent`)、`:1007`(`addWebMessageListener(world)`) | ✅ API 存在（但这不影响路线选择） |
| Titanium `patch.sh` = 185 行，`args.gn` 含 `is_desktop_android = true`，GPL-2.0，单人维护 | raw 抓取 + GitHub API | ✅ 185 行；GPL-2.0；3224 star / 178 fork / 180 open issue / 最后 push 2026-11-12 |

### 1.2 需要更正的三点

1. **「sidePanel 有 API 没 UI，要自己写侧栏」已过时。**
   上游现有：
   - `chrome/browser/ui/android/extensions/side_panel/{java,factory_java,internal,stub}`：`ExtensionSidePanelManagerBridge` + `ExtensionSidePanelContentsAndroid` + `ExtensionSidePanelCoordinatorAndroid`
   - `chrome/browser/ui/side_panel/android/side_panel_native_view_android.cc`、`android_side_panel_enabled_fn.cc`
   - 结论：`chrome.sidePanel.*` 的 wiring 上游已有，我们做的是**竖屏形态的呈现与手势**，不是从零实现 API。

2. **「Titanium 证明主要工作是解锁」只对了一半。**
   我们今天看到的上游（160.x）已经把解锁做掉大半：`ExtensionUi`、`ExtensionUiBackendImpl`、`ExtensionsMenu*`（含 `SitePermissionsPage*` 站点权限页）、`ExtensionInstallDialogBridge`、`ExtensionDeveloperPrivateBridge`、`windowing/internal`（`ExtensionWindowControllerBridge`）、`toolbar/extensions/ExtensionsToolbarCoordinator*`（含 drag、popup、action list、request-access button、hover card）。
   因此 Titanium 那 185 行里，相当部分是在**给它自己的分支补上游当年没有的东西**；照抄只会把技术债搬过来（还带 GPL）。

3. **手机形态是真正的硬缺口（已被源码钉死）。**
   - `chrome/browser/ui/android/toolbar/java/res/layout/toolbar_tablet.xml:123` 有 `extensions_toolbar_container_stub`
   - `.../top/ToolbarTablet.java` 有 `ExtensionsToolbarCoordinator` 的完整接线（`getPoppedOutActionWidthConsumer`、`EXTENSIONS_MENU_BUTTON`、`EXTENSION_ACTION_LIST`…）
   - `toolbar_phone.xml` 与 `ToolbarPhone.java` **零扩展引用**
   - Titanium 用 `canvas.translate` 手绘绕过，就是撞在这个缺口上。
   → 我们要**正经补上 phone 承载点**（XML 容器 + Coordinator 接线），这比 sed 修改画布代价低、可上游化。

### 1.3 报告仍未验证、需要我们自己测量的

- `internal` vs `stub` 的切换条件我确认为**只看 `enable_extensions_core`**（`chrome/android/BUILD.gn:1043-1054`），不含 `is_desktop_android` 判断 → 由此产生 §5 的「配置 B」实验。
- `chrome://extensions` 在手机视口下的可用性（Titanium 用 CSS 补丁：卡片 400px→96%、字段 680px→96%、`touch-action: none`→`pan-y`）。
- 站外/商店安装：`download_crx_util.cc` 的 allowlist、CWS 的 UA 判断（Titanium 对 `[*.]chromewebstore.google.com` 强制桌面 UA）。
- Service worker 保活、Doze 下扩展后台行为在 Android 的真实表现（无现成资料，只能实测）。

---

## 2. 我们自己的上下文（比报告更重要的输入）

仓库里的既有资产改变了「兼容性」的定义：

| 仓库 | 角色 | 对本项目的意义 |
|---|---|---|
| `lumo` | MV3 扩展（WXT + React 19），已上 CWS/Edge，AI 侧栏 agent，用 sidePanel / scripting / tabs / webNavigation / DNR / cookies | **一等验收用例**：我们自己的旗舰扩展必须零修改跑起来 |
| `lumo-userscript-manager` | MV3 扩展，`chrome.userScripts` + MAIN/USER_SCRIPT 双世界 + GM API + `GM_xmlhttpRequest` + 通知/下载/剪贴板 | **第二条验收用例**，专打 userScripts / webRequest / cookies / 世界隔离 |
| `lumo-mobile` | Kotlin + Compose 原生 App，内嵌 WebView 浏览器 + agent 运行时（`web/BrowserController.kt`、`assets/page/*.js`） | UI/产品已有参考实现；**证明外壳应当用 Kotlin/Compose，不是 Flutter** |
| `lumo-website` | 官网 | 未来的扩展分发/商店入口 |

推论：

1. 报告把「Flutter 只做外壳」当作前提。我们不需要 Flutter —— 已有 Compose 代码库与设计 token，且 Chromium Android 的 UI 层就是 Java/Views，两栈都在 JVM 上，用 Compose 做**新增界面**（设置、扩展管理增强、商店、权限弹窗）成本最低。
2. 「装什么跑什么」这个承诺对我们其实是**可验证的**：两个自家扩展覆盖了 sidePanel、userScripts、DNR、scripting、storage、cookies、notifications、downloads、clipboard、world 隔离 —— 覆盖了主流内容型扩展 80% 的能力面。
3. 真正的差异化不在「能装扩展」，而在 **AI 侧栏 + agent 驱动页面** 与扩展运行时共存（`chrome.debugger`/CDP、`scripting`、`sidePanel` 三者同时要）。这会决定几个 patch 优先级（见 §6）。

---

## 3. 目标能力分层（我们承诺什么）

| 层 | 承诺 | 判据 |
|---|---|---|
| L0 | 能安装、能运行、能卸载 MV3 扩展（含 CRX/zip/文件夹） | 自有 2 个扩展 + Top 20 CWS 扩展 |
| L1 | `action` / `popup` / `sidePanel` / `contextMenus` / `notifications` / `tabs` / `storage` / `scripting` / `cookies` / `webNavigation` / `alarms` / `i18n` 语义可用 | 扩展零修改 |
| L2 | `declarativeNetRequest`（含 `modifyHeaders`）、`userScripts`、`offscreen`、`webRequest`（观察） | 广告拦截类 + userscript 类扩展 |
| L3 | 表单/身份类：`identity.launchWebAuthFlow`、`nativeMessaging`、`debugger` | 按需 |
| 不支持（明确写进文档） | `tabCapture`/`desktopCapture` 采集源语义、`chrome.windows` 多窗口完整语义、`devtools.*` 面板、`enterprise.*`、平台应用（`app.*`） |

注意：`tabCapture` / `desktopCapture` 的 **feature 是 OPEN 的**（已核），但 Android 上没有采集源。这类"API 在、实现空"的条目要按 **L3 灰名单** 处理，别在发布说明里写"支持"。

---

## 4. 架构

```
┌───────────────────────────────────────────────────────────────┐
│ 我们维护的层（小）                                              │
│  · 手机形态扩展承载点：toolbar_phone 容器 + Coordinator 接线     │
│  · 竖屏 side panel 呈现（bottom sheet / 抽屉）+ 手势            │
│  · 安装/侧载/更新流程、扩展管理增强、商店对接                    │
│  · 权限与站点访问 UX（上游已有 SitePermissionsPage，需手机化）   │
│  · Compose 新增界面（设置、商店、诊断）、遥测/崩溃               │
│  · patch 集 + rebase CI                                        │
├───────────────────────────────────────────────────────────────┤
│ 上游（不要重写）                                                │
│  · 浏览器内核、扩展系统、SW 生命周期、DNR 引擎                   │
│  · ui/android/extensions（ExtensionUi：菜单/工具栏/安装/权限）   │
│  · side_panel/internal、windowing/internal                      │
│  · chrome://extensions WebUI（视口需补丁）                      │
└───────────────────────────────────────────────────────────────┘
```

原则：**上游有的不重写、上游缺的做最小侵入补丁、产品体验放在 Compose 层**。补丁全部以 `git apply` 形式的 patch 文件维护（学 Brave 的 `chromium_src` overlay 思路，但我们的量级不需要 overlay 目录）。

---

## 5. 两个构建配置：先做实验，再选形态

因为 `enable_desktop_android_extensions` 在 `declare_args()` 里，**可以从 args.gn 覆盖**，所以有两条都值得跑一次的路：

| 配置 | args.gn 关键项 | 预期 | 风险 |
|---|---|---|---|
| **A. 上游支持形态** | `is_desktop_android = true` | 扩展栈完整（含 windowing、tablet 工具栏），最接近「上游 CI 会测」的路径 | 可能带桌面化 UI（窗口/多实例），手机形态需收敛 |
| **B. 手机形态 + 扩展** | `target_os="android"` + `enable_desktop_android_extensions = true` | 保留手机原生 UI（我们熟悉的 Chrome Android 形态），同时编译扩展核心与 internal UI | 部分代码路径依赖 `is_desktop_android` 的其他假设（如 windowing、devtools），可能编译失败或运行期崩溃 |

**实验顺序**：先 A（成功率最高，能立刻拿到可用基线），再 B（若 A 的桌面化 UI 不可接受，B 是我们真正的目标形态）。两次构建复用同一个 `out/` 目录可省一半磁盘。

判定标准（二选一即可）：
- A 能在手机上以可接受形态跑起 `lumo` 扩展的 sidePanel；
- 或 B 能编译通过且扩展菜单可用。

---

## 6. 缺口清单 → patch 集（按优先级）

| # | 缺口 | 上游现状（已核） | 我们的做法 | 优先级 |
|---|---|---|---|---|
| 1 | 手机工具栏无扩展承载点 | tablet 有 stub 容器 + `ExtensionsToolbarCoordinator` 接线；phone 无 | **已实现**（`patches/0002`）：`toolbar_phone.xml` 加容器 + `ToolbarPhone` 接收 coordinator + 去掉 tablet 强转。仍缺 width consumer（见 docs/08 残留风险 M1） | ✅ |
| 2 | 竖屏 side panel 呈现 | bridge/contents/coordinator 已有 | **已实现**（`patches/0010`）：底部抽屉 peek/收起/展开 + 拖拽；宽屏并排可调宽 | ✅ |
| 3 | `chrome://extensions` 移动视口 | 桌面 WebUI | 视口 + 卡片/字段宽度 + `touch-action` 的 CSS/布局补丁（Titanium 的做法可作参考，代码自写） | P1 |
| 4 | 安装入口 | `ExtensionInstallDialogBridge`、`ExtensionInstallPrompt` 已有；无 CWS 手机入口 | 侧载（SAF 选 zip/文件夹）+ 商店 URL 安装；评估 CWS 的 UA 依赖 | P1 |
| 5 | MV2 策略 | `g_allow_mv2_for_testing` 型测试开关 | **产品决策**：只有明确需要才开，且要写进隐私/安全说明；默认不开 | P1（决策） |
| 6 | 隐身 profile 下扩展 | `process_manager.cc` 有 `!IsOffTheRecord()` 判断 | 默认保持上游行为（扩展不跑在 OTR）；若开，需单独的隐私说明 | P2 |
| 7 | 稳定性 | 上游有历史 crbug（`tabs_api` 空指针、OTR profile UAF、返回键、SAF 加载未打包扩展） | 先在 A 配置下复现；能上游就上游，不能就带 crbug 号的最小补丁 | P1 |
| 8 | 站点访问/权限 UX | `ExtensionSiteSettingsAndroid`、`SitePermissionsPage*` 已有 | 手机化排布；「按站点授予」是手机端关键差异化 | P1 |
| 9 | `debugger` / CDP | feature OPEN，依赖 DevTools frontend | 我们的 agent 需要 CDP 时再开（注意 Play 政策） | P2 |
| 10 | rebase 流水线 | — | patch 文件化 + CI 每晚对 `main` 试 rebase，失败即告警 | P0（工程） |

---

## 7. 里程碑

| 阶段 | 目标 | 产出 | 估时（1–2 人） |
|---|---|---|---|
| **P0 基线** | 自构建 A 配置 APK 跑起来；安装 `lumo` 与 `lumo-userscript-manager`；逐项记录「work / broken / missing」 | 环境脚本、args.gn、实测缺口表、崩溃日志 | 1–2 周 |
| **P1 手机形态** | 手机工具栏承载 + 竖屏 side panel + 安装/管理入口 | 可日常使用的内部版本 | 3–4 周 |
| **P2 兼容性** | Top 20 CWS 扩展回归；DNR/modifyHeaders、userScripts、offscreen 验证 | 兼容性矩阵 + 逐条 patch 或灰名单 | 3–4 周 |
| **P3 发布** | rebase CI、签名与更新、Play 合规（第三方代码执行、权限说明） | 内测渠道版本 | 2–3 周 |
| 持续 | 每 4 周跟一个 milestone（160→161→…），patch 失配修复 | — | 每次 1–3 天 |

对比报告估算（C 路线 12–24 人月）：在「只做手机承载 + 产品化 + 上游已有 UI」的前提下，**P0–P1 约 1 人 1.5–2 个月**是现实的；报告的数字对应的是从零做 UI 的情形。

---

## 8. 环境现状与准备（本机实测）

| 项 | 实测 | 结论 |
|---|---|---|
| CPU / 内存 | 12 核 / 60GB | 够用（增量构建分钟级，全量 2–4h） |
| 磁盘 | 288GB 可用 | 够，但要预算：`src`≈60–70GB + `out/`≈40–60GB；**不做多 out 目录** |
| JDK | 系统 JDK 25 | 无关紧要：Chromium 用 CIPD 拉 `third_party/jdk`（`DEPS: jdk-25.0.5+8`） |
| Android SDK | `~/android-sdk`：build-tools 36/37，platforms 30/36/37 | 可用；NDK 由 CIPD 提供，无需本地 |
| 模拟器 | 有多个 AVD（x86_64 + arm64），**无 `/dev/kvm`** | 软件模拟太慢 → 功能验证用**真机**，模拟器只做冒烟 |
| depot_tools / gn / ninja | **未安装** | P0 第一步 |

P0 环境命令（草案）：

```bash
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git ~/depot_tools
export PATH="$HOME/depot_tools:$PATH"
mkdir -p ~/c && cd ~/c && fetch --nohooks --no-history android   # --no-history 省 ~20GB
./build/install-build-deps.sh --android
gclient runhooks
gn gen out/Default --args='target_os="android" is_desktop_android=true is_debug=false \
  target_cpu="arm64" is_component_build=false symbol_level=1 \
  enable_arcore=false enable_vr=false proprietary_codecs=true ffmpeg_branding="Chrome"'
autoninja -C out/Default chrome_public_apk
```

注意：`target_cpu` 用 `arm64`（真机）；Titanium 的 `args.gn` 写的是 `arm`，不要照抄。

---

## 9. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 上游把 desktop-android 扩展当实验特性，随时改结构 | patch 反复失配 | 补丁最小化 + 每晚对 `main` 试 rebase + 优先把 phone 承载点**上游化**（提 CL） |
| A 配置的 UI 是桌面化窗口模型，手机不可用 | 需转 B 配置，编译期风险 | P0 同时准备 B 的 args.gn；B 失败再评估「A + 收敛 UI」 |
| Play 政策：浏览器内执行第三方代码 | 上架被拒 | 早期就跟 Play 沟通（浏览器类豁免惯例：Chrome/Edge/Firefox 均如此）；权限提示、安全浏览、可关闭扩展 |
| CWS 抓取/安装接口的 ToS | 分发受限 | 自建商店 + 侧载 CRX/zip 为默认，CWS 仅作"打开链接"降级 |
| GPL 污染 | 商用受限 | 不引入 Titanium 代码；只参考其**问题清单**，补丁独立实现 |
| 内存/耗电 | 中低端机体验差 | 扩展按需加载、进程优先级、single-renderer 策略；实测后才调 |
| 我们自己扩展的私有 API 依赖 | 旗舰功能不可用 | P0 就把 `lumo` 的 manifest 权限清单与上游 feature 表逐条对齐 |

---

## 10. 非目标（现在就写下来，避免反复讨论）

1. Flutter 外壳（已有 Compose 资产；Chromium Android UI 是 Java/Views）。
2. WebView + shim 运行时（缺 `chrome-extension://`、请求头改写、SW 语义；报告已论证）。
3. MITM 代理改请求头（证书 + 用户体验代价）。
4. Kiwi/Edge 代码复用（前者停更，后者闭源）。
5. 承诺 `tabCapture` / `devtools` 面板 / 多窗口语义。
6. 云浏览器（延迟、隐私、离线）。

---

## 11. 首周 checklist

- [ ] 装 depot_tools，`fetch android`（`--no-history`），跑通 `install-build-deps.sh`
- [ ] A 配置出包，装到真机，确认基础浏览可用
- [ ] 开发者模式加载 `lumo`（未打包目录），记录：action 图标是否出现、popup 是否可开、SW 是否启动、sidePanel 是否可开、content script 是否注入
- [ ] 同样测 `lumo-userscript-manager`：`chrome.userScripts` 注册是否成功、GM API 是否可用
- [ ] `chrome://extensions` 在手机上截图，记录视口/触摸问题
- [ ] 试装 3 个流行 CWS 扩展（选 uBlock Origin Lite / Dark Reader / Bitwarden 类），记录失败点与日志
- [ ] 产出 `docs/p0-gap-matrix.md`：每条 = 能力 / 结果 / 证据（日志、截图、crbug）/ 需要的 patch
- [ ] 决定 A 还是 B（或 A 收敛 UI），并把决定写回本文 §5

> 只有 P0 的实测缺口表出来之后，§6 的 patch 优先级才是可信的；在那之前它是基于源码阅读的推断。
