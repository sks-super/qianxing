# v001 · 棋盘·移动·合并·结算首版

- **工程**：`2048_景苏`
- **时间**：2026-10-17 01:18
- **存档名**：2048 · v001 · 棋盘·移动·合并·结算首版
- **备注**：首次把 14 个模块全部写完：4x4 棋盘 + 逐帧平移/回弹/合并粒子 + 结算拍立得展示 + 最高分持久化

## 本版快照包含的文件

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
node _tools/version_restore.mjs --game 2048_景苏 --version v001
```

> 仅供回看/对照。直接手工复制这目录里的文件到工程根即可恢复该版本。
