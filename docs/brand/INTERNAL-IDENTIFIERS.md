# 冻结标识符清单

> 原则：**用户看不见，或者改了只会碎的东西，一律不碰。**
> 这份清单同时是 `scripts/brand/brand.json → frozen.literals` 的来源：
> 文本规则执行前会把这些字面量切成不可编辑片段，所以一条 `Osaurus → Nuo` 的粗规则也改不到它们。

所有计数可用下面的命令复现（在仓库根目录执行）：

```bash
python3 scripts/brand/brand.py inventory     # 按 area 统计剩余品牌词
rg -o --no-filename -F '<字面量>' | wc -l     # 单个字面量的出现次数
```

---

## 1. Swift 模块 / 包 / target

| 标识符 | 参考量 | 为什么冻结 |
|---|---|---|
| `OsaurusCore` | 1228 处 `import OsaurusCore` | 改模块名要动 1300+ 文件的 import、包清单、工程引用；收益为零 |
| `OsaurusCLI` / `OsaurusCLICore` | — | 同上 |
| `OsaurusRepository` / `OsaurusNetworking` / `OsaurusPlugins` / `OsaurusPluginTestKit` | — | 同上 |
| `OsaurusEvals` / `OsaurusEvalsKit` | — | eval harness 的包名，CI 与 `make evals*` 依赖 |
| `OsaurusAI` | 758 处 | Hugging Face 组织名 + 模型 id 前缀，是**外部数据契约** |

> 取证：`rg -l '^(@testable )?import Osaurus' -g '*.swift' | wc -l` → 1323 个文件。
> 模块名不改，`Packages/` 目录名、`osaurus.xcodeproj`、`osaurus.xcworkspace`、scheme `osaurus` 也就都不用改。

## 2. 插件 ABI

| 标识符 | 参考量 | 为什么冻结 |
|---|---|---|
| `osaurus_plugin_entry_v2` | 40 处 | 原生插件动态库导出符号；改名让所有已编译插件失效 |
| `osr_*`（`osr_agent`、`osr_complete_fn`、`osr_db_query_t` …） | 11+ 符号 | 插件 C ABI 的整套类型/函数名 |
| `osaurus-bundle.json` | — | 插件/技能包的清单文件名，仓库外已有实例 |

## 3. 工具、协议、HTTP 面

| 标识符 | 为什么冻结 |
|---|---|
| `osaurus_help` / `osaurus_inspect` / `osaurus_config` | 模型侧工具名。改名 = 破坏已保存的 agent 配置、eval 用例、prompt 里的示例 |
| `mcp__osaurus__*` | MCP 工具命名空间，客户端已按此匹配 |
| `X-Osaurus-*`（13 个不同头） | HTTP 协议头，CLI / 浏览器扩展 / 中继端都按原样收发 |
| `window.__osaurus`、`__osaurus_abi_probe__` | 注入到插件 WebView 的全局对象与 ABI 探测键 |
| `osaurus://`（143 处） | 兼容期内双注册，旧链接必须继续可达 |

## 4. 系统与进程标识

| 标识符 | 参考量 | 为什么冻结 |
|---|---|---|
| `OSAURUS_*` / `OSU_*`（164 个不同变量名） | — | 测试、CI、打包脚本、用户脚本里的环境变量契约 |
| `ai.osaurus.*`（97 个不同键） | 191 处 | UserDefaults 键名 + Keychain 命名空间；bundle id 变了但键名不需要变 |
| 日志 subsystem `ai.osaurus` | — | 与 `log stream --subsystem ai.osaurus` 的既有用法绑定 |
| `group.com.osaurus.shared` | — | App Group id，改动会使既有共享容器失联 |
| `ai.osaurus.id` / `osk-v1.` | — | Osaurus ID 会话令牌与密钥编码前缀。`ai.osaurus.id` 是 Keychain service 名，令牌由上游 `*.osaurus.ai` 身份服务签发，改名只会把已登录会话弄丢——它是唯一一个**不改名**的 Keychain service（`Brand.Keychain.identitySession.legacy = nil`） |
| `com.dinoki.osaurus.control.*` | — | 分布式通知名；CLI 侧双发一个版本 |
| dispatch queue label `ai.osaurus.*` / `com.dinoki.osaurus.*` | — | 只在调试器与 `log stream` 过滤里可见，改无收益 |
| `com.dinoki.osaurus` 日志 subsystem | — | 同上；日志口径不是品牌面 |

## 5. 上游地址与产物

| 标识符 | 为什么冻结 |
|---|---|
| `github.com/osaurus-ai/vmlx-swift` 等上游仓库地址 | 包依赖来源，改了拉不到代码 |
| `www.osaurus.ai` API 域名 | 上游云服务端点，改名不会让服务出现在 nuo 域名下 |
| `osaurus-cli` / `osaurus-plugin-host` / `osaurus-evals` | SwiftPM product 名与 CI 二进制名（用户看到的是 `nuo`，内部名不变） |
| CI artifact 内部名（`nuo-app-*` / `nuo-release-*`） | 只在 Actions 页面里可见；同一 workflow 内成对使用，上游没有跨 run 按名下载，跟着品牌走 |
| Sentry release 名 | **不冻结**：Cocoa SDK 用 `<CFBundleIdentifier>@<version>` 作为 release 名，bundle id 变了就必须跟着变，否则 dSYM 传到没人上报的 release 下 |
| `docs/evidence/**`、`results/**`、`reports/**` | 历史证据。改写已归档的证明等于伪造证据 |

---

## 6. 加密域分隔串与签名 payload（改一位就丢数据/验签失败）

这些字符串是**密码学契约**：它们分隔不同用途的密钥派生与签名输入。改名不会带来任何用户可见收益，
只会让已加密数据无法解密、已发出的邀请/配对/隧道握手全部验签失败。因此即使它们的字面量带着
`osaurus`，也必须原样保留。

| 标识符 | 位置 | 后果 |
|---|---|---|
| `osaurus-storage-v1` | `StorageKeyManager.hkdfInfo` | SQLCipher DEK 的 HKDF info。改了 → 已加密会话库打不开 |
| `osaurus-agent-v1` / `osaurus-agent-v2` | `AgentKey` | 代理主密钥/地址派生域 |
| `osaurus-pair-v1` / `osaurus-pair-v2` / `osaurus-pair-key-v1` | `PairingKey`、`PairingSPAKE2`、`PairingKeyEnvelope` | 设备配对与密钥信封 |
| `osaurus-pairing-server-v1` | `CryptoHelpers` | 配对服务端签名 |
| `osaurus-sc1` | `SecureChannel` | Secure Channel 握手 transcript 域 |
| `osaurus-id` | `IdentityModels`（`typ`） | 身份令牌类型 |
| `osaurus-agent-invite-v1:` | `AgentInvite.signingPayload` | 邀请链接签名；改了旧链接一律签名不匹配 |
| `osaurus-credits:` / `osaurus-owner:redeem:` / `osaurus-workspaces:redeem:` / `osaurus-teams:redeem:` | 钱包签名 payload | 服务端按旧串验签，改了兑换全部失败 |
| `osaurus-tunnel:` | `RelayTunnelManager` | 中继隧道鉴权串 |
| `osaurus-bundle.json` / `osaurus-manifest.json` / `osaurus-plugin.json` | 清单文件名 | 仓库外已有实例；改名读不到已发布插件/模型包 |
| `group.com.osaurus.shared` | App Group | 既有共享容器 |

> 取证：`rg -n '"osaurus-[a-z0-9]+' -g '*.swift' Packages/OsaurusCore | grep -v /Tests/`

---

## 7. 明确**不**冻结的东西

下面这些看起来像标识符，但属于品牌面，必须改：

- `~/.osaurus` → `~/.nuo`（数据根，随迁移一起换；旧树整版保留）
- `com.dinoki.osaurus`（bundle id；构建配置里改，迁移代码里作为 legacy 常量保留）
- `_osaurus._tcp` / `_osaurus-mobile._tcp`（兼容期双注册 + **双浏览**：`BonjourBrowserCore` 同时浏览 `_nuo._tcp.` 与旧类型，按 agent id 去重，只有两种类型都消失才在宽限期后下线）
- `osaurus://`（兼容期双注册 + **双解析**：`Brand.ownsURLScheme(_:)` 同时接受 `nuo://` 与 `osaurus://`；新链接一律按 `nuo://` 生成）
- 14 个 Keychain service 名（改名 + 懒迁移；`ai.osaurus.id` 不动，见第 4 节；失败必须原样上报，绝不降级成 `notFound`）
- `Contents/Helpers/osaurus`（改名 `nuo`，旧名留软链）
- `LICENSE` 里的版权行（等书面指示，不在本轮范围）
