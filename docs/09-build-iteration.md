# 构建与迭代模型（实测数据）

问题：**每次改动都要全量构建吗？内核能不能“编译一次、存成二进制、以后不再编译”？**

短答：不是全量。`out/<dir>` 就是编译缓存，改一个 Java 文件约 2 分钟、改一个 C++ 文件约 25 秒。
“所有功能都不再编内核”做不到，但可以做到**每个 Chromium 版本只全量编译一次**——前提是把功能按下面
三层拆开：扩展层（不编）、运行时开关层（不编）、结构性内核补丁（编，但有限且可门控）。

本机基线：12 核 / 60G / NVMe，Chromium `160.0.8157.0`，`chrome_public_apk`。

---

## 1. 流水线

```
scripts/chromium/build.sh [a|b]
  ├─ apply-patches.sh   patches/NNNN-*.patch 顺序 git apply（sha256 stamp 幂等）
  ├─ keys.sh install    keys/lumo-dev.jks → $CHROMIUM_SRC/lumo-signing/（GN 只能 // 相对路径）
  ├─ brand.sh           名称 + 图标（内容比对后才写，见 §5）
  ├─ gn gen             args.sh 生成 args.gn（~5s）
  ├─ autoninja(siso)    增量：只重编受影响的 TU / javac / dex / 链接 / 重签
  └─ 归档               artifacts/apk/lumo-<config>-<ts>.apk + lumo-latest.apk
```

`OUT_DIR` 默认 `out/lumo-<config>`（FAST=1）或 `out/lumo-<config>-rel`（FAST=0）；
旧的 `out/lumo-rel` 会被自动复用，避免升级脚本后误触发一次数小时的全量构建。

## 2. 实测：改动 → 成本

| 场景 | 实测 | 触发的东西 |
|---|---|---|
| 无改动（no-op） | **5.6 s** | `ninja: no work to do` |
| `touch` 一个 .java（内容不变） | 9.9 s | siso 按内容哈希，bytecode 相同 → 不连锁 |
| 改一个 .java（bytecode 变化，如 patches/0009/0010/0011） | **1 m 53 s** | javac 4s + **dex/分 dex ~90s（瓶颈）** + 打包 APK |
| 改一个 .cc（如 patches/0003/0005/0006/0008） | **25 s** | 编译 0.8s + 重链 `libchrome.so` 18s + 打包 1s |
| 只改签名（keystore args） | **32 s** | 只用 apksigner 重签，零编译 |
| `gn gen` | 5 s | args 不变时几乎免费 |
| 换 `FAST`/换 args 形状 | 近乎全量 | `is_official_build` 改变 → 几乎所有 .o 失效 |
| 全新 out 目录（首次/换版本） | 小时级（12 核经验 2–4 h，本机未实测） | 全部编译 + 链接 |
| 你们的日常一次构建（`siso_metrics`） | 110–125 s | 与上表一致 |
| `build.sh` 端到端 no-op | **19 s** | gn gen 5s + 图标渲染 3s + `about_credits.html` 3s（上游每次重生成）+ keytool 1s + siso 7s |

只想看脚本解析到哪个 out 目录、会不会触发全量：`DRY_RUN=1 scripts/chromium/build.sh a`。

复现方式：

```bash
time autoninja -C out/lumo-rel chrome_public_apk        # no-op
# 改一个 .java 后再跑；op 计时看 out/*/siso_metrics*.json 的 duration_nanos
```

**结论**：瓶颈是 dex/打包（Java 层）而不是编译内核本身。C++ 内核补丁的代价比想象中小得多。

## 3. 三类改动，三条迭代路径

| 层 | 例子 | 迭代方式 | 编内核？ |
|---|---|---|---|
| **A 扩展层** | AI 侧栏（`../lumo`）、用户脚本管理器、拦截规则、下载器、ainew 面板 | `npm run build` → `scripts/device/ext-install.sh`（push + `--load-extension`） | 否 |
| **B 运行时开关层** | 侧栏开关、拖宽、日志、userScripts 策略、GPU 兼容开关 | `scripts/chromium/flags.sh`（`--enable-features` / `--disable-features`）+ `chrome://flags` | 否（前提：代码已编进二进制） |
| **C 结构性内核补丁** | 手机工具栏缺 `extensions_toolbar_container_stub`、bottom sheet、popup 锚点、detach 修复 | `patches/NNNN-*.patch` → `build.sh` | 是（25s–2min） |

判断一个需求属于哪层（**内核改动预算三问**）：

1. 能做成扩展/内容脚本吗？→ A
2. 上游已有代码，只是默认值/开关不对？→ B（**不要打补丁**）
3. 上游**没有**这段代码/挂载点？→ C（才允许进 `patches/`，并且尽量用 feature flag 门控）

`patches/0003` 属于第 2 类：它只是把 `kEnableAndroidSidePanel` /
`kEnableAndroidSidePanelManualResizing` 的默认值翻成 ENABLED，而这两个 feature 已经暴露给命令行
（`chrome/browser/flags/android/chrome_feature_list.cc:425-428`）。因此它可以被运行时覆盖：

```bash
LUMO_DISABLE_FEATURES=EnableAndroidSidePanel,EnableAndroidSidePanelManualResizing \
  scripts/chromium/flags.sh push      # 不重编译就能回到“无侧栏”做回归
```

> 注意：**不要**因此删掉 0003。命令行 flag 只在 `am set-debug-app` 握手/可调试运行时生效，
> 普通用户安装启动时读不到它；编译默认值仍然是产品默认行为。B 层的用途是**实验、灰度、回滚**，
> 不是替代产品默认值。

## 4. 运行时开关通道：`flags.sh`

```bash
scripts/chromium/flags.sh presets                 # 与 Lumo 相关的可切换 feature 及当前默认值
scripts/chromium/flags.sh compose                 # 打印将要写入的命令行（不碰设备）
scripts/chromium/flags.sh push                    # 写 /data/local/tmp/chrome-command-line + set-debug-app
scripts/chromium/flags.sh show                    # 看设备当前内容
scripts/chromium/flags.sh clear                   # 删掉，回到上游默认
```

环境变量：`LUMO_EXTENSIONS`（逗号列表，绝对路径优先）、`LUMO_EXT_ROOT`、`LUMO_FEATURES`、
`LUMO_DISABLE_FEATURES`、`LUMO_FLAGS`。所有设备脚本（`ext-install.sh`/`run.sh`/`verify.sh`）
都走这一个入口，避免“三处手写命令行、各自踩引号坑”。

约束（写进脚本里做了校验）：

- `--load-extension` 只有一个值，多个扩展**必须逗号分隔**（重复 flag 只生效最后一个）。
- 命令行只从 `/data/local/tmp` 读；共享存储里的同名文件会被主动删除
  （否则任何有 all-files 权限的 App 都能注入 `--load-extension` / `--remote-debugging-port`）。
- 只支持 `set-debug-app` 握手，不依赖 root 改 `/data/local`。

## 5. “把内核存成二进制”：`cache.sh`

真正可复用的“内核二进制”就是 `out/<dir>`（siso 的 action 状态 + 所有 .o + APK），不是单独一个 .so。

```bash
scripts/chromium/cache.sh manifest [out_dir]    # 内核身份：版本/clang/depot_tools/args.gn/patch sha/APK sha
scripts/chromium/cache.sh snapshot [out_dir]    # out/lumo-rel → artifacts/cache/out-*.tar.zst（~9.3G → 数 G）
scripts/chromium/cache.sh restore <archive> [out_dir]
scripts/chromium/cache.sh list
```

恢复的前提（不满足就不要恢复，直接重编）：

- 同一个 Chromium tarball（`chrome/VERSION` 一致）
- 同一个 clang / depot_tools CIPD 版本（见 manifest）
- 同一个绝对路径（默认 `$HOME/chromium/src`）

跨 Chromium 版本升级时缓存必然失效——这也正是“内核只在换版本时全量编一次”的节奏。

**不建议**做的两条路：

- 直接改 APK 里的 `classes.dex` / 替换 `libchrome.so`：单体 `libchrome.so` + 资源 ID + 版本校验，
  维护成本远高于重编 25 秒；只在线上热修单个 Java 常量时才有意义。
- siso 远端缓存（RBE）：siso 1.6.9 支持 REAPI，但需要 Google 凭据/自建 RBE；个人项目收益为负。
  siso **没有**本地磁盘 action cache，本地缓存就是 out 目录本身。

## 6. 签名密钥（稳定、入库、仅 debug）

| 项 | 值 |
|---|---|
| 文件 | `keys/lumo-dev.jks`（**故意** git 管理） |
| 别名 / 口令 | `lumo` / `lumodebug` |
| 证书 SHA-256 | `14:43:04:4D:CF:72:11:1D:14:6C:28:A4:ED:27:E8:C7:D8:4A:63:32:76:4B:DF:13:87:17:AE:A5:18:80:52:5E` |
| 用途 | **仅** `dev.lumo.browser` 的 debug/自测/真机验收构建 |
| 接线 | `args.sh` → `android_keystore_path/name/password` → apksigner |

为什么入库：固定 key 之后 `pm install -r` 才能覆盖升级（profile、扩展、用户脚本开关、登录态全部保留），
否则每次构建都要卸载重装。代价是它是**公开**的（和上游 `build/android/chromium-debug.keystore` 同等级），
所以：

- 只用于 debug；**不能**上架，**不能**当作“官方包”证明。
- 校验一个包是否可信，请比对 manifest 里的 `apk sha256`，而不是看签名“有没有”。
- 未来做商店分发时另建 `keys/lumo-release.jks`，**绝不入库**，走 CI secret。

## 7. 反模式清单

| 反模式 | 后果 | 正确做法 |
|---|---|---|
| `FAST=0` 与 `FAST=1` 共用一个 out 目录 | 每次切换几乎全量重编 | 每个 flavor 一个 out 目录（脚本已分开） |
| 以为“改 args 也是增量” | `is_official_build`/`target_cpu`/`is_debug` 改变 → 全量 | 定稿 args 后再开始迭代 |
| 值不变也重写资源文件/图标 | mtime 变、资源管线变脏、出现“莫名其妙的重编” | `brand.sh` / `render-icons.py` 已做内容比对 |
| 用 `--enable-features` 替代产品默认值 | 用户正常启动时拿不到 flag | 默认值编进去，flag 只做实验/回滚 |
| 把 `out/` 提交进 git | 仓库爆炸 | 用 `cache.sh snapshot` 归档到 `artifacts/`（已 gitignore） |
| 每个需求都打 patch | 补丁集膨胀、rebase 成本指数上升 | 先过“三问”，C 层才进 `patches/` |

## 8. 当前已知缺口

- **配置 b 实测不可直接编译**（2026-11-18）：`FAST=0 build.sh b` 在 `gn gen` 阶段被上游断言拦住
  （`assert(enable_webui_ntp)` → `theme_color_picker` 要求 `is_desktop_android`，见
  `docs/00` §5）。这不是 build flag 能组合出来的形态，需要专属补丁子集。
  结论：`a` 是唯一可交付配置；`b` 若要做，按独立项目排期，不要用 `build.sh b` 试探。
- 因此“切换配置 = 一次全量构建”的代价目前**不会发生**：只维护 `out/lumo-a`（FAST）与
  `out/lumo-rel`（official）。
- `nativeMessaging` / `desktopCapture` / `devtools.*` 是平台限制，补丁解决不了（见 `07-capability-matrix.md`）。
