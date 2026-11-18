# GN 参数（`scripts/chromium/args.sh`）

`args.sh` 是唯一出处：`build.sh` 和 `fix-missing-deps.sh` 都调用它，不要另写 `args.gn`。

## 输出示例（config a，FAST=1）

```gn
target_os = "android"
target_cpu = "arm64"
is_debug = false
is_official_build = false          # FAST=1
use_thin_lto = false
chrome_pgo_phase = 0               # 官方 tarball 不带 PGO profile
is_component_build = false
symbol_level = 0
is_desktop_android = true          # config a
disable_fieldtrial_testing_config = true
proprietary_codecs = true
ffmpeg_branding = "Chrome"
enable_arcore = false
enable_vr = false
enable_openxr = false
enable_cardboard = false
enable_remoting = false
enable_reporting = false
google_api_key = "x"               # 占位，禁用 Google 服务
google_default_client_id = "x"
google_default_client_secret = "x"
use_rtti = false
icu_use_data_file = true
include_both_v8_snapshots = false
chrome_public_manifest_package = "dev.lumo.browser"
android_keystore_path = "//lumo-signing/lumo-dev.jks"
android_keystore_name = "lumo"
android_keystore_password = "lumodebug"
```

config b 额外加一行：

```gn
enable_desktop_android_extensions = true   # 见 extensions/buildflags/buildflags.gni
```

## 为什么是这些值

| 参数 | 原因 | 改了会怎样 |
|---|---|---|
| `is_official_build` | FAST=0 用于验收：非 official 的 Android 构建会打开 UBSan hardening trap（array-bounds/return/unreachable）与 `DCHECK_ALWAYS_ON`，在老 Adreno 上 GPU 进程直接 abort | 切换 = 近乎全量重编（所以按 flavor 分 out 目录） |
| `use_thin_lto` | 默认 false：ThinLTO 让链接时间翻倍，迭代期得不偿失 | 链接变慢，产物略小 |
| `chrome_pgo_phase = 0` | PGO profile 来自 DEPS 的 GCS 条目，tarball 没有；开了会构建失败 | 性能小幅下降，构建失败 |
| `symbol_level = 0` | 产物 343 MB；symbol 会让 out 目录再涨数 GB | 崩溃栈不可读 |
| `is_desktop_android = true`（config a） | 上游唯一被 CI 覆盖的 Android 扩展形态；扩展栈（工具栏/菜单/side panel/windowing）随 `enable_desktop_android_extensions` 默认打开 | 手机形态需要靠补丁收敛（0002/0009/0010/0011） |
| `enable_desktop_android_extensions = true`（config b） | 非 desktop_android 构建里强制编译扩展核心；`internal` vs `stub` 只看 `enable_extensions_core`（`chrome/android/BUILD.gn`） | 需要全量构建；部分代码假设 `is_desktop_android`，可能运行期崩 |
| `google_api_key = "x"` 等 | 无 Google 服务凭据；用占位符关闭同步/登录等 | 云功能不可用（预期） |
| `enable_reporting/remoting/vr/arcore = false` | 减小体积与攻击面，避免拉入不需要的依赖 | 构建变慢、体积变大 |
| `android_keystore_*` | 仓库内 dev key（`keys/README.md`）；GN 只解析 `//` 路径，所以 `keys.sh` 先复制进源码树 | 只影响签名步骤：不重编，只重签（~32 s） |

## 常用覆盖

```bash
# 验收包（official）
FAST=0 scripts/chromium/build.sh a

# 指定 out 目录（一般不要；脚本已按 flavor 分配）
OUT_DIR=out/lumo-rel scripts/chromium/build.sh a

# 指定并行度（默认 nproc；内存紧张时降到 8-10）
JOBS=8 scripts/chromium/build.sh a

# 只看解析结果
DRY_RUN=1 scripts/chromium/build.sh a
```

## 自检

```bash
scripts/chromium/args.sh a | tee /tmp/args-a.gn
diff <(cat ~/chromium/src/out/lumo-a/args.gn) /tmp/args-a.gn   # 应与生成的一致
```

> 改了 `args.sh` 后，若 `args.gn` 内容变化，gn 会重写 `build.ninja`，下一次构建的耗时
> 取决于改的是哪一类参数：`android_keystore_*` 只重签，`is_official_build`/`target_cpu`/`is_debug`
> 近乎全量。
