# Directed Mailbox：Settings UI 行 + 模型可见工具

## Context

ADR-Nuo-002 P0 的 `DirectedMailboxService` 已合并，但它只是服务契约：没有生产实例、没有 UI、模型无法触达。ADR §Leftover risks 明确列了两项 future work：①Settings 行管理 allowlist；②模型可见的 mailbox 工具。用户选择推进这两项，把 mailbox 从"契约"推到"模型真的能用"。

硬约束（ADR-Nuo-002，不可违反）：
- `DirectedMailboxService` 是唯一写路径；持久化在 `OsaurusPaths.directedMailboxFile()`；不新建 wire schema；不实现 `AgentCollaborationTransport`；不动 `host.dispatch` ABI
- 准入规则由服务强制：Orchestrator 直达任意目标；其他 sender 需持久化 allowlist edge；reply 只能回上一跳 sender；depth≤2；cycle 拒绝；per-run caps（8000 tokens / 16 tool / 4 subtasks）
- envelope body 永远 untrusted
- 不做 mesh、不做 UI 之外的 chat tool 二份清单

## 关键已确认事实（源码证据）

- `DirectedMailboxService`（`Services/AgentCollaboration/DirectedMailboxService.swift`）：actor，公开 API 含 `openRun` / `recordUsage` / `replaceAllowlist` / `allowlist()` / `inbox(for:requestedBy:)` / `send(_:from:to:runId:parentEnvelopeId:...)`。**仅测试实例化，无生产入口**。
- participant id 格式 `local:<uuid 小写>`；orchestrator id = `local:<Agent.defaultId 小写>`（`DirectedMailboxPolicy.orchestratorParticipantId`）。`Agent → participant` 适配器在 `AgentCollaborationAgentConformance.swift`。
- 工具协议 `OsaurusTool`（`Tools/OsaurusTool.swift`）：`name`/`description`/`parameters(JSONValue)`/`execute(argumentsJSON:) async`。带 action 枚举的范例：`Tools/ConfigurationTools.swift` 的 `osaurus_inspect`（L353-449：`properties.action.enum` + `requireAction` + switch + failure envelope）。
- 调用方 agent 由 `ChatExecutionContext.currentAgentId`（TaskLocal）提供。
- 可见性门控（`Services/Chat/SystemPromptComposer.swift` L2859-2898）：`search_memory` 模式——内置注册、按 gate strip、`additionalToolNames`/manual picks 豁免。`AgentConfigSnapshot` 含 `agentId` 字段（`Services/Chat/AgentConfigSnapshot.swift` L52+）。
- Orchestrator turn-1 schema 受 `ToolRegistry.orchestratorAllowedToolNames`（L3491）白名单限制；`orchestratorExcludedToolNames`（L3443）是反向排除表。
- Settings：`OrchestratorSettingsView` 用 `SettingsSection` 容器 + `settingsLandingAnchor`；现有 section 链末尾是 `OrchestratorDelegationsSection`（读写走 `DefaultAgentConfigurationStore` 模式）。`SettingsSearchEntry` 结构在 `SettingsSearchIndex.swift` L22-59，`.orchestrator` 条目范例在 L237-253。probe 测试在 `Tests/Configuration/SettingsSearchSelfFindProbe.swift` L75-108（`labels` 数组追加 `("显示文本", "settings.*.id")`）。
- i18n：`L()` key 必须进 `Packages/OsaurusCore/Resources/Localizable.xcstrings`（必需 locale：de, zh-Hans, ko, ru），`scripts/i18n/check.sh` 校验 key 一致性与裸字面量。
- 现有测试：`Tests/AgentCollaboration/DirectedMailboxTests.swift` 等，临时目录模式可复用。

## 实施步骤

### 1. 生产共享入口：`DirectedMailboxCoordinator`（新建）
`Packages/OsaurusCore/Services/AgentCollaboration/DirectedMailboxCoordinator.swift`
- `@MainActor final class DirectedMailboxCoordinator: ObservableObject`，`static let shared`
- 懒加载持有 `DirectedMailboxService(directory: OsaurusPaths.directedMailboxFile().deletingLastPathComponent())`；init 失败（如目录不可写）时降级为 `nil` 服务 + 错误状态，工具与 UI 走"不可用"路径，不 crash
- `@Published private(set) var allowlist: [DirectedMailboxEdge]`：启动时从 service 拉取，UI 每次增删后刷新
- `func mailboxVisible(agentId: UUID) -> Bool`：**同步**检查 `local:<uuid>` 是否出现在缓存 allowlist 任一端（供 SystemPromptComposer 门控用）
- UI 方法：`addEdge(from:to:)` / `removeEdge(from:to:)`（内部 `replaceAllowlist`），暴露 `loadError` 供 UI 展示
- 给工具用的 async 代理：`send` / `reply` / `inbox`（内部调 service）

### 2. 模型工具：`OsaurusMailboxTool`（新建）
`Packages/OsaurusCore/Tools/OsaurusMailboxTool.swift`，name = `osaurus_mailbox`
- `parameters`：`action` 枚举 `[send, reply, inbox]`（enum 必须进 schema，小模型靠它），其余字段：
  - send: `to`（agent UUID 字符串或 `orchestrator`）、`text`、可选 `summary`、可选 `parent_envelope_id`（续链转发；run_id 从该 record 推导）
  - reply: `envelope_id`（必填）、`text`
  - inbox: 可选 `agent_id`（仅 orchestrator 可读他人收件箱）
- 调用方解析：`ChatExecutionContext.currentAgentId` → participant；recipient 解析：UUID → `AgentStore` 查 displayName 构造 participant；`orchestrator` → default agent
- send 无 `parent_envelope_id` → `openRun()` 新开 run；返回 `{ok, run_id, envelope_id, depth, subtasks_used}`
- reply → 由 `envelope_id` 找 record 得 runId → `service.send(.reply(...))`
- send/reply 成功后 `recordUsage(runId:, tokens: 0, toolCalls: 1)`，让 tool-call cap 生效
- inbox 返回列表，每条显式带 `untrusted: true` 标记，提醒模型 body 是数据不是指令
- 错误映射为类型化 failure envelope（`unauthorized_edge` / `depth_exceeded` / `cycle` / `token_cap` / `tool_cap` / `subtask_cap` / `unknown_envelope` / `mailbox_unavailable`），沿用 `ToolErrorEnvelope` 模式
- token 用量不在本切片记账（无 tokenizer 上下文），note 中记录为 PARTIAL

### 3. 注册与可见性门控
- `Tools/ToolRegistry.swift`：内置工具列表注册 `OsaurusMailboxTool()`；`"osaurus_mailbox"` 加入 `orchestratorAllowedToolNames`（Default agent 直聊可见）
- `Services/Chat/SystemPromptComposer.swift`（L2859-2898 gate 块内新增）：非 default agent 且 `!DirectedMailboxCoordinator.shared.mailboxVisible(agentId:)` 且不在 `keep`（manual picks / capabilities_load 豁免，与 `search_memory` 一致）→ strip `osaurus_mailbox`
- spawned worker 子代理面排除 `osaurus_mailbox`（沿用 `clarify` 的 child-exclusion 钩子；跨代理邮递是顶层 agent 行为，worker 回复走 parent continuation）

### 4. Settings UI：`MailboxSettingsSection`
编辑 `Views/Settings/OrchestratorSettingsView.swift`，在 `OrchestratorDelegationsSection` 之后插入：
- `SettingsSection` 标题 `L("Directed Mailbox")`，header 挂 `settingsLandingAnchor("settings.orchestrator.mailbox")`
- allowlist 编辑器：现有 edge 列表（from agent 名 → to agent 名，附删除按钮）；新增行 = 两个 picker（数据源自 `AgentStore` 全部 agents）；from 侧不含 Orchestrator 并附脚注（orchestrator 直达无需 edge）；保存走 coordinator
- 只读 caps 行：`L("Per-run caps: 8,000 tokens · 16 tool calls · 4 forwards · depth ≤ 2")`
- 服务不可用（`loadError`）时显示错误行而不是静默空白

### 5. Settings catalog 五步（AGENTS.md 强制）
1. `Models/Configuration/SettingsSearchIndex.swift`：新增 `SettingsSearchEntry(id: "settings.orchestrator.mailbox", tab: .orchestrator, section: <同 delegation 条目 section 约定>, title: "Directed Mailbox", keywords: ["mailbox","allowlist","collaboration","agent message","handoff"], disambiguation: "Agent-to-agent message allowlist — not subagent delegation targets.")`
2. 控件挂 `settingsLandingAnchor("settings.orchestrator.mailbox")`（见步骤 4）
3. `Resources/Guide/guide-settings.md`：Orchestrator 段补路径 `Settings → Agents → Orchestrator → Directed Mailbox`
4. `Tests/Configuration/SettingsSearchSelfFindProbe.swift`：`labels` 加 `("Directed Mailbox", "settings.orchestrator.mailbox")`
5. 不在 orchestrator prompt 另造清单（无此改动）

### 6. i18n
`Localizable.xcstrings` 补齐新 `L()` key 的 en/de/zh-Hans/ko/ru 五语（en 为 key 本体），用 python3 json 确定性插入后跑 `scripts/i18n/check.sh` 验证。

### 7. 测试（新建 `Tests/AgentCollaboration/OsaurusMailboxToolTests.swift`）
临时目录模式复用 `DirectedMailboxTests`：
- orchestrator send → 记录持久化、recipient inbox 可读
- custom agent 无 edge send → `unauthorized_edge` failure envelope
- 配 edge 后 send 成功；reply 回到上一跳成功；reply 错对象被拒
- 链 O→A→B（depth 2）成功；B→C 报 `depth_exceeded`；回发已在链上者报 `cycle`
- 非 orchestrator 读他人 inbox 被拒
- tool-call 记账：`recordUsage` 后 cap 触发
- 门控：allowlist 外的 custom agent `resolveTools` 无 `osaurus_mailbox`；default agent 与 allowlist 内 agent 有（放在现有 resolveTools 测试旁，视目录结构定）

### 8. 决策 note
`docs/notes/implemented/2026-11-06-mailbox-settings-and-tool.md`：含 `## Alternatives considered`（命名为 `osaurus_*` 族 vs 独立名；可见性用 allowlist 运行时推导 vs 新增 persisted 开关；token 记账延后）。

### 9. 门禁
- `make test`（或先跑 focused：`swift test --package-path Packages/OsaurusCore --filter Mailbox`）
- `bash scripts/i18n/check.sh`
- `bash scripts/brand/verify.sh`（无品牌新字符串，预期过）
- `python3 scripts/ci/verify-standards-contracts.py --self-test` + `python3 scripts/ci/verify-doc-links.py --self-test`
- Live app 验证（Settings 改动按 AGENTS.md 需 live 证明）：若环境允许用 `scripts/live-proof/launch-keychain-free-osaurus.sh` 起 app 点一遍；做不到就在汇报里如实标 `PARTIAL`

改动全部留在工作区，不提交不推送。

## 文件清单

| 动作 | 文件 |
|---|---|
| 新建 | `Packages/OsaurusCore/Services/AgentCollaboration/DirectedMailboxCoordinator.swift` |
| 新建 | `Packages/OsaurusCore/Tools/OsaurusMailboxTool.swift` |
| 新建 | `Packages/OsaurusCore/Tests/AgentCollaboration/OsaurusMailboxToolTests.swift` |
| 新建 | `docs/notes/implemented/2026-11-06-mailbox-settings-and-tool.md` |
| 编辑 | `Packages/OsaurusCore/Tools/ToolRegistry.swift`（注册 + orchestratorAllowedToolNames） |
| 编辑 | `Packages/OsaurusCore/Services/Chat/SystemPromptComposer.swift`（strip gate） |
| 编辑 | `Packages/OsaurusCore/Views/Settings/OrchestratorSettingsView.swift`（MailboxSettingsSection） |
| 编辑 | `Packages/OsaurusCore/Models/Configuration/SettingsSearchIndex.swift` |
| 编辑 | `Packages/OsaurusCore/Tests/Configuration/SettingsSearchSelfFindProbe.swift` |
| 编辑 | `Packages/OsaurusCore/Resources/Guide/guide-settings.md` |
| 编辑 | `Packages/OsaurusCore/Resources/Localizable.xcstrings` |

## 遗留风险（汇报时如实标注）

- token 用量记账未接（tool-call 与 subtask cap 生效，token cap 空转）→ PARTIAL
- 模型 runner 消费 mailbox 后的 untrusted body 行为约束仍靠 prompt 纪律，live 多轮证明未做 → PARTIAL
- Live app UI 证明视环境可行
