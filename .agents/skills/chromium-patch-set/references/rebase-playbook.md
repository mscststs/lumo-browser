# Chromium 升级 / 补丁失败的处理手册

## 0. 前提事实

- `~/chromium/src` 是**没有 commit** 的 git 仓库（GCS tarball 解压而来）：
  `git apply` / `git apply --reverse --check` 可用，`git diff` / `git checkout --` 不可用。
- 因此补丁靠 `patches/*.patch` + `.lumo-patches/*.stamp` 维护；
  编写新补丁用 `scripts/chromium/patchwork.sh`。
- 升级 Chromium = **唯一值得全量构建的时刻**，且必须换新 out 目录。

## 1. 升级步骤

```bash
# 1) 新 tarball（版本号从 https://chromiumdash.appspot.com/releases 查）
mkdir -p artifacts/src
curl -L -o artifacts/src/chromium-<NEW>.tar.xz \
  https://commondatastorage.googleapis.com/chromium-browser-official/chromium-<NEW>.tar.xz

# 2) 新的源码目录（不要覆盖旧树，旧树是回滚基准）
export CHROMIUM_SRC="$HOME/chromium/src-<NEW>"     # 或干脆 mv src src-old && extract
scripts/chromium/extract.sh artifacts/src/chromium-<NEW>.tar.xz

# 3) 依赖与工具链（DEPS 变了就要重跑）
scripts/chromium/cipd-deps.sh
scripts/chromium/toolchain.sh
scripts/chromium/fix-missing-deps.sh a

# 4) 补丁：新树里没有 stamp，会全部重放
scripts/chromium/apply-patches.sh            # 第一条失败处停下来

# 5) 新 out 目录（不要复用旧 out：args/code 都变了）
FAST=1 OUT_DIR=out/lumo-a-<NEW> scripts/chromium/build.sh a

# 6) 真机验收 + 文档
scripts/device/install.sh && scripts/device/verify.sh
```

## 2. 单条补丁失败

`apply-patches.sh` 的报错形如：

```
failed to apply 0010-sidepanel-bottom-sheet.patch (rebase needed: git -C ~/chromium/src am -3 ...)
```

处理顺序：

1. **看失败 hunk**：`(cd ~/chromium/src && git apply --verbose patches/0010-*.patch 2>&1 | head -20)`
2. **判断是“上游改了上下文”还是“上游已实现该功能”**：
   - 上下文漂移 → 重做补丁（见 §3）
   - 上游已实现 → 删除该补丁（见 `SKILL.md` §5），并更新 `patches/README.md`、`docs/06`
3. **不要**用 `patch -p1 --fuzz` 或手工改到“能 apply”为止——stamp 会与补丁内容不一致，
   下次重放必炸。

## 3. 重做一条补丁

```bash
# 1) 找到上游对应文件的现状
cd ~/chromium/src
sed -n '1,80p' chrome/browser/ui/side_panel/internal/android/java/src/.../SidePanelContainerCoordinatorImpl.java

# 2) 用 patchwork 记录 pristine 状态
~/lumo-browser/scripts/chromium/patchwork.sh start \
  ~/lumo-browser/patches/0010-sidepanel-bottom-sheet.patch \
  chrome/browser/ui/side_panel/internal/android

# 3) 按新上下文重新实现（保持同样的行为与注释意图）
#    - 保留原补丁的“为什么”
#    - 如果上游把方法改名/拆类，跟着改，不要为了少改而绕路

# 4) 导出并验证
~/lumo-browser/scripts/chromium/patchwork.sh export
(cd ~/chromium/src && git apply --check ~/lumo-browser/patches/0010-*.patch)
~/lumo-browser/scripts/chromium/patchwork.sh revert
~/lumo-browser/scripts/chromium/apply-patches.sh      # 全量重放

# 5) 删掉对应的 stamp，确保下次不会被跳过
rm -f ~/chromium/src/.lumo-patches/0010-*.stamp
```

> 重要：**改了补丁文件内容就必须让 stamp 失效**（删 stamp 或让 sha256 变化后手动删除），
> 否则 `apply-patches.sh` 会认为“已应用”。

## 4. 构建/运行期才发现的问题

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 编译错误：符号不存在 | 上游重命名/删除 API | 按新 API 重做补丁 |
| 编译错误：`kFeature` 未声明 | feature 清单文件变了 | 检查 `chrome_feature_list.cc` 的声明与 `kFeaturesExposedToJava` |
| 运行崩溃，栈在补丁文件里 | 上游生命周期变了（如侧栏 detach 路径） | 参考 `docs/08` 的审计方式，重新处理生命周期 |
| 功能静默失效 | 上游把默认值改成 ENABLED/DISABLED | 对比 `patches/0003` 的思路：优先用编译默认值 + 运行时覆盖 |

## 5. 回滚到旧版本

旧源码树 + 旧 out 目录都保留时：

```bash
export CHROMIUM_SRC="$HOME/chromium/src-old"
FAST=0 scripts/chromium/build.sh a
scripts/device/install.sh artifacts/apk/lumo-latest.apk
```

这也是为什么要 `cache.sh snapshot`：旧 out 目录一旦删除，回滚需要重新全量。

## 6. 升级后的文档义务

- `docs/06-status.md`：新版本号 + 新证据路径
- `docs/01-architecture.md`：若上游代码位置/`enable_extensions_core` 逻辑变化
- `patches/README.md`：每条补丁的状态与删除/新增
- `README.md` / `AGENTS.md` 的版本徽章与“快速事实”表
