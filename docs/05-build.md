# 构建约束

## 1. out 目录与 flavor

| 场景 | out 目录 |
|---|---|
| 日常迭代（`FAST=1`，非 official） | `out/lumo-a` |
| 验收 / 发布（`FAST=0`，official） | `out/lumo-a-rel`；历史目录 `out/lumo-rel` 会被自动复用 |

- 一个 flavor 一个目录。`FAST` 改变 `is_official_build`，共用目录会让几乎所有目标失效。
- 解析优先级：显式 `OUT_DIR` > `out/lumo-<config>-rel` > 历史 `out/lumo-rel` > `out/lumo-<config>`；
  定义在 `scripts/lib/common.sh:resolve_out_dir`。
- 只用 `DRY_RUN=1 scripts/chromium/build.sh <config>` 确认解析结果，不要手工改 `args.gn`。

## 2. GN 参数（`scripts/chromium/args.sh` 是唯一出处）

| 参数 | 取值 | 原因 |
|---|---|---|
| `is_desktop_android` | config `a` = `true` | 上游唯一带完整扩展 UI 的 Android 形态 |
| `enable_desktop_android_extensions` | config `b` = `true` | 非 desktop-android 构建强制编译扩展核心；**实测被上游 gn 断言阻塞**（见 §3） |
| `is_official_build` | `FAST=0` 时 `true` | 非 official 会启用 UBSan hardening trap 与 `DCHECK_ALWAYS_ON`，老 Adreno 上 GPU 进程 abort |
| `use_thin_lto` | `false` | 迭代期链接时间优先 |
| `chrome_pgo_phase` | `0` | 官方 tarball 不带 PGO profile |
| `symbol_level` | `0` | 控制产物体积 |
| `google_api_key` 等 | `"x"` | 无 Google 服务凭据，关闭云功能 |
| `chrome_public_manifest_package` | `dev.lumo.browser` | 产品包名 |

## 3. 配置 b 的约束

`target_os="android"` + `enable_desktop_android_extensions=true`（`is_desktop_android=false`）**不可直接编译**：

```
//chrome/browser/new_tab_page/BUILD.gn: assert(enable_webui_ntp)
    ← //chrome/browser/extensions/BUILD.gn:2568
//ui/webui/resources/cr_components/theme_color_picker/BUILD.gn:
    assert((!is_android && !is_ios) || is_desktop_android)
```

即会滑进只对 `desktop_android` 成立的 WebUI/资源假设，需要专属补丁子集。
`build.sh b` 会提前告警并在 `gn gen` 阶段失败；`a` 是交付配置。

## 4. 改动预算（三问）

1. 能做扩展吗 → 扩展仓库（不编内核）
2. 上游已有代码、只是默认值/开关不对 → `scripts/chromium/flags.sh`
3. 上游缺代码 → `patches/`（C++ 单文件约 25 s；Java 约 2 min，dex 是瓶颈）

参考量级（12 核）：`build.sh` 空跑约 20 s，全量 2–4 h。结构性改动不要指望"快"。

## 5. 缓存

```bash
scripts/chromium/cache.sh manifest [out_dir]    # 版本 / clang / depot_tools / args.gn / patch sha / apk sha
scripts/chromium/cache.sh snapshot [out_dir]    # out/<dir> → artifacts/cache/out-*.tar.zst
scripts/chromium/cache.sh restore <archive> [dir]
```

`out/<dir>` 就是编译缓存。恢复的前提：同一 Chromium 版本、同一 clang/depot_tools、同一绝对路径、
同一批编译类 GN 参数；不满足就直接重编。

## 6. 签名

`args.sh` 注入 `android_keystore_*`，指向 `keys/lumo-dev.jks`（由 `keys.sh` 复制到
`$CHROMIUM_SRC/lumo-signing/`，因为 GN 只解析 `//` 相对路径）。

- 只影响 apk 打包步骤：改签名不触发重编译。
- dev key 是公开的，仅用于 debug/自测；正式分发另建 release key。
- 规则与指纹见 `keys/README.md`，威胁模型见 `SECURITY.md`。

## 7. 禁止

- `FAST=0` 与 `FAST=1` 共用 out 目录。
- 改 `is_official_build` / `target_cpu` / `is_debug` 后还指望增量。
- `rm -rf out/` 清理空间（先 `cache.sh snapshot`）。
- 提交 `out/`、`artifacts/`、APK、Chromium 源码。
- 用 `gclient sync` / `fetch.sh` 解决本网络的依赖问题（见 [01-architecture.md](01-architecture.md) §6）。
