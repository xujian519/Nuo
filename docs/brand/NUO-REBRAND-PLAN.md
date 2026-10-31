# Nuo 品牌改造方案

> 状态：已确认，Phase 0 已落地
> 仓库：`/Users/xujian/projects/Nuo`（Osaurus 的 fork）
> 基线提交：`c0da268a`
> 相关文件：`scripts/brand/`（可执行层）、`docs/brand/INTERNAL-IDENTIFIERS.md`（冻结契约）、`docs/brand/UPSTREAM-SYNC.md`（上游同步 Runbook）

---

## 1. 一句话

这个仓库要继续从上游 `osaurus-ai/osaurus` 合并更新，所以改名不能是全仓 `sed`。
方案把改名收敛成一个**可重放层**：`brand.json`（唯一真源）+ `rules/*.json`（幂等规则）+ `apply.sh`（每次 merge 后重放）+ `verify.sh`（CI 守卫）+ `baseline.json`（棘轮快照）。
估算改动面约 180 个文件，而不是深度改名会带来的约 1400 个。

---

## 2. 目标与非目标

### 目标

1. 用户能看到的一切都是 `Nuo` / `nuo`：App 名、菜单栏、关于面板、权限文案、6 语言界面文案、图标、DMG 文件名、CLI 命令、数据目录、URL scheme、Bonjour 服务名、Keychain 条目、bundle id。
2. 旧数据不丢：会话、模型、密钥、配置一次性自动迁移，且旧数据整版保留可回滚。
3. 外部契约不碎：Swift 模块名、插件 ABI、HF 模型 id、工具名、HTTP 头、环境变量等保持原样。
4. 上游可持续合并：`git merge upstream/main` 之后跑一次 `scripts/brand/apply.sh` 即可回到 Nuo 状态，冲突面集中在约 20 个文件。

### 非目标

- 不改 `LICENSE`（`Copyright (c) 2026 Osaurus, Inc.` 保留原文，等书面指示）。
- 不改 Swift 模块名 / target 名 / 目录名 / 工程文件名（`OsaurusCore`、`Packages/OsaurusCore/`、`osaurus.xcodeproj`、`osaurus.xcworkspace`）。
- 不改 1584 处文案的**实现方式**（不做集中常量重构），只改文案内容本身。
- 不改内部工程文档与证据目录（`docs/**` 除白名单外、`docs/evidence/**`、`results/**`、`reports/**`）。
- 不重建 Sparkle 发布链路（Phase 6 前用占位 feed，自动更新关闭）。

---

## 3. 已确认决策

| # | 决策 | 取值 |
|---|---|---|
| 1 | 改名深度 | 完整品牌替换（显示名 / 6 语言 / 图标 / 产物 / CLI / bundle id / 数据根 / Keychain / URL scheme / Bonjour） |
| 2 | bundle id | `com.nuo.app`（测试 target：`com.nuo.app.tests` / `com.nuo.app.uitests`）。需要自有域名后才算最终值 |
| 3 | 旧数据 | 一次性自动迁移，copy 不 move，旧数据整版保留 |
| 4 | 外部契约 | 冻结（见第 5 节），不随改名变动 |
| 5 | 上游跟进 | 继续跟随，规则化重放 + CI 守卫 |
| 6 | 版权署名 | `LICENSE` / `Credits.rtf` / `NSHumanReadableCopyright` 本轮不动 |
| 7 | 图标与 wordmark | 先上占位字标，等美术输入（outline 化矢量路径）替换 |
| 8 | Sparkle | nuo 版先关闭自动更新，feed 指向 `https://nuo.app/appcast.xml`（尚未发布） |
| 9 | 文档范围 | README + `COMMUNITY_EVALS.md` + `docs/plugins/**` + 内置 `Guide/**`；其余文档冻结 |
| 10 | Keychain ACL 被拒 | 接受系统弹窗重填；绝不静默变空（读失败要在 UI 明确提示） |

---

## 4. 命名契约

| 面 | 旧 | 新 | 备注 |
|---|---|---|---|
| 显示名 | Osaurus | **Nuo** | `CFBundleDisplayName`、菜单栏、关于面板 |
| bundle id | `com.dinoki.osaurus` | `com.nuo.app` | 驱动 TCC / UserDefaults 域 / Keychain ACL / Sparkle |
| 可执行名 | `osaurus` | `Nuo` | `PRODUCT_NAME = Nuo`，产物 `Nuo.app` |
| CLI 命令 | `osaurus` | `nuo` | 构建产物仍是 `osaurus-cli`（内部名，不改） |
| 内嵌 helper | `Contents/Helpers/osaurus` | `Contents/Helpers/nuo` | 旧名保留为相对软链一个版本 |
| URL scheme | `osaurus://` | `nuo://` | 一个版本内双注册 |
| Bonjour | `_osaurus._tcp` / `_osaurus-mobile._tcp` | `_nuo._tcp` / `_nuo-mobile._tcp` | 一个版本内双注册 + 双浏览 |
| 数据根 | `~/.osaurus` | `~/.nuo` | 迁移期读旧写新 |
| App Support | `~/Library/Application Support/com.dinoki.osaurus` | `~/Library/Application Support/com.nuo.app` | 旧路径继续参与迁移链 |
| Keychain | `com.osaurus.*` / `ai.osaurus.*` / `com.dinoki.osaurus.*` | `com.nuo.*` / `ai.nuo.*` | 15 个 service，逐个映射迁移 |
| UserDefaults 键 | `ai.osaurus.*` | 不变 | 键名是内部标识；bundle id 变了，域本身是新的，只需从旧域搬值 |
| Sparkle feed | `osaurus-ai.github.io/…` | `https://nuo.app/appcast.xml` | 自动检查关闭，等 feed 真发布 |
| DMG / 产物 | `Osaurus-<v>.dmg` | `Nuo-<v>.dmg` | `build-and-release.yml` |

---

## 5. 冻结清单（摘要）

完整表格与取证命令见 `docs/brand/INTERNAL-IDENTIFIERS.md`。原则：**用户看不见，或者改了只会碎的东西，一律不碰。**

- Swift 模块 / 包 / target：`OsaurusCore`、`OsaurusCLI`、`OsaurusCLICore`、`OsaurusRepository`、`OsaurusNetworking`、`OsaurusPlugins`、`OsaurusPluginTestKit`、`OsaurusEvals`、`OsaurusEvalsKit`、`OsaurusAI`。
- 插件 ABI：`osaurus_plugin_entry_v2`、`osr_*` 符号与类型、插件 bundle 清单 `osaurus-bundle.json`。
- 工具与协议：`osaurus_help` / `osaurus_inspect` / `osaurus_config`、`mcp__osaurus__*`、`X-Osaurus-*` 头、`window.__osaurus`、`__osaurus_abi_probe__`。
- 环境变量：`OSAURUS_*`、`OSU_*`。
- 系统标识：日志 subsystem `ai.osaurus`、dispatch label、`group.com.osaurus.shared`、`ai.osaurus.*` defaults 键、`ai.osaurus.id`、`osk-v1.`、加密域分隔串。
- 网络服务：`github.com/osaurus-ai/vmlx-swift` 等上游仓库地址、`www.osaurus.ai` API 域名。
- 工程与产物：目录名、工程/工作区文件名、scheme 名 `osaurus`、`osaurus-cli`、`osaurus-plugin-host`、`osaurus-evals`、CI artifact 内部名、Sentry release 名。
- 证据：`docs/evidence/**`、`results/**`、`reports/**`。

---

## 6. 架构：brand 层

```
scripts/brand/
  brand.json          唯一真源：新旧名字、冻结字面量、路径分类
  rules/10-app-identity.json    Phase 1
  rules/20-runtime.json         Phase 2（待加）
  rules/30-ui-text.json         Phase 3（待加）
  rules/40-docs.json            Phase 5（待加）
  brand.py            引擎：apply / verify / snapshot / inventory
  apply.sh            重放（每次 upstream merge 后跑）
  verify.sh           CI 守卫（<1s）
  snapshot.sh         重测棘轮基线
  baseline.json       当前遗留计数（用户可见口径）
```

### 6.1 规则引擎

四种 op：

| op | 用途 | 幂等保证 |
|---|---|---|
| `replace` | 正则替换（可限定文件、可只改 Swift 字符串字面量） | 替换结果再匹配不到原式 |
| `pbx-setting` | 按 bundle id 定位 `buildSettings` 块后改/删单个 build setting | 目标值已正确则跳过 |
| `insert-after` | 在锚点字面量后插入一行（plist 数组项） | 插入内容已存在则跳过 |
| `block` | 锚定多行原文的整块替换（脚本逻辑补丁） | 锚点消失且替换内容已在则跳过；两者都不在 → 退出码 3 报冲突 |

设计要点：

- **不做 before-count 断言，只做 post-condition（0 匹配）**。上游 merge 把某行带回来，规则自然重新命中；merge 带来新写法，规则立刻失效可见。
- **冻结字面量先切割**：任何文本规则执行前，先把 `brand.json → frozen.literals` 里的标识符切成不可编辑片段，所以一条 `Osaurus → Nuo` 的粗规则也碰不到 `OsaurusCore`、`ai.osaurus.`、`X-Osaurus-*`。
- **Swift 只数/只改字符串字面量**：`import OsaurusCore`、`OsaurusPaths.root()` 是代码不是品牌面，永不参与计数与改写。
- **`block` 规则先于 `replace` 执行**：整块补丁锚定今天的原文，细粒度替换随后处理剩下的部分。
- **`enforced` 分阶段开启**：阶段没做完时规则存在但不阻塞 CI；阶段落地时翻成 `true`，从此 CI 保证不再回退。

### 6.2 守卫（`brand-guard`）

三道检查，任何一条失败 CI 红：

1. **规则吸收**：所有 `enforced: true` 的规则必须 0 匹配。
2. **棘轮**：`paths.strict`（已改造面）里的文件，遗留计数不得超过 `baseline.json`；新增遗留直接失败。缩小不失败，但会提示重测基线。
   还没改造的面放在 `paths.strict_pending`，只统计不拦截 —— 每个阶段落地时把对应 glob 从 pending 挪到 strict，闸门跟着阶段走，不会一上来就红。
3. **契约存在**：`frozen.contracts` 里的字符串必须仍在（例如 `import OsaurusCore` ≥ 1200 次、`osaurus_plugin_entry_v2` 存在）。上游合进来把插件 ABI 弄丢会立刻被抓到。

当前实测（Phase 0 完成时）：strict 42 个文件 / 401 处遗留，pending 73 个文件 / 2657 处，`verify.sh` 约 0.5s。

> `scripts/live-proof/**`、`docs/evidence/**`、`results/**`、`reports/**` 是对历史证据的归档，不参与棘轮 —— 改写已归档的证明等于伪造证据。

### 6.3 与上游合并的工作流

```bash
git fetch upstream && git merge upstream/main      # 正常解冲突
scripts/brand/apply.sh                             # 重放规则
scripts/brand/verify.sh                            # 守卫
scripts/brand/snapshot.sh --write                  # 阶段推进后重测基线
```

规则锚点被上游改掉时 `apply.sh` 以退出码 3 中止并打印期望原文 —— 这是**设计好的失败**，不是静默放过。处理流程见 `docs/brand/UPSTREAM-SYNC.md`。

---

## 7. 阶段计划

### Phase 0 — brand 层（已完成）

- `scripts/brand/brand.json`、`rules/10-app-identity.json`、`brand.py`、`apply.sh`、`verify.sh`、`snapshot.sh`、`baseline.json`。
- `docs/brand/`：本方案、冻结清单、上游同步 Runbook。
- `.github/workflows/ci.yml` 增加 `brand-guard` job。
- `AGENTS.md` 增加一条硬规则引用。
- 验收：`apply.sh` 对当前树实际产生 65 处变更、再跑一次 0 处（幂等）、`verify.sh` 退出 0 且 <1s；人为往 `Makefile` 写一行 `Osaurus` 后 `verify.sh` 退出 1；把任一规则翻成 `enforced: true` 后 `verify.sh` 退出 1。三条均已实测。

### Phase 1 — 身份与产物（规则已就绪，待执行）

范围（`rules/10-app-identity.json` + 2 个手写补丁）：

- pbxproj：`PRODUCT_NAME = Nuo`、3 个 bundle id、`TEST_HOST`、`CFBundleDisplayName`、`SU_FEED_URL`、`SUEnableAutomaticChecks = NO`；删除 `INFOPLIST_KEY_NSMicrophoneUsageDescription`（见 7.1）。
- xcscheme：3 处 `BuildableName = "Nuo.app"`。
- `Makefile`、`scripts/build/build_arm64.sh`：产物路径 `Nuo.app`，内嵌 helper 改名 `nuo` 并留 `osaurus` 相对软链。
- `.github/workflows/build-and-release.yml`、`deploy-appcast.yml`：产物名与 artifact 名。
- 手写补丁：`scripts/osaurus` → `nuo` 逻辑（bundle id 双查、候选路径双列），`scripts/release/install_cli_symlink.sh`（装 `nuo`，旧 `osaurus` 软链只在不存在时补），CLI help 文案。

验收：

```bash
make cli && make app
xcodebuild -workspace osaurus.xcworkspace -scheme osaurus -configuration Debug \
  -derivedDataPath build/DerivedData build | tail -5
ls build/DerivedData/Build/Products/Debug/Nuo.app/Contents/Helpers   # nuo + osaurus 软链
xcodebuild -workspace osaurus.xcworkspace -scheme OsaurusCoreTests test  # 既有套件不回归
```

### Phase 2 — 运行时身份与数据迁移

新增 `Packages/OsaurusCore/Brand/Brand.swift`：唯一运行时真源。

```swift
public enum Brand {
    public static let display = "Nuo"
    public static let slug = "nuo"
    public static let bundleID = "com.nuo.app"
    public static let urlScheme = "nuo"
    public static let dataRootName = ".nuo"
    public enum Legacy {                 // 只给迁移用，规则引擎整目录跳过
        public static let dataRootName = ".osaurus"
        public static let appSupportDir = "com.dinoki.osaurus"
        public static let urlScheme = "osaurus"
        public static let keychainServices = [...15 个旧名...]
    }
}
```

改动点：

1. `OsaurusPaths.defaultRoot` → `~/.nuo`；`OSAURUS_TEST_ROOT` 语义不变。
2. Keychain：15 个 service 名换成 `com.nuo.*` / `ai.nuo.*`；`Brand.Legacy.keychainServices` 保留旧名。
3. Bonjour：注册 `_nuo._tcp` + `_osaurus._tcp`，浏览两者，按最近一次发现去重。
4. URL scheme：处理 `nuo://` 与 `osaurus://`（Info.plist 已双注册）。
5. 分布式通知：`com.nuo.control.*` 新发 + `com.dinoki.osaurus.control.*` 双发一个版本。
6. 迁移器 `BrandMigration.swift`（见第 8 节）。
7. CLI 侧 app defaults 域名跟随：`com.nuo.app` 优先、`com.dinoki.osaurus` 兜底（一个版本）。

验收：迁移证明（旧目录/旧 defaults/旧 keychain 造数据 → 新装启动 → 数据齐、旧数据仍在）、双注册证明（`open osaurus://…` 仍可达）、测试隔离证明（`OSAURUS_TEST_ROOT` 下不触发迁移）。

### Phase 3 — 界面与文案

- `Localizable.xcstrings`：386 个品牌 key / 1511 条本地化，按键类别分桶：
  - A 类「产品自称」→ 直接换 `Nuo`（约 70%）。
  - B 类「外部事实」→ 人工改写：`osaurus.ai` 定价/Cloud 计划、Discord、X、GitHub issue 链接、上游文档链接。**直接改名会变成假承诺，必须逐条处理。**
  - C 类「路径/标识」→ 用 `~/.nuo`、`nuo://` 等新值。
- `App/osaurus/InfoPlist.xcstrings`：13 个 key × 6 语言（显示名、11 条权限文案）。
- Swift 字面量：`AppDelegate`（菜单栏标题、tooltip、分析同意弹窗）、`osaurusApp.swift`（关于面板、Help 菜单、外链）、`AppIntents`、CLI help。
- 5 种非英文语言需要抽查：机械替换后检查语序与冠词（德/俄/韩/简繁）。

验收：6 语言 `Nuo` 全覆盖；`grep -i osaurus Resources/` 只剩冻结项；实机走查每个改动过的菜单与面板。

### Phase 4 — 资产

- App 图标（`App/osaurus/osaurus-app-icon.icon`）、`Assets.xcassets` 里 24 个品牌图：先出占位（`N` 字标 + 单色托盘图标），等美术。
- `osaurus-logo-wordmark.svg` 是 outline 化路径，只能重画，不能改字。
- 顺手修 `osuarus-yellow-create` 拼写（4 个文件，1 处 Swift 引用）。
- `assets/dmg-bg.tiff`（2.9MB 位图）需视觉核对是否烘焙了 wordmark。

**不重命名 imageset 目录**：Swift 里有 925 行按名字引用，改名纯属自伤；可见品牌在图像内容，不在资源名。

### Phase 5 — 文档

- `README.md` 重写（不是替换）：badge 指向上游仓库、Discord、X、`docs.osaurus.ai` 全部失效，需要换成 nuo 的或删掉。
- `COMMUNITY_EVALS.md`、`docs/plugins/**`（12 篇）、`Resources/Guide/**`（28 篇）机械替换 + 人工校对链接。
- 其余 `docs/**` 冻结：它们是工程文档，描述的对象仍是 `OsaurusCore` 等模块。

### Phase 6 — 发布链路与证明

- Developer ID 证书、nuo appcast feed、notarization profile（仓库外依赖）。
- 实机 UI 走查 + eval 套件（`make ci-test`、`make evals-deterministic`、AgentLoop 相关 lane）。
- PR 证据按 `AGENTS.md` 的 Release Proof 要求写：源 SHA、模型/套件、原始分数与分母、失败归因、本地证据路径。

---

## 8. 数据迁移设计

### 8.1 触发条件

只在 `OSAURUS_TEST_ROOT` 未设置时执行（否则测试会动真实家目录）。用标记文件 `.brand-migration.json` 保证只跑一次、可重入、可诊断。

### 8.2 五类数据

| 数据 | 位置 | 迁移方式 |
|---|---|---|
| 数据根 | `~/.osaurus` → `~/.nuo` | `cp -cR`（APFS clonefile，模型几十 GB 也是秒级、不占额外空间）；非 APFS 回退 `ditto` |
| 旧 App Support | `~/Library/Application Support/com.dinoki.osaurus` | 现有迁移链继续并入新根（保持两段兼容） |
| UserDefaults | 域 `com.dinoki.osaurus` → `com.nuo.app` | 枚举旧域 key 写进新域；**键名不变**（`ai.osaurus.*` 冻结）。CLI 侧按域名字面量读取（`Pull.swift:183`、`Configuration.swift:98`），必须同步；`group.com.osaurus.shared` 冻结（涉及 App Group entitlement，不改） |
| Keychain | 15 个 service | 逐个读旧名 → 写新名；读失败不静默 |
| 配置/端口 | `~/.nuo/config/server.json` | 随数据根整体搬迁 |

### 8.3 失败语义

- Keychain 读被 ACL 拒绝（`errSecAuthFailed` / `errSecInteractionNotAllowed`）：记录到标记文件，启动后弹一次「有 N 个密钥需要你重新授权」，点击重试带用户交互；**绝不表现为"密钥不存在"**。
- 迁移中途失败：标记文件写 `partial`，下次启动重试；旧根从不删除，删掉 `~/.nuo` 即回滚。
- 两边都存在：以新根为准，不合并（避免每次启动重扫）。

### 8.4 回滚

`rm -rf ~/.nuo` + `rm -f ~/Library/Preferences/com.nuo.app.plist`，旧连接管。文档里写清楚。

---

## 9. 并存期（一个版本）

| 面 | 并存方式 | 退场时机 |
|---|---|---|
| URL scheme | `nuo://` + `osaurus://` 双注册 | 下个版本删旧 |
| Bonjour | 双注册 + 双浏览 | 下个版本删旧 |
| CLI | 装 `nuo`，`osaurus` 软链只在缺失时补 | 手动退场 |
| 内嵌 helper | `nuo` + `osaurus` 相对软链 | 下个版本 |
| 通知 | 新旧双发 | 下个版本 |
| 旧数据 | 整版保留 | 用户自己删 |

---

## 10. 风险登记

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | bundle id 变更后 Keychain ACL 视为另一 app，读旧条目弹窗或被拒 | 密钥看似"消失" | 读旧写新 + 显式失败 UI + 退化方案（冻结 15 个 service 名） |
| R2 | TCC 权限全部重弹（麦克风/通讯录/日历/位置/屏幕录制/自动化） | 首启体验 | 已知行为，文案里说明；不假装保留 |
| R3 | 新旧 App 同时存在抢 1337 端口 | 服务起不来 | 旧 App 提示退出；新 App 端口冲突时明确报错而非静默换端口 |
| R4 | Sparkle feed 不存在 | 手动检查更新失败 | 自动检查关闭；菜单项在 feed 未配置时隐藏 |
| R5 | 5 种非英文语言机械替换后语义走样 | 界面不专业 | Phase 3 抽查 + 关键页面人工过一遍 |
| R6 | 上游 merge 改掉规则锚点 | apply 中止 | 退出码 3 + 打印期望原文 + Runbook |
| R7 | `osaurus.ai` 相关文案（Cloud 定价、Discord、文档站）机械替换后变成假承诺 | 用户被误导 | B 类文案逐条人工改写，禁止机械替换 |
| R8 | 发布链路（证书 / notarize / feed）在仓库外 | Phase 6 卡住 | 提前并行准备，不阻塞 Phase 1–5 |
| R9 | 迁移时模型目录几十 GB | 首启卡死 | APFS clonefile，失败回退 ditto 并显示进度 |
| R10 | 旧登录项变孤儿 | 开机启动失效 | 新 App 首启重新注册；文档说明 |

---

## 11. 验证矩阵

| 层 | 命令 / 证据 | 门 |
|---|---|---|
| 品牌守卫 | `scripts/brand/verify.sh` | 必须 <5s、退出 0 |
| 编译 | `make cli`、`make app` | 0 error |
| 单测 | `make test`、`make ci-test` | 不回归基线 |
| 发布构建 | `scripts/build/build_arm64.sh`（本地未签名变体） | `Nuo.app` 产物 + helper 软链 |
| 迁移 | 造旧数据 → 首启 → 比对会话/模型/密钥 | 三类数据齐全，旧数据仍在 |
| 并存 | `open osaurus://…`、`dns-sd -B _osaurus._tcp` | 双向可达 |
| 实机 UI | 菜单栏、关于、设置、6 语言切换 | 无 `Osaurus` 残留 |
| Eval | `make evals-deterministic` + AgentLoop lane | 按 `AGENTS.md` 记录原始分数 |

---

## 12. 工作量与推进顺序

| 阶段 | 文件量 | 依赖 | 可并行 |
|---|---|---|---|
| Phase 0 | 8 | — | 已完成 |
| Phase 1 | ~26 | Phase 0 | 与 Phase 2 文件集不相交，可并行 |
| Phase 2 | ~20 + 1 新模块 | Phase 1（产物名） | 与 Phase 1 并行 |
| Phase 3 | ~10 源文件 + 2 xcstrings | Phase 1 | 否（依赖产物名验证） |
| Phase 4 | ~30 资产 | 美术输入 | 与 Phase 3 并行 |
| Phase 5 | ~42 文档 | Phase 3 | 是 |
| Phase 6 | CI/发布 | 证书 + feed | 最后 |

---

## 13. 待外部输入

1. **美术**：wordmark（outline 矢量）、app 图标、托盘图标、占位字标确认。
2. **域名与证书**：`nuo.app` 是否自有（决定 bundle id 终值）、Developer ID、notarization profile。
3. **appcast feed**：`https://nuo.app/appcast.xml` 的托管方式。
4. **版权行**：`LICENSE` / `Credits.rtf` / `NSHumanReadableCopyright` 的最终署名。
