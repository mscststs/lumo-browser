# GPU / GL 排查记录（2026-11-15）

自构建 APK 首跑时，浏览器进程在启动约 0.3s 后崩溃：

```
[FATAL:content/browser/gpu/gpu_data_manager_impl_private.cc:387] GPU process isn't usable. Goodbye.
```

## 1. 现象与实测矩阵

| 启动参数 | 结果 | 关键日志 |
|---|---|---|
| （默认） | GPU 进程初始化失败 → 浏览器 FATAL | ANGLE GL 后端：`eglCreateContext ES 3.0 failed ... max supported (2.0)`；`CollectGraphicsInfo failed` |
| `--use-angle=vulkan` | 同上 | ANGLE Vulkan 起得来（Adreno 640 / Vulkan 1.1.128），但随后仍报 `max supported (2.0)` |
| `--use-gl=egl` | 参数被忽略（允许的实现只有 ANGLE） | `allowed implementations: [(gl=egl-angle,angle=opengles),(gl=egl-angle,angle=vulkan)]` |
| `--use-cmd-decoder=validating` | 走原生 EGL（日志出现 AdrenoGLES），但 Chrome 仍尝试 Vulkan | `EGL_EXT_device_query not supported` → `Failed to get vkGetInstanceProcAddr pointer from ANGLE` |
| `--use-cmd-decoder=validating --disable-features=Vulkan` | GPU 进程**静默死亡**（无任何错误日志，疑似 SIGILL） | 见 §2 |
| `--in-process-gpu` / `--disable-gpu-sandbox` | 同上，无更多信息 | — |

对照：同设备上 Titanium v157 的 APK 正常启动，日志直接出现 `AdrenoGLES-0: Driver Path /vendor/lib64/egl/libGLESv2_adreno.so`，**没有 ANGLE 日志**（即它是原生 EGL 路径）。

## 2. 根因判断

1. **非 official 构建自带 UBSan “hardening” trap**
   （`-fsanitize=array-bounds/return/unreachable -fsanitize-trap=...`，见
   `build/config/compiler/BUILD.gn` 的 `ubsan_hardening(...)`），以及
   `DCHECK_ALWAYS_ON=1`、`enable_expensive_dchecks=true`。
   这类 trap 命中时进程直接 SIGILL，**不打印任何日志**——与 GPU 进程“静默死亡”完全吻合。
2. Chromium 160 在 Android 上只允许 ANGLE 实现（`ui/gl/init/gl_factory_android.cc`），
   而这台 2021 年的 Adreno 驱动在 ANGLE GL/Vulkan 后端下把 ES 版本压到 2.0，
   GPU 信息收集（要求 ES3 且禁止回退）因此失败。
3. Android 分支在 `InitializeGpuModes()` 中**没有软件合成回退**，GPU 不可用即 FATAL。

## 3. 决策

| 决策 | 理由 |
|---|---|
| 产品构建必须 `is_official_build = true` | 去掉 UBSan trap / DCHECK_ALWAYS_ON；APK 也会从 511MB 降到 ~200MB |
| `chrome_pgo_phase = 0` | 官方 tarball 不含 PGO profile（DEPS 里是 GCS 依赖） |
| `use_thin_lto = false` | 先求可运行与构建时间；后续出正式包再评估 |
| 保留 `patches/0005`（尊重 `--disable-features=Vulkan`） | 避免 WebGPU interop 强行拉起 Vulkan；在缺 `EGL_EXT_device_query` 的驱动上是明确 bug |
| 若 official 构建下 GPU 仍失败 | 退路：`--use-cmd-decoder=validating --disable-features=Vulkan`（原生 EGL 路径），必要时再补软件合成回退 |

## 4. 复现命令

```bash
FAST=0 OUT_DIR=out/lumo-rel scripts/chromium/build.sh a
scripts/device/install.sh
# 默认参数；若 GPU 仍失败再试：
#   --use-cmd-decoder=validating --disable-features=Vulkan
```

## 5. 待验证

- [ ] official 构建下默认参数能否正常起浏览器（`GPU process isn't usable` 消失）
- [ ] `chrome://gpu` 页面（可在能启动后查看）确认 GL_RENDERER
- [ ] 若仍失败：检查 ANGLE ES2 cap 是否与 `target_sdk_version=37` 有关（试 `target_sdk_version=30`）

## 6. 最终结论（2026-11-16 更新）

- `is_official_build=true` 构建仍会因 ANGLE/Adreno 的 ES3 上下文创建失败而崩（`EGL_BAD_ATTRIBUTE`）。
- 采用 `patches/0006`（GPU 信息收集允许 ES2 回退）后，浏览器**正常启动**：
  GPU 进程以 ES2 运行，Chromium 160 在我们的设备上稳定可用，扩展全部加载。
- 因此 v0.1 的 GPU 策略：**官方构建 + ES2 回退补丁**；后续再针对 ES3/ANGLE 做优化（不影响扩展能力）。

## 7. 已解决的手机形态问题

| 问题 | 根因 | 补丁 |
|---|---|---|
| 点「打开扩展程序菜单」崩溃 | 上游把扩展工具栏硬编码为 tablet（`(ToolbarTablet) mToolbarLayout`） | `0002`：`toolbar_phone.xml` 加容器 + `ToolbarPhone` 接收 coordinator + ToolbarManager 去掉强转 |
| 手机侧栏永远不显示 | `canShowSideUi` 要求 `availableWidth >= minWebContents(412dp)`，手机只有 392dp | `0007`：窄窗口改为全宽 overlay 面板 |
| 扩展菜单/管理页 | 上游已有 | 无需补丁；真机已验证底部弹层与 chrome://extensions 可用 |
