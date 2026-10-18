# v003 · 按钮自绘·文本兜高

- **工程**：`2048_景苏`
- **时间**：2026-10-18 11:42
- **存档名**：2048 · v003 · 按钮自绘·文本兜高
- **备注**：修真机三处空白：①按钮改用「图片底+文本+光标检测区域」自绘，不再依赖 buttonPrefabId（没配模板时旧写法会把按钮和文字一起跳过）；②createText 增加「字号×行高系数 1.45」兜高，修掉标题(62号/76高)、分数数值(34号/46高)、结算大字在真机上「一个字都不画」；③按钮底图补 raise，修掉它被结算面板底板盖住。另给光标检测区域显式置 transparent，避免命中区变成色块压住按钮。

## 本版快照包含的文件

- `README.md`
- `anim.lua`
- `audio.lua`
- `board.lua`
- `config.lua`
- `fadeScreen.lua`
- `fx.lua`
- `game.lua`
- `hud.lua`
- `input.lua`
- `menu.lua`
- `signal.lua`
- `state.lua`
- `utils.lua`
- `view.lua`
- `编辑器.html`

## 怎么用

```bash
# 把这个版本的全部源码覆盖回工程（会先备份当前版本）
node _tools/version_restore.mjs --game 2048_景苏 --version v003
```

> 仅供回看/对照。直接手工复制这目录里的文件到工程根即可恢复该版本。
