# Launcher icon artwork

Android 启动图标的唯一来源。**不要**手工改 `~/chromium/src` 里的 PNG，也不要
直接把一张 1024 图缩放了事 —— 改这里的 SVG，然后跑 `scripts/chromium/brand.sh`。

| 文件 | 作用 |
|---|---|
| `app-icon-background.svg` | adaptive 背景层：夜空渐变 + 两道海浪（平涂） |
| `app-icon-foreground.svg` | adaptive 前景层：右上角的月亮 + 柔和月晕 |
| `themed-app-icon.xml` | Android 13+ 单色主题图标（VectorDrawable） |

设计：**月光 + 海浪**，只保留三个元素——月亮、月晕、两道浪。
没有窗口/浏览器 chrome/3D 透视；颜色全部是纯色或单层渐变，
48 px 下仍然是一眼能读出的「月夜海面」。

月亮中心 (71,36)、r=10：到图标中心 (54,54) 的距离 24.8，两半径之和 34.8 < 36，
所以圆形蒙版（Pixel 系 launcher）不会切到月亮。

渲染：`scripts/chromium/render-icons.py`（librsvg → PNG，ImageMagick Lanczos 缩放）。

## 为什么画在 108×108 网格上

Android 的 `AdaptiveIconDrawable` 把每一层按 **1.5 倍**视口绘制
（`getExtraInsetFraction() == 0.25`，每边外扩 25%），然后只保留视口内的部分。
因此 108dp 的层里，**只有正中 72dp 可见**：

```
+-------------------------- 108 --------------------------+
|  18        72 visible (safe zone)            18        |
|  +--------------------------------------------+        |
|  |                                            |        |
|  +--------------------------------------------+        |
+---------------------------------------------------------+
```

两个 SVG 都用 108 坐标；所有前景内容必须落在 `18..90`。
`render-icons.py` 会检查这一点（以及 legacy 图标圆角透明、背景层满幅不透明），
不满足直接失败，避免「图标被裁一半」这种只能靠真机才能发现的问题。

## 产物（`res_chromium_base/`）

| 文件 | mdpi | hdpi | xhdpi | xxhdpi | xxxhdpi |
|---|---|---|---|---|---|
| `mipmap-*/app_icon.png`（API<26，烘焙超椭圆圆角） | 48 | 72 | 96 | 144 | 192 |
| `mipmap-*/layered_app_icon.png`（前景层，=48dp×1.5） | 72 | 108 | 144 | 216 | 288 |
| `mipmap-*/layered_app_icon_background.png`（背景层，=108dp） | 108 | 162 | 216 | 324 | 432 |
| `drawable/themed_app_icon.xml`（Android 13+ 单色） | — | — | — | — | — |

legacy 图标 = 场景正中 72 单位 + `n=4.5` 超椭圆裁剪，因此和老系统上看到的形状、
和新系统上 launcher 蒙版裁出来的画面一致。

## `brand.sh` 还会改的两处 XML

上游 Chromium 的两个自适应图标配方不一致，直接用会把 Lumo 的渐变背景丢掉：

| 文件 | 上游 | Lumo |
|---|---|---|
| `res_base/drawable/ic_launcher.xml` | 白底 + 满幅 `layered_app_icon.png` | 夜景背景层 + 透明前景层 |
| `res_base/drawable/ic_launcher_round.xml` | 背景层 + **透明**前景 shape | 夜景背景层 + 透明前景层 |

`brand.sh` 幂等地把两个文件统一成「`layered_app_icon_background` + `layered_app_icon`
+ `themed_app_icon`」并校验，否则方图标会是白底（白色 logo 看不清）、圆图标只有底色。

## 本地预览

```bash
scripts/chromium/render-icons.py --out /tmp/icons --preview /tmp/icons/preview
```

`--preview` 会额外输出 launcher 形状（超椭圆 / 圆形）的模拟结果，用来判断蒙版
安全区，不需要刷机。
