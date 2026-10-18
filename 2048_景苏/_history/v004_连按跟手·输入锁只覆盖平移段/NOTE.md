# v004 · 连按跟手·输入锁只覆盖平移段

- **工程**：`2048_景苏`
- **时间**：2026-10-18 12:34
- **存档名**：2048 · v004 · 连按跟手·输入锁只覆盖平移段
- **备注**：输入缓冲+连击加速+解锁回调独立 tag+看门狗；修复开场黑幕清掉解锁回调导致输入永久锁死

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
node _tools/version_restore.mjs --game 2048_景苏 --version v004
```

> 仅供回看/对照。直接手工复制这目录里的文件到工程根即可恢复该版本。
