# Lumo Browser

Android Chromium 内核 + 完整 MV3 扩展支持的移动浏览器。

- 策略与起点分析：[docs/00-strategy-and-start.md](docs/00-strategy-and-start.md)
- 工程约定：[AGENTS.md](AGENTS.md)
- 补丁说明：[patches/README.md](patches/README.md)

```bash
scripts/chromium/fetch.sh      # 拉取 Chromium
scripts/chromium/build.sh b    # 构建（b = 手机形态 + 扩展核心）
scripts/device/install.sh      # 真机安装
scripts/device/verify.sh       # 验收
```
