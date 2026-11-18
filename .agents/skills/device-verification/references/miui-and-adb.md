# MIUI / SELinux / adb 的坑

设备：Redmi K20 Pro（raphael），Android 11 / MIUI，Magisk root。`common.sh` 里的
`D()`/`DR()` 分别代表「adb shell」与「adb shell su -c」。

## 1. 安装

| 现象 | 原因 | 处理 |
|---|---|---|
| `adb install` → `Failure [INSTALL_FAILED_...]` 或 “canceled by user” | MIUI 安装器拦截 sideload | `scripts/device/install.sh`：push 到 `/data/local/tmp` 后 `su -c "pm install -r -g -d -i com.miui.packageinstaller ..."` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 设备上是另一把 key 签的包（例如上游 debug key） | 卸载一次：`adb uninstall dev.lumo.browser`（会清 profile），之后 dev key 的包可 `-r` 覆盖 |
| 安装成功但图标/名称不对 | APK 不是品牌化产物 | 确认 `scripts/chromium/brand.sh` 跑过，`aapt2 dump badging` 看 `application-label` |
| `pm install` 报 `INSTALL_FAILED_INSUFFICIENT_STORAGE` | 344 MB APK + 解压空间 | 清理 `/data/local/tmp/*.apk`、卸载旧包 |

安装后确认：

```bash
adb shell pm path dev.lumo.browser
adb shell dumpsys package dev.lumo.browser | grep -E "versionName|signatures" | head -3
```

## 2. 扩展载荷位置

| 位置 | 可写 | 浏览器可读 | 结论 |
|---|---|---|---|
| `/data/data/<pkg>/files/...` | root 可写 | Magisk domain 下 SELinux 拒绝 | ❌ |
| `/data/local/tmp/...` | shell 可写 | 可读，但属于共享临时区 | 仅探针调试 |
| `/sdcard/Android/data/<pkg>/files/ext/...` | shell 可写 | ✅（app 外部目录） | ✅ 标准做法 |

```bash
EXT_ROOT=/sdcard/Android/data/dev.lumo.browser/files/ext
adb shell ls "$EXT_ROOT"
```

## 3. 命令行 flag 通道

- 文件：`/data/local/tmp/chrome-command-line`（shell 可写，644）。
- 生效条件：`adb shell am set-debug-app --persistent dev.lumo.browser`。
- 写入方式：`flags.sh` 用 `printf '%s\n' '$CMDLINE'`，**不要**用 `su -c` 里嵌引号
  （会被吞掉/拼接成 `n`）。
- 验证：

```bash
scripts/chromium/flags.sh show
adb logcat -d | grep -i cr_CommandLine | tail -3
```

## 4. SELinux / root

```bash
adb shell getenforce                       # 应为 Enforcing
adb shell su -c 'getenforce'               # 同上
adb shell su -c 'ls -Z /sdcard/Android/data/dev.lumo.browser/files' | head -3
```

- `setenforce 0` 只能用于**判断是否 SELinux 导致**，不能写进方案或脚本长期开关。
- MIUI 的 `su -c` 对多参数/引号敏感：复杂命令用 `adb shell "su -c 'cmd'"` 的单层写法，
  或像 `flags.sh` 一样避免嵌套。

## 5. uiautomator / 截图

```bash
adb shell su -c 'uiautomator dump /sdcard/ui.xml'  # MIUI 上需要 root
adb pull /sdcard/ui.xml
adb exec-out screencap -p > shot.png
```

- `ui_dump()` 已经封装了这两步，失败不致命（返回旧的 xml）。
- 文本判定用 `text=` / `content-desc=`，不要依赖坐标（不同分辨率会漂）。

## 6. 扩展装载失败排查

```bash
adb logcat -d | grep -iE "Failed to load extension|extension.*error|cr_Extensions" | tail -20
```

| 现象 | 可能原因 |
|---|---|
| 扩展不在列表 | 目录里没有 `manifest.json`；或路径含空格/中文；或 `--load-extension` 被后一个 flag 覆盖 |
| 显示「无效」 | SW 未唤醒（正常，等 5–10 s 或点开扩展页）；或 manifest 校验失败（看 logcat） |
| 装上了但 API 全失败 | 扩展缺权限声明；或 `userScripts` 开关未在扩展详情页打开（补丁 0008 之后默认允许，但仍需声明权限） |
| 中文/emoji 路径 | 不要用；统一 ASCII 目录名 |

## 7. 设备不在线

```bash
adb devices                 # 没有设备时 common.sh 的 DEVICE_SERIAL 为空，need_device 会直接报错
adb kill-server && adb start-server
```

`doctor.sh` 会把“无设备”标记为 WARN（不是 FAIL），构建相关检查照常进行。
