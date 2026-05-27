# MailAgent ↔ Ping Island 集成 — Review + 优化 Handoff

> **状态**：**Phase 3 P0 Quick Fix 已 ship**（2026-05-26 晚）。3 个用户报问题 + 4 个 plugin P0 隐患 — 9 个 atomic commits 解决。详见文末 §8。
> **历史**：本文 §1-§7 是 2026-05-26 初版 review 内容；后续经多 agent 交叉验证发现 3 个事实误判（mascot 资产已 ship / Phase 2 大部分已 ship / 方案 D 未列），就近在原章节加 `>  **更正**:` 备注，结论以最新 ship 记录为准。
> **方向（修正）**：~~用户已推翻 fork minimal 约束~~ → 实测 fork Swift 改动仍可控（8997 行 diff = 6700 行 docs + ~2300 行 Swift）。Phase 3 P0 采用 critic 推荐的 Quick Fix 路径 A（45 行 Swift），不走原推荐的"大胆新建 dock"。
> **fork 端行号**为 review 时（branch `feat/mail-brand` HEAD `3d42f69`）状态，实施时以当前代码为准。

---

## 0. TL;DR — 三个问题同源

MailAgent 用 **"常驻 `mail-sync` 进程 push envelope"** 模型，套进 ping-island 的 **"hook 注入 + session phase 状态机"** 模型。三个问题都是这个错配的表现：

| # | 用户现象 | 根因一句话 |
|---|---|---|
| 1 | 设置里 mailagent "没安装就能用" | Island 的"安装"机制对 mailagent 是**空操作**（不该装却假装能装），渲染纯靠 envelope 与安装解耦 |
| 2 | 未展开（collapsed）态没有通知 icon | mail 的 `notification` 事件落 `.idle` phase → 不进 collapsed 可见集；且 `MascotKind` 无 `.mail`（fallback 成翼盔狐 Hermes） |
| 3 | 左侧顶部固定消息没有 | = DESIGN.md §7 的 "Phase 2 resting icon dock"，**fork 从未实现**（base app 无此 primitive） |

**问题 2 与 3 强耦合**：都因 mail 通知不进 collapsed 可见集。**建议合并实现一个 mail 专属的 collapsed "resting-icon 层"**，一次解决两者，收益最大。

---

## 1. 架构现状（数据流 + 状态机）

### 1.1 envelope → fork 数据流（纯 socket，与安装无关）
```
MailAgent: dispatch_*  (src/notify/island_dispatch.py)
  → BridgeEnvelope (island_envelope.py) → .encode() JSON
  → ping_island.send_async → AF_UNIX connect /tmp/island.sock → sendall/recv
fork: HookSocketServer 收 → makeEnvelope/makeClientInfo → SessionState
```
- socket 路径 `ISLAND_SOCKET_PATH` 或 `/tmp/island.sock`（`ping_island.py:48-49`）。fail-open，对端不在入 reconnect queue。
- **关键：发送链路完全不读 Island 安装状态**——socket 在 + envelope 合法即送达渲染。这是问题 1 的机制根源。

### 1.2 envelope schema 要点（`island_envelope.py`）
- `provider` 固定 `"mail"`；`eventType` 经 `_WIRE_EVENT_MAP` **一律翻成 `"Notification"`**（fork dispatcher 只认 5 个内置 hook 名），原 mail event 名进 `metadata["mailagent.eventType"]`。
- `status: {kind}`，kind ∈ `notification | waitingForInput | completed | error`。
- `metadata["tool_use_id"] = "bridge-<envelope_id>"`（fork 反向 `respondToIntervention` 用）。

### 1.3 brand 匹配（决定能否走 mail 专属渲染）
`island_dispatch._base_metadata` 每个 envelope 注入 5 个 key：`client_kind=mailagent` / `client_name=MailAgent` / `client_origin=plugin` / `client_originator=MailAgent` / `thread_source=mailagent-hooks`。
→ fork `HookSocketServer.makeClientInfo`（`:695-913`）→ `matchRuntimeProfile`（`ClientProfile.swift:1538-1570`，kind 命中 +100）→ mailagent runtime profile（`ClientProfile.swift:1262-1276`）→ `brand=.mail`。
- **缺这 5 个 key → 匹配失败 → kind=.custom → brand=.neutral → mail 专属渲染全失效**（fork commit `171f907` 就是补这个的 bug fix）。

### 1.4 collapsed 状态机（`NotchView.swift` / `IslandPresentation.swift`）
- 形态：**closed**（只 `headerRow`）/ **opened**（`headerRow` + content）。无单一 collapsed/compact 枚举。
- closed `headerRow` 三段（`NotchView.swift:633-683`）：**左** = 单个 `MascotView(size:16)`（`:643-651`）；**中** = `closedCenterMessage`（仅 `detailed` mode）；**右** = `BellIndicatorIcon` / `SessionCountIndicator`。
- closed 自动隐藏 `shouldHideForIdleState`（`:161-168`）：`activeSessions.isEmpty && !hasPendingPermission && !hasHumanIntervention && !hasCompletedReadyState` 时整个 notch 隐藏。
- closed mascot 来源只挑 `phase.isActive || needsManualAttention` 的 session（`IslandPresentation.swift:127-134`）。

### 1.5 status → phase 映射（问题 2/3 的命脉，已 verify）
`SessionRecord.sessionPhase`（`HookSocketServer.swift:129-151`）：
```
waiting_for_approval → .waitingForApproval
waiting_for_input    → .waitingForInput   ← 仅 urgent mail 走这
running_tool/processing/starting → .processing
compacting → .compacting
default    → .idle                        ← notification / ended(completed) 全落这
```
**`.idle` 不满足 `phase.isActive`** → mail 普通通知既不是 mascot source、又被 `shouldHideForIdleState` 隐藏 → **collapsed 态什么都不显示**。

### 1.6 profile 三表 + "注册" vs "安装"（`ClientProfile.swift`）
- `managedHookProfiles`（`:994-1027` mailagent）：Settings「集成 → Hooks 管理」列表项。mailagent：`installationKind:.pluginDirectory`, `alwaysVisibleInSettings:true`, `localAppBundleIdentifiers:["com.apple.mail"]`。
- `runtimeProfiles`（`:1262-1276` mailagent）：**渲染关键表**，envelope brand 匹配用。
- **"注册" = 编译进 app 的静态常量**（mailagent 全在）；**"安装" = `HookInstaller.isInstalled` 检测磁盘托管文件**。二者完全解耦。

---

## 2. 问题 1 — "设置里 mailagent 没安装就能用"

### 现状 / 根因（**设计错配，非功能 bug**）
1. **为什么恒显示**：`visibleHookProfiles` 过滤 `alwaysVisibleInSettings || ...`（`SettingsWindowView.swift:217-220`），mailagent `alwaysVisibleInSettings:true` → 永远显示在「集成 → Hooks 管理」。
2. **为什么"没安装就能用"**：
   - 渲染靠 envelope metadata（§1.3），与安装零关系。
   - mailagent `installationKind:.pluginDirectory`，但 **`HookInstaller.managedPluginDirectoryFiles` 对 mailagent 返空 `[:]`**（`HookInstaller.swift:2597-2600`，`guard profile.id == "hermes-hooks"`）→ 点「安装」写 0 文件 → `isInstalled` 检测 `~/.mailagent/plugins/ping_island/{plugin.yaml,__init__.py}` marker（`:1813-1831`）**永远 false**。
   - MailAgent Python 端 `island_bootstrap.py` 实际写的是 `manifest.json`（+ locales），**文件名跟 Island 检测的不一致** → 即便 bootstrap 跑过，仍显"未安装"。
3. **症状**：mailagent 行恒显 **"未安装" +「安装」按钮**（点了无效），而灵动岛照常工作 → 用户困惑。

### 对比其他 profile
claude/codex 是 `installationKind:.jsonHooks`：`isInstalled` 检测 `~/.claude/settings.json` 含托管 hook 段，「安装」真写 hook 配置——**它们安装状态与"能用"强相关**（不装 hook 就不发 envelope）。mailagent 是常驻进程模型，Island 根本不需要"装"。

### fork 实现建议

> **2026-05-26 更正 — 方案 D 才是最优解**（critic review 发现）：
> 方案 A/B/C 都漏了一条更简路径。`ClientProfile.swift:1004` 已写 `configurationRelativePath: ".mailagent/plugins/ping_island/manifest.json"`，且 plugin 端 `island_bootstrap.py:115` 也写 `manifest.json`，**两端路径本就对齐**。卡点仅在 `HookInstaller.managedPluginDirectoryFiles:2597 guard profile.id == "hermes-hooks"` 拦住了 mailagent 走 `containsManagedPluginDirectory` 真正检测。
>
> **方案 D（已 ship 路径，~10 行 diff）**：在 `containsManagedPluginDirectory` 加 mailagent 早期 return（目录/manifest 存在即视为已接入），`managedPluginDirectoryFiles` 仍返空（不主动写文件，避免覆盖 MailAgent 自己的 manifest）。
>
> **对比**：方案 A 涉及 10 处 `installationKind` switch 全要补 + UI 重构 HookManagementLine + 新 `.externalProducer` enum case（~100 行）；方案 D 是 hermes-hooks 同模式的 if 分支扩展（~10 行），**对称性最好**，长期维护成本最低。
> Phase 3 P0-1 commit `61bee08` 走方案 D。

**方案 A（原推荐，已被方案 D 超越）**：给 mailagent 一个"外部托管、Island 不接管安装"的语义：
- `ClientProfile.swift`：`ManagedHookInstallationKind` 加 case `.externalProducer`，mailagent profile 改用它。
- `HookInstaller.swift:867-882 isInstalled`：该 kind 时检测 MailAgent 真实落地的 `~/.mailagent/plugins/ping_island/manifest.json`（对齐 `island_bootstrap.PLUGIN_DIR`），存在即「已接入」。
- `SettingsWindowView.swift:2613 / 2628-2664 HookManagementLine`：该 kind 时徽章文案改 **「已接入 / 进程未运行」**，按钮区去掉「安装/卸载」，只留「打开配置目录」「查看文档」。

**方案 B（省事）**：让 `managedPluginDirectoryFiles` 对 mailagent 也写一个含 `managedMarker` 的标记文件（`plugin.yaml`），使「安装」能翻 `isInstalled=true`。缺点：该文件对 MailAgent runtime 无意义（纯为骗检测）。

**方案 C（最省）**：纯改 `subtitle`（`ClientProfile.swift:997`）说明"由 mail-sync 进程自动接入，无需安装"，接受恒显"未安装"。效果最差。

---

## 3. 问题 2 — collapsed 态没有通知 icon

### 现状 / 根因（双重断点，已 verify）
- collapsed leading 是**唯一一个** `MascotView`（`NotchView.swift:643-651`），不是 per-notification icon。
- **断点 ①**：非 urgent mail（`notification`/`completed`）→ `sessionPhase` default → `.idle`（`HookSocketServer.swift:148-149`，已 verify）→ 不 active 不 attention → 被 `shouldHideForIdleState` 隐藏 → collapsed 啥都不显示。
- **断点 ②**：即便 urgent（`waitingForInput`）显示，`MascotKind` **无 `.mail` case** → `MascotClient` 的 `.mail → .hermes` fallback（`MascotView.swift:152-155`，已 verify，注释自带 `// Sprint 5 polish: add MascotClient.mail + MascotKind.mail`）→ 画出翼盔信使狐，不是邮件图标。
- 对比：展开态 `MailAgentSessionView` 用真 `Image("MailLogo")` imageset（`:341-363`）——与 collapsed 的 Canvas-Hermes 是两套资产。

### fork 实现建议

> **2026-05-26 更正 — mascot 资产已 ship，工作量被高估**（critic review 发现）：
> `MailLogo.imageset` + `MailMascot{Work,Personal,Dev}.imageset` 都已在仓里（commit `0e5c8b2`，含 @1x/@2x/@3x），且 `MailAgentSessionView.swift:341-363` 内部已经在用。**只缺 collapsed 态的 `MascotView` 暴露 `.mail` case** —— 实际是 5 行 enum + 1 个 Image 分支的改动，不是"中-大工作量"。
>
> Phase 3 P0-2/3/4 (commits `a630afe`/`108a67e`/`b3646e7`) 已 ship 此 quick fix（共 ~30 行 Swift，drawMascot 用 `context.resolve(Image("MailLogo"))` aspect-fit 渲染）。

1. **mascot 资产**（兑现作者自留的 Sprint 5 polish）：`MascotView.swift` 给 `MascotKind` + `MascotClient` 加 `.mail` case；`drawMascot`（`:588-614`）加 `case .mail`，**复用 `MailAgentSessionView` 的 `Image("MailLogo")` imageset 走图片分支**（避免重画像素图）。把 4 处 `.mail → .hermes`（`:155/206/233/256`）改成 `→ .mail`。
2. **让 mail 通知进 collapsed**（用户真正要的"通知 icon"）：**不要**把所有邮件硬塞成 `waitingForInput`（语义会全变"待输入"）。

> **2026-05-26 更正 — 方法 2 有更简路径**（critic review 推荐）：
> 原推荐"与问题 3 合并加 resting-icon 层"是过度工程。更简：`NotchView.shouldHideForIdleState`（`:161-168`）加一个 `!hasRecentMailActivity` 条件（mail 5min TTL），让现有 mascot + SessionCountIndicator 在 collapsed 态可见，覆盖 90% 用户诉求。**不新建 dock**，**不改 `closedLeadingWidth`**，base brand 行为零变化。
> Phase 3 P0-5 (commit `b5c860c`) 已 ship 此路径（10 行 Swift）。
> 完整 resting-icon dock（§4）作为 nice-to-have，等用户用 P0 后再决定。

---

## 4. 问题 3 — "左侧顶部固定消息"= DESIGN.md §7 resting-icon dock

### 这是什么（已在 MailAgent `docs/mailagent/DESIGN.md` 定义）
DESIGN.md §7（`:801-845`，尤其 `:818/822-825`）：邮件到达 4s 全 pill（Phase 1）收起后，**在物理刘海左侧留一排 22×22 彩色小图标**，每封待处理邮件一个，**按 priority 排序（Critical→Failed→AI ready→Urgent→Queued），max 4 + `+N` 折叠**，持久驻留到 ack/处理。

> **2026-05-26 更正 — Phase 2 opened 态已 ship，只缺 closed 态 dock primitive**（critic review 发现）：
> `MailAgentSessionView.swift:36-52` 已经实现了 6 个 scenario layout（MailReceivedUrgent / LLMReviewedUrgent / AIDraftReady / MailCompleted / SyncFailed / DeadLetterAccum / DailyDigest），button wire `respondToIntervention` 也通了（commit `bbcf85a`）。**问题 3 实际是"collapsed 态左侧没有 multi-icon dock primitive"，不是"DESIGN.md §7 完整未实现"**。
>
> Phase 3 P0 决策**未实现完整 dock**，改用 P0-5（NotchView.shouldHideForIdleState 加 mail TTL 例外）让现有 collapsed mascot + count 显示，覆盖 90% 体验。完整 §7 dock 等用户用 P0 后再决定（critic 评为 nice-to-have，非 must-have）。

### 现状 / 根因
- **fork 从未实现完整 dock**。collapsed `headerRow` 左侧只有单个 `MascotView`，没有任何"多图标左侧 dock"primitive。
- 这是 **MailAgent DESIGN.md 独有设计**，base ping-island 是"单 mascot + 右侧计数"模型，无对应物可借。

### fork 实现建议（效果优先 → 大胆新建）
1. **数据源**：`NotchView` 加 `var mailRestingSessions: [SessionState]` = `sessionMonitor.instances.filter { $0.clientInfo.brand == .mail && 未ack }`，按 `metadata["mailagent.scenario"]` 留存（urgent/SyncFailed/AIDraftReady/DeadLetterAccum）、`MailCompleted` 清除，按 DESIGN.md `:824` priority 排序（读 `metadata["mailagent.aiPriority"]`/scenario）。
2. **让它们不被隐藏**：`shouldHideForIdleState`（`NotchView.swift:161-168`）条件 OR 上 `!mailRestingSessions.isEmpty`。
3. **新视图** `MailRestingIconDock.swift`：参考 `StatusIcons.swift` Canvas 风格 + `SessionCountIndicator` 的 `+N` 样式，22×22 + 6px gap + cap 4 + `+N` chip + Critical 红脉冲（`MailAgentSessionView.swift:509-529` 的 pip/脉冲色可复用）。
4. **挂载**：`NotchView.swift:641-652 headerRow` 的 `HStack` 最左插入 `if !mailRestingSessions.isEmpty { MailRestingIconDock(...) }`；同步更新 `closedLeadingWidth`/`closedCenterWidth`（`:689-706`）把 dock 宽度算进去防挤压。
5. **交互**：点图标 → `viewModel` open + 设对应 session 为 attention → 复用 `SessionAttentionNotificationView`→`MailAgentSessionView`；ack → `respondToIntervention`（`:461`）+ 从 dock 移除。
6. **清除**：`MailCompleted` envelope（`island_dispatch.py:331-354`）到达移除对应 session。

> 这一层同时解决问题 2 的"通知 icon"——resting dock 里每个图标就是 per-mail 的 collapsed icon，且按 priority 着色，比单 mascot 信息量大得多。

---

## 5. 推荐实施顺序（效果优先）

| 序 | 工作 | 收益 | 工作量 |
|---|---|---|---|
| 1 | **问题 2+3 合并：mail resting-icon dock + `.mail` mascot** | 最高（收起态终于有持久邮件图标，DESIGN.md §7 落地） | 中-大（新视图 + NotchView 改 + mascot 资产） |
| 2 | 问题 1：profile 安装语义（方案 A） | 中（消除"假未安装"困惑） | 小-中 |

**问题 2/3 必须一起做**（同根：让 mail session 进 collapsed 可见集）。先做这个，再补问题 1 的 Settings 语义。

---

## 6. MailAgent 端（plugin）配合点

fork 改动若需 plugin 配合，集中在这几处（MailAgent repo）：
- **envelope 已带的字段**：`metadata["mailagent.scenario"]`（路由）、`mailagent.aiPriority`/`aiAction`、`mailagent.mascot`（domain→mascot id，resting dock 排序/着色可用）、brand 5-key（§1.3）。**大部分 resting dock 所需数据 envelope 已有**，fork 直接读 metadata 即可。
- 若 resting dock 需要 plugin 显式发"清除"信号：已有 `dispatch_mail_completed`（`island_dispatch.py:331-354`，`status_kind=completed`）可作清除触发。
- 若需新字段（如 resting dock 专用的 priority rank / icon id），在 `island_dispatch._base_metadata` 或对应 `dispatch_*` 加 `metadata["mailagent.*"]`，fork 端读。

---

## 7. 关键文件速查表（review 时行号）

**fork（ping-island）**
| 事实 | 位置 |
|---|---|
| collapsed headerRow 三段 / 单 MascotView | `NotchView.swift:633-683` / `643-651` |
| shouldHideForIdleState | `NotchView.swift:161-168` |
| sessionPhase（notification/ended→.idle）✅verify | `HookSocketServer.swift:129-151` |
| MascotClient .mail→.hermes fallback ✅verify（含 Sprint5 TODO 注释） | `MascotView.swift:152-155` |
| MascotKind 枚举（无 .mail） | `MascotView.swift:262-274` |
| MailAgentSessionView（Image("MailLogo") / scenario 路由 / button 回路） | `MailAgentSessionView.swift:36-52` / `341-363` / `461-465` |
| brand 匹配 matchRuntimeProfile | `ClientProfile.swift:1538-1570` |
| mailagent managedHook / runtime profile | `ClientProfile.swift:994-1027` / `1262-1276` |
| isInstalled / managedPluginDirectoryFiles（mailagent 返空） | `HookInstaller.swift:867-882` / `2597-2600` |
| Settings 集成分类 / Hooks 管理 / 徽章 | `SettingsWindowView.swift:28` / `1877-1950` / `2613` |
| mascot source（仅 active/attention） | `IslandPresentation.swift:127-134` |

**MailAgent（plugin）**
| 事实 | 位置 |
|---|---|
| envelope brand 5-key 注入 | `src/notify/island_dispatch.py:_base_metadata` |
| eventType→Notification + tool_use_id | `src/notify/island_envelope.py:38-60 / 144-148` |
| socket sender（fail-open） | `src/notify/ping_island.py:48-49 / 126-130` |
| plugin assets 写 manifest.json | `src/notify/island_bootstrap.py` |
| DESIGN.md §7 resting-icon 规格 | `docs/mailagent/DESIGN.md:801-845` |

---

*Review by Claude Opus 4.7 (1M context)，代表 chenyqthu，2026-05-26。基于深度代码 review + 2 个核心根因实读 verify。实施时以当前 fork 代码为准。*

---

## 8. Phase 3 P0 Ship 记录（2026-05-26 晚）

### 8.1 决策路径与凭据

经 3 路 opus reviewer 交叉验证（fork-side architect / mailagent-side architect / critic），critic 揪出原 handoff 3 个 CRITICAL 事实错误（mascot 资产已 ship / Phase 2 大部分已 ship / 方案 D 未列）+ 5 个 MAJOR gaps，推翻"完整 resting-icon dock 是首选"的判断。

**用户决策（through `AskUserQuestion`）**：路径 A（Quick Fix 半天）+ plugin 4 项全修 + executor/verifier 双轨施工。

### 8.2 9 个 atomic commits（已 build / 已 test pass / 已 verifier APPROVE）

#### Fork 端（branch `feat/mail-brand`，净增 44 行 Swift）

| Commit | 文件 | 一句话 |
|---|---|---|
| `61bee08` (FE-1) | `HookInstaller.swift` | `containsManagedPluginDirectory` 加 mailagent 早期 return（方案 D）→ 修问题 1 "假未安装" |
| `a630afe` (FE-2) | `MascotView.swift` | `MascotClient`/`MascotKind` 各加 `case mail` + 所有 switch 补分支 |
| `108a67e` (FE-3) | `MascotView.swift` | `drawMascot .mail` 走 `context.resolve(Image("MailLogo"))` aspect-fit |
| `b3646e7` (FE-4) | `MascotView.swift` | 4 处 fallback `self = .hermes` → `self = .mail` |
| `b5c860c` (FE-5) | `NotchView.swift` | `shouldHideForIdleState` 加 `!hasRecentMailActivity`（mail 5min TTL）→ 修问题 2 collapsed 可见 |

xcodebuild 每个 commit 独立 SUCCEEDED；base brand（claude/codex/hermes 等）零行为变化（verifier D 类独立 confirm）。

#### Plugin 端（`/Users/chenyuanquan/Documents/Mailagent/` branch `feat/island-p0-fixes`，+1162/-67 行 Python）

| Commit | 一句话 |
|---|---|
| `667c9b0` (PE-1) | `_enqueue_snooze` 后追发 MailCompleted + `mailagent.snoozeReason` metadata → 修 snooze 卡 dock bug |
| `f56cc82` (PE-2) | `dispatch_ai_draft_start/stream/ready` 三函数 + action whitelist 加 `send_draft/edit_draft/discard_draft` |
| `0a68268` (PE-3) | reconnect queue 优先级保留（critical 优先 notification） + 冷启动 5min × 5s 短探测 |
| `687f23a` (PE-4) | `dispatch_action_acked` envelope + `handle_response` 全 path 追发 → subprocess 结果回流 fork |

`pytest tests/notify/`: **260/260 passed**（含 PE-4 新增 13 个 test）。

#### Phase 3 Polish（fork 端，后续追加，+455/-28）

| Commit | 文件 | 一句话 |
|---|---|---|
| `87ca0b9` (Polish-1) | `MailAgentSessionView.swift` | 加 `case "ActionAcked"` ackedLayout，读 actionAckedChoice/Ok/error 显示成功✓/失败✗ + choice 可读文案 helper（8 映射） |
| `95ba312` (Polish-2) | `SessionStore.swift` | `pruneOrphanedSessions` 拆 `switch provider`，新增 mail 分支（12h TTL + `!needsManualAttention` → `removeValue` 真删 + `cancelPendingSync`）；claude GC 字节级零变化 |
| `159b1e2` (Polish-3) | `MailAgentBrandTests.swift` + `MailAgentSessionViewTests.swift` | 16 个新单测：brand 5-key 推导（含降级 .neutral）/ scenario→layout 路由（8 分支含 ActionAcked）/ button wire |
| (pending, 2026-05-27) | `SessionState.swift` + `SessionListView.swift` + `SessionTextSanitizer.swift` | **接入点 C 列表预览修复**：mail 会话 `/ · /` → `InstanceRow` 经新增 `SessionState.mailListTitle/mailListPreview` 读 `mailagent.subject/aiSummary/sender` 显真实主题+摘要（列表原生，非整卡）；顺带 `SessionTextSanitizer` 剥离 `<command-message/name/args>`+`<local-command-stdout>` 斜杠命令包裹，修 `/clear` 标题残留 `<command-message>…`。+10 单测（4 mail list + 6 sanitizer，新建 `SessionTextSanitizerTests.swift`） |

`PingIslandTests` bundle: **648 passed / 0 failed**（含 16 个新 mail 测试）。base regression：claude/codex/hermes 路径字节级零变化（lead diff review confirm）。

> Polish-4（2026-05-27, 上表末行）后本地全量 `xcodebuild test -only-testing:PingIslandTests` → **`** TEST SUCCEEDED **` / 0 failed**（含本次 +10）。注：本机缺 team `2DKS5U9LV4` 的 "Mac Development" 证书，需 `CODE_SIGNING_ALLOWED=NO` 跑纯逻辑单测；未 commit（push 决定权保留给用户）。

### 8.3 新跨端契约（plugin 已发，fork 端消费状态）

| 字段 / 事件 | 来源 | fork 消费 | 状态 |
|---|---|---|---|
| `mailagent.aiSummary` (AIDraftReady) | PE-2 `dispatch_ai_draft_ready` | `MailAgentSessionView.aiSummary` 读后 `draftPreviewCard` 渲染 | ✅ 完全对接 |
| `AIDraftReady` scenario | PE-2 | `MailAgentSessionView:42 case "AIDraftReady": draftLayout` | ✅ 完全对接 |
| `mailagent.snoozeReason` | PE-1 | 未读 | ⚠️ silent 向后兼容（MailCompleted 主路径已工作） |
| `mailagent.actionAckedChoice/EnvelopeId/Ok` | PE-4 | Polish-1 `case "ActionAcked"` ackedLayout 读取 | ✅ 已对接（expand 态显示成功✓/失败✗ + choice 可读文案） |
| `AIDraftStream` (`draftChunkText/Index`) | PE-2 | 走 fallback layout | ⚠️ 流式 chunk 在 fork UI 不显示（设计可接受，仅 AIDraftReady 需用户响应） |

### 8.4 已知 gap（下个 sprint 候选）

> **Polish 已解决 3 项**（commit `87ca0b9`/`95ba312`/`159b1e2`）：~~ActionAcked silent 无 UI~~ → Polish-1 ackedLayout · ~~mail session 不被 GC~~ → Polish-2 12h TTL · ~~0 mail unit test~~ → Polish-3 16 个单测。剩余 gap：

| Gap | 严重度 | Fix 建议 |
|---|---|---|
| FE-1 `containsManagedPluginDirectory` 检测的是**目录存在**而非 `manifest.json` 文件存在 | low | 改为 `fileManager.fileExists(atPath: url.appendingPathComponent("manifest.json").path)`，与 commit message 语义对齐（1 行） |
| `mailagent.snoozeReason` fork 端不区分 UI 文案 | low | `MailAgentSessionView` 完成态读 `hookMetadata["mailagent.snoozeReason"]` 显示 "已暂存 X" |
| brand 5-key 缺失 logger.warning（降级静默） | low | `HookSocketServer.swift:830 case .mail` else 分支加 telemetry |
| reconnect queue maxlen 20 上限（plugin 端已加优先级保护，但绝对值仍可调） | low | 视实际丢消息率决定是否提高 maxlen |
| AIDraftStream fork 端走 fallbackLayout（chunk 不显示） | low（设计可接受） | expand 态拼接 `mailagent.draftChunkText` 显示流式动画 |
| 完整 DESIGN.md §7 per-mail collapsed dock | — | Phase 4 候选（见 §8.5），等用户用 P0 后真实反馈再决定 |

### 8.5 未来 Phase 4+ 候选（路径 B 后续）

若用户体验路径 A 后仍要 DESIGN.md §7 完整 per-mail collapsed dock：
- 新建 `MailRestingIconDock.swift`（22×22 icons + 6px gap + cap 4 + `+N` chip）
- `SessionState.acknowledgedAt` 新字段 + TTL 30min + MailCompleted 双源清除
- `closedLeadingWidth` **仅 mail brand 用户** 动态化（必须用 feature flag，否则破坏 base behavior — critic MAJOR #5 警告）
- plugin 端 `mailagent.restingPriority` int rank 单一来源（消除 fork 硬编码 scenario→priority 映射）

---

*Phase 3 P0 ship 总结由 Claude Opus 4.7 (1M context) 撰写，2026-05-26。基于 3 路 opus reviewer 交叉验证 + executor/verifier 双轨施工 + xcodebuild SUCCEEDED + 260/260 pytest pass + APPROVE 判决。所有 9 个 commits 已 atomic ship，未 push（push 决定权保留给用户）。*
