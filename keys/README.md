# Lumo 开发签名密钥（**故意**提交到 git）

`lumo-dev.jks` 是 Lumo Browser 自构建 APK 的**开发/测试签名密钥**。它**不是**发布密钥，
用它签出的包**不能**上架、**不能**用于生产分发。

## 为什么要把私钥放进仓库

| 问题 | 没有固定密钥 | 有固定密钥（本文件） |
|---|---|---|
| 每次重新构建后覆盖安装 | `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，必须先卸载（丢数据、丢扩展、丢登录态） | `adb install -r` 直接覆盖升级 |
| 扩展 ID 稳定性 | 扩展 ID 依赖扩展自己的 key，与 APK 无关；但 `--load-extension` 路径和 profile 会因卸载而清空 | profile 保留，`chrome://extensions` 状态、权限、用户脚本开关都在 |
| 多人/多机验证 | 每人一份随机 key，证据不可复现 | 同一份 key，`apksigner` 证书指纹可写进验收记录 |
| CI 无设备验证 | 无法预签 | 直接 `./gradlew` 式的无密钥构建 |

上游 Chromium 的默认密钥 `build/android/chromium-debug.keystore`（别名 `chromiumdebugkey`，
口令 `chromium`）是**全世界公开**的，任何人可以用它签一个同包名的包；它只用于“能装上”，
不提供任何身份保证。本仓库的 dev key 同样是公开的（就放在这里），**安全等级相同：只防手滑，不防攻击**。

## 事实清单（明面上写清楚）

- 路径：`keys/lumo-dev.jks`（PKCS#12，RSA 2048，有效期 10,000 天 ≈ 2054 年）
- 别名：`lumo`　口令（store 与 key 相同）：`lumodebug`
- 证书 SHA-256：`14:43:04:4D:CF:72:11:1D:14:6C:28:A4:ED:27:E8:C7:D8:4A:63:32:76:4B:DF:13:87:17:AE:A5:18:80:52:5E`
- 用途：**仅** `dev.lumo.browser` 的开发/自测/真机验收构建
- 构建时由 `scripts/chromium/keys.sh` 复制到 `$CHROMIUM_SRC/lumo-signing/`（GN 只能解析 `//` 相对路径），
  再通过 `args.sh` 的 `android_keystore_*` 传给 apksigner

## 不要做的事

1. **不要**用它签正式发布包（Play/应用商店会拒绝，且泄露后无法吊销）。
2. **不要**把它当成“代码签名”安全机制：它是公开的，任何人都能伪造同包名的 APK。
   真正的信任边界在：包名 + 分发渠道 + 你安装时校验的 APK 哈希（见 `artifacts/apk/meta.env`）。
3. **不要**在 `docs`/发布说明里承诺“签名校验通过 = 官方包”。要校验官方包，请用发布密钥
   （后续如果做商店分发，再引入 `keys/lumo-release.jks`，那份**绝不入库**，走 CI secret）。

## 操作

```bash
scripts/chromium/keys.sh status    # 打印别名/有效期/指纹，并检查仓库内文件完整性
scripts/chromium/keys.sh install   # 复制到 $CHROMIUM_SRC/lumo-signing/（构建会自动做）
```

更换密钥 = **所有设备必须卸载重装**（签名不兼容），所以除非泄露否则不要换。
