# 上游同步 Runbook

> 目标：`git merge upstream/main` 之后，用两条命令回到 Nuo 状态，并且知道哪些地方需要人看。

---

## 1. 日常流程

```bash
git fetch upstream
git merge upstream/main          # 正常解冲突，别手动搬品牌改动

scripts/brand/apply.sh           # 重放所有规则
scripts/brand/verify.sh          # 守卫
make test                        # 受影响包
```

如果 `apply.sh` 打印了 `applied 0 change(s)` 而 `verify.sh` 仍然报错，说明上游新增了品牌面但规则没有覆盖 —— 补规则，不要手改。

---

## 2. 三种失败形态

### 2.1 规则锚点失效（退出码 3）

```
brand: build.embedded-cli-helpers: anchor not found in scripts/build/build_arm64.sh (upstream changed it?).
--- expected anchor ---
# Copy to Helpers folder as 'osaurus'
...
```

上游重写了这段脚本，规则没法安全套用。处理顺序：

1. 看上游新代码，判断它是否已经等价于我们的改动（例如它自己就把 helper 改名了）。
2. 是 → 删规则或改 `find`/`replace` 为新原文。
3. 否 → 把我们的补丁手工落到新代码上，然后把 `find` 更新成新原文。
4. 重跑 `apply.sh` 确认幂等（第二次 0 变更）。

**不要**为了绕过冲突而把规则改成宽松正则 —— 那会在别的分支上误伤。

### 2.2 棘轮失败（退出码 1）

```
brand-guard: FAIL (1 issue(s))
  - Makefile: 50 legacy occurrence(s) > baseline 49
```

含义：`paths.strict` 里的文件多了品牌词。两种可能：

- 上游新写的文案/路径 → 补规则，让 `apply.sh` 吃掉它。
- 你自己的改动引入了品牌词 → 修掉。

修完 `apply.sh` 仍失败，说明规则没覆盖，补规则。

### 2.3 契约消失（退出码 1）

```
brand-guard: FAIL (1 issue(s))
  - contract 'osaurus_plugin_entry_v2' disappeared (0 < 30)
```

这是**最严重**的一类：上游可能改了插件 ABI、模块名、或把某个冻结标识符搬走了。不要改 `brand.json` 把闸门调低来让它变绿。先搞清楚上游为什么动它，再决定是跟（升级我们这边的引用）还是拦（保留兼容层）。

---

## 3. 阶段推进时

每完成一个阶段：

```bash
scripts/brand/snapshot.sh --write     # 重测棘轮基线（数字应该变小）
```

再把该阶段的规则 `enforced` 翻成 `true`：

```jsonc
{ "id": "pbx.bundle-id", "enforced": true, ... }
```

从此这些规则任何回退都会让 CI 红。翻的时候一次只翻一个阶段，别一次性全开 —— 否则第一次红你不知道是哪条。

---

## 4. 新增一条规则

```jsonc
{
  "id": "area.what",            // 唯一、可 grep
  "op": "replace",              // replace | pbx-setting | insert-after | block
  "files": ["相对路径或 glob"],
  "pattern": "正则",
  "replace": "替换文本，可用 {display} {slug} {bundle_id} 等占位符",
  "enforced": false,
  "why": "一句话说明为什么需要它"
}
```

自检清单：

1. `apply.sh --dry-run` 的命中数符合预期（不是 0，也不是离谱的大）。
2. `apply.sh` 两次，第二次必须是 0。
3. 目标文件 `git diff` 只动了你想动的地方。
4. 命中范围不包含任何冻结字面量（引擎会保护，但规则设计上也不该依赖它兜底）。
5. 新名字优先用占位符，不要手写 `nuo` / `Nuo` —— 真源只有 `brand.json`。

---

## 5. 不要做的事

| 反模式 | 为什么 |
|---|---|
| 全仓 `sed -i 's/Osaurus/Nuo/g'` | 会把 `OsaurusCore`、`ai.osaurus.*`、`osaurus_plugin_entry_v2` 一起打碎，且下次 merge 全量冲突 |
| 手动改完不补规则 | 下次 merge 全部丢失，且 `verify.sh` 会误报 |
| 为了让 CI 绿而调低 `contracts.min` | 等于把安全闸门拆了；契约消失要先解释原因 |
| 把 `docs/evidence/**` 里的历史记录改名 | 改写已归档的证明等于伪造证据 |
| 把 `LICENSE` 里的版权行算进"品牌替换" | 版权声明不是品牌面，等书面指示 |
