---
name: chromium-android-build
description: Build Lumo Browser (Chromium for Android) from the pristine official tarball, and keep iteration fast. Use when asked to build the APK, set up the Chromium checkout/toolchain, speed up or debug an incremental build, choose or repair an out directory, cache/restore the build tree, change GN args, or inspect the signing key.
---

# Chromium Android 构建与迭代

## 0. 先记住三件事

1. **源码在仓库外**：`~/chromium/src`，本仓库只有补丁与脚本。永远不要提交源码或 `out/`。
2. **不是每次全量**：`out/<dir>` 就是编译缓存。改一个 C++ 文件 ≈ 25 s，改一个 Java 文件 ≈ 2 min，
   `build.sh` 端到端空跑 ≈ 19 s，全量 2–4 h。
3. **一行一个 flavor**：`FAST` 改的是 `is_official_build`，同一个 out 目录混用 = 几乎全量重编。

## 1. 事实

| 项 | 值 |
|---|---|
| 源码 | `~/chromium/src`，`chrome/VERSION` = `160.0.8157.0` |
| depot_tools | `~/depot_tools`（`common.sh` 自动加进 PATH） |
| 目标 | `chrome_public_apk`；产物 `~/chromium/src/out/<dir>/apks/ChromePublic.apk` |
| 归档 | `artifacts/apk/lumo-<config>-<ts>.apk` + `lumo-latest.apk` 符号链接 |
| out 目录 | `out/lumo-a`（FAST，config a）、`out/lumo-rel`（official，config a 的历史目录）、`out/lumo-b[-rel]`（未构建） |
| 签名 | `keys/lumo-dev.jks` → 由 `keys.sh` 复制到 `$CHROMIUM_SRC/lumo-signing/` |

## 2. 判断该做什么

| 情况 | 动作 |
|---|---|
| 第一次在这台机器上 | `scripts/chromium/doctor.sh` |
| 没有源码树 | `extract.sh`（GCS tarball，本网络唯一可行）→ `cipd-deps.sh` → `toolchain.sh` |
| `gn gen` 报 `Unable to load //third_party/...` | `scripts/chromium/fix-missing-deps.sh a` |
| 日常改代码后 | `scripts/chromium/build.sh a`（增量） |
| 要出验收/发布包 | `FAST=0 scripts/chromium/build.sh a` |
| 怀疑触发了全量 | `FAST=... DRY_RUN=1 scripts/chromium/build.sh a` 看解析到的 out 目录 |
| 换机器/重装 | `scripts/chromium/cache.sh restore <archive>` 后仍要 `gn gen`（args 一致时 siso 复用） |
| 只想看内核身份 | `scripts/chromium/cache.sh manifest` |

## 3. 标准流程（增量）

```bash
scripts/chromium/doctor.sh                 # 0. 环境
scripts/chromium/apply-patches.sh          # 1. 幂等：stamp 命中就跳过
scripts/chromium/keys.sh install           # 2. 签名密钥就位（build.sh 会自动做）
scripts/chromium/brand.sh                  # 3. 品牌化（内容比对后才写）
FAST=1 scripts/chromium/build.sh a         # 4. gn gen + autoninja(siso) + 归档
scripts/device/install.sh                  # 5. 装机（MIUI 走 root pm install）
```

`build.sh` 末尾会打印本次耗时和证书指纹，两者都要抄进提交正文/验收记录。

## 4. 成本模型（决定优化方向）

| 改动 | 实测 | 主要开销 |
|---|---|---|
| 纯 no-op（直接 autoninja） | 5.6 s | 无 |
| `build.sh` 端到端 no-op | 19 s | gn gen 5 s + 图标 3 s + `about_credits.html` 3 s + keytool 1 s |
| 一个 .cc | 25 s | 编译 0.8 s + 重链 `libchrome.so` 18 s |
| 一个 .java | 1 m 53 s | javac 4 s + **dex ~90 s** + 打包 |
| 只改签名参数 | 32 s | 仅 apksigner |
| 改 args 形状（FAST/目标/ABI） | 近乎全量 | 所有 .o 失效 |
| 全新 out | 2–4 h | 全部编译 + 链接 |

推论：**Java 层是瓶颈，不是内核编译**。能放到扩展/运行时的改动优先放出去。

## 5. 常见故障

见 `references/troubleshooting.md` 的完整故障树。三条最高频：

1. `gclient_entries missing, .gclient file in parent directory` —— **无害**（tarball 没有 `.gclient_entries`），
   不要为此去跑 `gclient sync`（本网络会挂）。
2. `gn gen` 说缺 `//third_party/xxx` —— 官方 tarball 省略了 `checkout_android` 依赖，
   用 `fix-missing-deps.sh` / `fetch-dep.sh` / `fetch-tree.sh` 补齐，并把结论写进 `docs/01`。
3. 构建莫名变慢/全量 —— 九成是 `FAST` 或 `OUT_DIR` 与上次不同。用 `DRY_RUN=1` 确认。

## 6. 禁止

- 在 `~/chromium/src` 里 `sed -i` 改源码后直接构建而不产出补丁（下次重放就丢）。
- 手工 `rm -rf out/`“清理一下”（等于放弃几小时编译缓存；用 `cache.sh snapshot` 先归档）。
- 把 `out/`、APK、源码提交进仓库。
- 用 `gclient sync` 或 `fetch.sh` 解决网络问题（先读 `references/troubleshooting.md`）。

## 7. 参考

- `references/gn-args.md`：每个 GN 参数为什么这么设
- `references/out-dirs-and-costs.md`：out 目录规则、成本实测方法与原始数据
- `references/troubleshooting.md`：故障树
- 仓库内：`docs/09-build-iteration.md`、`docs/01-architecture.md`
