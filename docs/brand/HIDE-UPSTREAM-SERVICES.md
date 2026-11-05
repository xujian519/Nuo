# 隐藏上游服务入口（Osaurus Router / Osaurus Cloud / osaurus.ai）

> 状态：**Router 主开关的 Phase 1 已由 [ADR-Nuo-001](../adr/ADR-Nuo-001-remove-router-credits-and-cloud-sync.md) 落地**（缺省关闭，隐藏 Credits / Workspaces / 余额芯片，onboarding 不再打开 Router，启动不再跑 WelcomeCredit / WorkspaceSync）。Relay 缺省、Identity 入口隐藏仍未实施，不在该 ADR 的 Phase 1。
> 用户决策原文："Osaurus Router / Osaurus Cloud / 域名 osaurus.ai 这些我不需要"
> → 进一步确认后的执行口径：**只隐藏入口，不删除连接代码**；验收判据 = **默认不连上游**。

## 1. 目标与非目标

### 目标

1. 新装用户开箱后，应用**默认不与 `*.osaurus.ai` 建立任何连接**。
2. 设置、菜单、onboarding、聊天界面里不再出现指向 Osaurus Router / Osaurus Cloud / osaurus.ai 的入口。
3. 改动集中、可回滚：不删服务代码，只改「默认开关 + 入口可见性」。

### 非目标

- **不删除** `Services/Router/`、`Services/Insights/`、`RelayTunnelManager` 等任何代码（保留与上游合并的能力）。
- **不改** 已建立连接的协议行为（签名、credits 计费、relay 协议全部原样）。
- **不动** 冻结标识符：`ai.osaurus.router.enabled` 等 UserDefaults key、`ai.osaurus.id` Keychain 服务、`OsaurusRouter` 类型名。
- Hugging Face（hf.co）、GitHub OAuth 等**非 osaurus.ai** 的外部依赖不在本工作项内。
- 已登录 Router / 已配对 iPhone 的旧用户：升级后**保持现有行为**（不强制断开），只对新装默认关闭。

## 2. 现状事实（实施前复核用，全部有源码证据）

| # | 入口 / 连接 | 现状 | 证据 |
|---|---|---|---|
| 1 | **Router 主开关** | `ai.osaurus.router.enabled` **缺省 = 关闭**（ADR-Nuo-001 Phase 1）。显式 `true` 仍打开 | `Services/Router/OsaurusRouterTypes.swift` |
| 2 | Router 设置 UI | Settings → Credits 页含 "Osaurus Router" toggle、credits 余额/充值、"router off" 说明卡 | `Views/Credits/CreditsView.swift:198-205` |
| 3 | Router usage 中心 | `RouterAccountUsageCenterView`（ChatView 等处引用） | `Views/Router/RouterAccountUsageCenterView.swift` |
| 4 | Cloud 模型浏览器 | `CloudModelBrowserDialog`，依赖 `isOsaurusRouterEnabled` | `Views/Model/CloudModelBrowserDialog.swift:57` |
| 5 | Onboarding 预热 | 身份创建步骤会 warm up Router 并 `connectOsaurusRouterIfPossible()` | `Views/Onboarding/OnboardingView.swift:139-159, 233` |
| 6 | **Relay（Reach From Anywhere）** | `mobileConnectReachFromAnywhere` 缺省 = true，配对 iPhone 后经 osaurus-relay 建 WebSocket 隧道 | `Services/MobileConnect/MobilePairingService.swift:596,607-610`；`Networking/RelayTunnelManager.swift:5` |
| 7 | Relay UI | Settings → Mobile 页 "Reach From Anywhere" toggle | `Views/Settings/OsaurusConnectView.swift:221-224` |
| 8 | **Osaurus ID（Identity）** | Settings → Identity 页（`OsaurusIDSection`）登录上游身份服务；Router 计费依赖它 | `Views/Identity/OsaurusIDSection.swift`；`CreditsView.swift:40` |
| 9 | Workspaces / Roster | `WorkspacesService`、`WorkspaceRosterStore` 订阅 Router enabled 状态 | `Services/Router/WorkspaceRosterStore.swift:125` |
| 10 | osaurus.ai URL 引用 | 73 个文件（含 `Localizable.xcstrings`、CLI、App 文案） | `rg -l "osaurus\.ai"` |

关键结论：Router 缺省已关，onboarding 不再预热或钉住 Router。Relay 仍缺省开启（配对后），不在 ADR-Nuo-001 Phase 1。

## 3. 方案

### 3.1 默认开关（满足判据的核心）

1. `OsaurusRouter.isEnabled`：缺省 `true` → `false`。**注意兼容性**：旧安装已写入 `true` 的用户不受影响（key 存在即按 key）；未写过 key 的新装/老用户都变 off。需要确认产品口径：老用户升级是否应「继承缺省 on」→ 视为「未显式选择」，按新默认 off 处理。这是**行为变更**，要在 release note 里写清。
2. `MobilePairingService.isReachAnywhereEnabled` 缺省 `true` → `false`（同样只影响未写过 key 的用户）。
3. 以上两处是**唯一**的默认状态改动；不新增隐藏设置。

### 3.2 入口隐藏（UI 面）

按「入口移除但代码保留」原则：

- Settings sidebar：`.connect`（Mobile）页内隐藏 "Reach From Anywhere" 区块（relay 不连，入口没意义）；**保留**配对/iPhone 相关本地功能（Bonjour 局域网配对不依赖上游）。
- Credits 页：Router toggle、credits 卡片、充值入口全部隐藏（Router off 时本就显示 explainer，直接整页收敛或改为「Router 不可用」说明）。
- Onboarding：去掉 Cloud/Router 预热路径（`connectOsaurusRouterIfPossible` 的 onboarding 调用点）。
- ChatView 等处的 Router usage 中心入口：隐藏（`isOsaurusRouterEnabled == false` 时本来就不显示，确认无其他入口）。
- `SettingsSearchIndex`：同步移除/标注 Router、Cloud credits、Reach Anywhere 相关条目（catalog 是搜索唯一真源，见 AGENTS.md 硬规则）。
- Identity 页：Osaurus ID 登录入口隐藏（上游身份服务不可用）；本机 Identity（master key、助记词）功能保留。

### 3.3 文案处理

- 隐藏后仍会被用户看到的 Router/Cloud 相关字符串（如 "router off" explainer）按 Phase 3 规则一并改名/改写，B 类（外部事实：定价、链接）逐条人工处理或删除。
- `osaurus.ai` 出现在**代码常量**（baseURL 等）：不改（连接代码保留），只是默认不再走到。

## 4. 影响面

- 代码面：Router 相关 ~70 文件、osaurus.ai 引用 ~73 文件（含文案）；实际**需要改的**预计 10–15 处（默认开关 2 处 + UI 隐藏 ~8 处 + search index + onboarding）。
- 测试：`Tests/Router/*` 多数测的是协议/签名逻辑，不依赖默认开关；需要新增「默认 off」用例（`isEnabled` 缺省值、onboarding 不预热）。
- 冻结清单：`ai.osaurus.*` UserDefaults key 不改名（INTERNAL-IDENTIFIERS.md 已冻结）。

## 5. 验证标准

1. 单元测试：`OsaurusRouter.isEnabled` 在干净 defaults 下为 `false`；`isReachAnywhereEnabled` 同理。
2. 网络判据：新装（无 keychain、无 defaults）启动后 10 分钟内，`lsof -i` / Little Snitch 观察**没有任何** `*.osaurus.ai` 出站连接（配对 iPhone、登录 ID、开 Router 除外）。
3. UI 走查：Settings 全文搜不到 "Router" / "Cloud" / "Reach From Anywhere" 入口；搜索（Settings search + `osaurus_help`）查不到这些设置项。
4. 回归：显式打开 Router（若用户通过 CLI/defaults 写入 key）后，原有 credits/连接行为不变。
5. `bash scripts/brand/verify.sh` 不回归。

## 6. 风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| 老用户升级后 Router 被静默关闭（缺省语义改变） | 中 | release note 明示；不迁移既有 key 的值 |
| 隐藏入口后仍有后台路径连上游（漏网调用点） | 中 | 验证标准 2 实机抓包兜底 |
| Router off 时代码路径空指针/假设 enabled | 低 | 上游已有 `guard isOsaurusRouterEnabled` 模式，逐个核对 |
| 上游 merge 把入口带回来 | 低 | Phase 3 brand 规则 + 本文件清单对照 |

## 7. 执行顺序（Phase 2 编译验收之后）

1. 默认开关 2 处 + 单测。
2. UI 隐藏 8 处 + SettingsSearchIndex + onboarding。
3. 实机网络判据验证。
4. 随 Phase 3 一并处理可见文案。
