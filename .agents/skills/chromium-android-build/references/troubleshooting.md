# 构建故障树

按出现频率排序。每条都给出**判定依据**和**不要做什么**。

## 1. `gclient_entries missing, .gclient file in parent directory`

```
/home/bob/chromium/.gclient_entries missing, .gclient file in parent directory
```

- 判定：**无害噪音**。官方 tarball 没有 `.gclient_entries`，gn/siso 只是提示。
- 不要做：为了消掉它去跑 `gclient sync`（本网络 googlesource 的 git smart-HTTP 不可用，
  `ls-remote` 会挂到超时）。

## 2. `gn gen` 失败：`Unable to load //third_party/xxx/BUILD.gn`

```bash
scripts/chromium/fix-missing-deps.sh a      # 解析 gn 报错，逐个补
# 单个依赖/子目录：
scripts/chromium/fetch-dep.sh third_party/xxx <git-url> <40-char-rev>
scripts/chromium/fetch-tree.sh third_party/androidx/local_modifications
```

- 根因：GCS 官方 tarball 省略了 `checkout_android` 的 git 依赖与部分 CIPD 条目。
- 补完把结论写进 `docs/01-architecture.md` §6，避免下次重复踩。

## 3. 构建突然变成全量（几小时）

- 先看解析结果：`FAST=... DRY_RUN=1 scripts/chromium/build.sh a`。
- 九成原因：`FAST` 与上次不同（`is_official_build` 变了），或 `OUT_DIR` 换了。
- 也可能是：`args.sh` 里改了 `target_cpu`/`is_debug`/`is_desktop_android`。
- 不要做：用 `rm -rf out/` "清理"。要腾空间用 `cache.sh snapshot` 后手动移走旧目录。

## 4. 安装后 GPU 进程崩溃 / 浏览器秒退

- 先确认包是 official：`FAST=0`。非 official Android 构建会启用 UBSan hardening trap 与
  `DCHECK_ALWAYS_ON`，在老 Adreno 上直接 abort（见 `args.sh` 注释与 `docs/05-build.md`）。
- 仍崩：`--disable-features=Vulkan` 试一次（补丁 0005 保证被尊重）；
  GPU 信息收集走 ES2 回退（补丁 0006）。
- 证据：`adb logcat | grep -iE "gpu|angle|vulkan|abort"`，写进提交正文；稳定的结论写进 0005/0006 的补丁注释。

## 5. 签名相关

| 症状 | 原因 | 解决 |
|---|---|---|
| `Assignment had no effect: android_keystore_path` | 拼错参数名，或非 Android 构建 | 用 `args.sh` 的输出，别手写 |
| `apksigner ... Failed to load keystore` | 未 `keys.sh install`，或 GN 路径不是 `//` 相对 | `scripts/chromium/keys.sh install` 后重跑 `build.sh` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 设备上是旧 key 签的包 | 卸载一次重装（之后就能 `-r` 覆盖） |
| 想换回上游公开 debug key | 临时排查 | `LUMO_KEY_PASSWORD=chromium` 不起作用；改 `args.sh` 的 `android_keystore_path` 为 `//build/android/chromium-debug.keystore` |

## 6. 磁盘 / 内存

- out 目录 9–11 GB，源码 30 GB，tarball 5.4 GB：留 ≥120 GB。
- 内存不足的表现：linking 被 OOM kill、`siso` 报 worker 退出。降并发：`JOBS=8 scripts/chromium/build.sh a`。
- 清理优先级：旧 APK（`artifacts/apk/`，每个 350 MB）→ 旧 out 目录（先 snapshot）→ 旧 tarball。

## 7. siso / ninja 行为

- `Run 'siso ps -C out/lumo-rel'` / `There are still N static analysis jobs running`：正常提示。
- `AI_AGENT` 环境变量会让 depot_tools 加 `--quiet --batch=false`：输出变少，不是失败。
- 想看真实执行的规则：`tail -20 out/lumo-rel/.ninja_log`。

## 8. 补丁应用失败

```
failed to apply NNNN-xxx.patch (rebase needed: git -C ~/chromium/src am -3 patches/...)
```

- 说明源码树不干净或上游代码变动。处理流程见 `.agents/skills/chromium-patch-set/references/rebase-playbook.md`。
- 不要做：手工 `patch -p1` 糊过去（stamp 与补丁会不一致）。

## 9. 首次搭建（tarball 路径）

```bash
mkdir -p artifacts/src
curl -L -o artifacts/src/chromium-160.0.8157.0.tar.xz \
  https://commondatastorage.googleapis.com/chromium-browser-official/chromium-160.0.8157.0.tar.xz
scripts/chromium/extract.sh artifacts/src/chromium-160.0.8157.0.tar.xz
scripts/chromium/cipd-deps.sh && scripts/chromium/toolchain.sh
```

`scripts/chromium/fetch.sh` 只有在 git smart-HTTP 可用时才值得用；本机不要用。
