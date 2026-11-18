# out 目录规则与成本实测

## 1. 规则

```
out/lumo-a         config a, FAST=1（is_official_build=false）   ← 日常迭代
out/lumo-rel       config a, FAST=0（official）                  ← 验收/发布（历史目录名，脚本自动复用）
out/lumo-b         config b, FAST=1                              ← 未构建
out/lumo-b-rel     config b, FAST=0                              ← 未构建
```

- 一个 flavor 一个目录。`FAST` 改变全局编译参数，混用 = 几乎全量重编。
- `build.sh` 的解析优先级：显式 `OUT_DIR` > `out/lumo-<config>-rel`（FAST=0）> 历史 `out/lumo-rel`
  > `out/lumo-<config>`（FAST=1）。用 `DRY_RUN=1` 确认。
- 目录大小参考：`out/lumo-rel` ≈ 9.3 GB，`out/lumo-a` ≈ 11 GB。磁盘要留 2 倍余量。

## 2. 成本实测（12 核 / 60 GB / NVMe）

| 场景 | 墙钟 | 说明 |
|---|---|---|
| 直接 `autoninja` no-op | 5.6 s | `ninja: no work to do` |
| `build.sh` 端到端 no-op | 19 s | gn gen 5 s + 图标渲染 3 s + `about_credits.html` 3 s + keytool 1 s + siso 7 s |
| `touch` 一个 .java（内容不变） | 9.9 s | siso 按内容哈希，bytecode 相同不连锁 |
| 改一个 .java（bytecode 变化） | 113 s | javac 4 s + dex/分 dex ≈ 90 s + 打包 |
| 改一个 .cc | 25 s | 编译 0.8 s + 重链 `libchrome.so` 18 s + 打包 1 s |
| 只改签名参数 | 32 s | 仅 apksigner/zip 对齐 |
| `gn gen` | 5 s | args 不变时几乎免费 |
| 历史真实构建（`out/*/siso_metrics*.json`） | 110–125 s | 与上表一致 |
| 全新 out | 2–4 h（12 核） | 未在本机完整计时；官方 arm64 单体经验值 |

## 3. 怎么自己量

```bash
# 墙钟
time autoninja -C out/lumo-rel chrome_public_apk

# siso 侧的分段耗时（duration_nanos）
python3 - <<'PY'
import glob, json
for f in sorted(glob.glob('/home/bob/chromium/src/out/lumo-rel/siso_metrics*.json')):
    d = json.loads([l for l in open(f) if l.strip()][-1])
    print(f, round(d.get('duration_nanos', 0)/1e9, 1), 's')
PY

# 哪条规则在被反复重建（找“莫名其妙的重编”）
tail -20 out/lumo-rel/.ninja_log
```

## 4. 已知的“每次都会重建”项

| 目标 | 原因 | 影响 |
|---|---|---|
| `gen/components/resources/about_credits.html` | 上游生成步骤每次判定为脏（非确定性输出） | ~3 s，无害 |
| 签名/打包 | 若 keystore 或 APK 输入变化才触发 | 32 s，只在参数变化时 |

`brand.sh` / `render-icons.py` 已改为**内容比对后再写**，不再因为“重跑了一次脚本”而让资源变脏。

## 5. 缓存（跨机器/跨重装）

```bash
scripts/chromium/cache.sh manifest                 # 先记内核身份
scripts/chromium/cache.sh snapshot                 # out/lumo-rel → artifacts/cache/out-*.tar.zst
scripts/chromium/cache.sh restore <archive> [dir]  # 恢复后第一次构建仍是增量的
```

失效条件（任一不满足就别恢复，直接重编）：

- `chrome/VERSION` 不同（Chromium 升级）
- clang / depot_tools 的 CIPD 版本不同（manifest 里有记录）
- 源码绝对路径不同（默认 `$HOME/chromium/src`）
- `args.gn` 的编译类参数不同（签名参数无关）
