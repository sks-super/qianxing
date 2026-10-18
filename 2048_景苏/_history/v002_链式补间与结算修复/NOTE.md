# v002 · 链式补间与结算修复

- **工程**：`2048_景苏`
- **时间**：2026-10-17 01:44
- **存档名**：2048 · v002 · 链式补间与结算修复
- **备注**：修掉三处 bug：①anim.update 覆盖 items 导致链式补间全丢（症状：动画只有第一段能动、方块停在缩放 0）；②粒子/飘字坐标系错位（棋盘局部 vs 场景原点）；③结算遮罩压在相框与面板之上（sink/raise 只改调用那一刻的顺序）。另确认容器 SetLocalScale 在模拟器生效——旧判定为误判，根因是离线渲染器没累加父级缩放。含文档补充：README 新增「引擎行为实测」「动画系统三个坑」。

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
node _tools/version_restore.mjs --game 2048_景苏 --version v002
```

> 仅供回看/对照。直接手工复制这目录里的文件到工程根即可恢复该版本。
