# ADR 0003：稳定 dev 签名密钥入库，并公开声明仅用于 debug

- 状态：已采纳
- 日期：2026-11-17
- 相关：`keys/README.md`、`scripts/chromium/keys.sh`、`SECURITY.md`

## 背景

Chromium 默认用上游公开的 `build/android/chromium-debug.keystore`
（别名 `chromiumdebugkey`、口令 `chromium`）签名。后果：

- 每次构建都是同一把“全世界公开”的 key → 至少可以覆盖升级；
- 但设备上如果装过别的 key 签的同包名包（例如上游 debug 包、别人自构建的包），
  覆盖安装会 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，只能卸载 → 丢 profile、扩展状态、用户脚本开关；
- 多人/多机验证时无法确认“这个 APK 是不是同一份构建”；证书指纹无法作为验收记录的一部分。

## 决策

生成并提交一把**本项目专用**的 dev key：`keys/lumo-dev.jks`（RSA 2048，PKCS12，别名 `lumo`），
口令明文写在 `keys/README.md`，并在文档里明确三件事：

1. 它只用于 `dev.lumo.browser` 的 **debug/自测**构建；
2. 它是**公开**的，不提供任何来源可信性（与上游 debug key 同等级）；
3. 正式分发必须另建 release key（不入库，走 CI secret），且需要换包名/卸载重装。

构建接线：`keys.sh` 复制到 `$CHROMIUM_SRC/lumo-signing/`（GN 只能解析 `//` 路径），
`args.sh` 输出 `android_keystore_*`，apksigner 使用它（只影响签名步骤，不触发重编译）。

## 后果

- ✅ `pm install -r` 可覆盖升级，profile/扩展/用户脚本开关保留，真机迭代不用卸载。
- ✅ 证书指纹（`SHA-256 14:43:04:4D:CF:...:80:52:5E`）可作为构建身份的一部分写进验收记录。
- ⚠️ 仓库多了一个二进制私钥（2.7 KB）；它是公开的，泄露无需响应。
- ⚠️ 必须防止它被用于正式分发：`SECURITY.md` 给出拒绝标准，发布流程另建 release key。
- ⚠️ 换 key = 所有设备必须卸载重装（签名不兼容），因此除非泄露不要换。

## 替代方案

- **继续用上游 debug key**：放弃。任何人可伪造同包名包，且与上游包互斥安装。
- **每台机器生成随机 key**：放弃。跨机器/CI 无法覆盖升级，证据不可复现。
- **把 key 放在仓库外/CI secret**：本地构建会退回“每次 key 不同”，破坏个人迭代；
  正式分发仍会走 secret（release key），两者分开即可。

## 复核条件

引入商店分发或自动更新通道时，必须同时引入 release key 与新的签名策略（本 ADR 只覆盖 dev）。
