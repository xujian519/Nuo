# Nuo UI · 设计文档快照

这里的两份文档是 UI 交付包（`~/Pictures/Nuo-UI/`）的**逐字快照**，没有改一个字：

| 文件 | 用途 |
|---|---|
| `DESIGN_SPEC.md` | 主文档：12 屏逐屏规范 + 令牌 + 实施计划（§9.1–9.4）+ 已知的坑 |
| `DECISIONS.md` | 6 条 ADR：为什么这么定、代价是什么、否掉了什么 |

阶段一落地了什么、怎么回滚，见 [`../NUO_UI_PHASE1.md`](../NUO_UI_PHASE1.md)。

## 快照的四点须知

1. **`DESIGN_SPEC.md` §9.1 里写着「已落地（未提交）」——那是快照当时（2026-11-04）的状态。**
   实际已在 `28aeedc4e` 提交。快照保持原样不改，是为了让它和交付包对得上；
   状态以 git 历史与 `NUO_UI_PHASE1.md` 为准。
2. **`research/ui-inventory.md` 没有随快照进来。** 它是设计文档引用的只读考古报告
   （495 行，每条带文件:行号），目前仍在交付包里。要引用它的具体行号时，去
   `~/Pictures/Nuo-UI/research/ui-inventory.md` 查。
3. **交付包整包（原型 HTML、截图、可编译令牌包）只存在于 `~/Pictures/Nuo-UI/`。**
   本仓只收了设计规范与决策，因为它们是后续阶段的依据；原型的权威副本不在仓内。
4. **`DESIGN_SPEC.md:482` 提到的 `PHASE1_LANDED.md` 不在仓内。** 它是交付包
   （`~/Pictures/Nuo-UI/`）里的副本；仓内读同一份内容的对应文档是
   [`../NUO_UI_PHASE1.md`](../NUO_UI_PHASE1.md)。快照逐字保留，不改链接。
