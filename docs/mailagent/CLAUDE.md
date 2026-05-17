# CLAUDE.md — ping-island fork 内的工作纪律

> 这份是 **MailAgent 项目在 ping-island fork 内** 的 Claude Code 指引。
> 不是上游 ping-island 自带的 `AGENTS.md`（那份是给 ping-island 维护者看的）。
>
> 两者关系：
> - **上游 `AGENTS.md`**：怎么改 ping-island 本身（业务逻辑、Hook、Codex/Claude 集成）→ **不归你管**
> - **本 `docs/mailagent/CLAUDE.md`**：怎么把 MailAgent `.mail` brand 加进 fork → **你的工作**

---

## 1. 工作边界（红线）

### ✅ 可以动（2026-05-17 fork-session 实测修正路径）

- `Prototype/Sources/IslandShared/Models.swift` — `AgentProvider` enum 加 `case mail`（§2.1）
- `PingIsland/Models/SessionProvider.swift` — `SessionProvider` enum 加 `case mail` + `displayName` 补 `.mail → "MailAgent"`（§2.1b，**spec 原漏**）
- `PingIsland/Models/ClientProfile.swift` §1 — `SessionClientBrand` 加 `case mail`（§2.2）
- `PingIsland/Models/ClientProfile.swift` §2 — `ClientProfileRegistry.managedHookProfiles`（line ~547+）数组末尾 append MailAgent profile entry（§2.3，**registry 在这里，不在 HookInstaller.swift**）
- `PingIsland/Assets.xcassets/` — 加 `MailLogo` + `MailMascot{Work,Personal,Dev}` 4 个 `.imageset`（§2.4，**PascalCase 跟 18 个 `*Logo` 惯例对齐，不用 `mascot-mail-*`**）
- **新建** `PingIsland/UI/Views/MailAgentSessionView.swift`（骨架 ~80 行，Sprint 1 不路由）

### ⚠️ 谨慎动（动之前先停下来对齐）

- `Prototype/Sources/IslandBridge/` — envelope decoder，原则上只扩 `.mail` 不重写
- `SessionLauncher.swift` — [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2.8 决策树先过一遍
- 编译时 `HoverPreviewStyle` / `MascotView` 等其它视图的 `switch session.provider` 可能要补 `.mail` case（Phase 1D 编译输出会暴露）—— 纯加 case，零业务改动，OK

### ❌ Sprint 1 不动（2026-05-17 review 拍板）

- `PingIsland/UI/Views/IslandOpenedContentView.swift` —— ISLAND-PLUGIN §2.5 spec diff 错位（`switch route` 不是 `switch provider`）。mail event 实际走 `.attentionNotification` / `.hoverDashboard` / `.sessionList` 由 generic `HoverSessionCard` 渲染，Sprint 4 联调再决定 MailAgentSessionView 真实接入点

### ❌ 绝对不动

- 上游 `README.md` / `README.zh-CN.md` / `AGENTS.md` / `NOTICE` / `LICENSE.md` — **fork 边界不污染**
- 上游 `docs/*.md`（codex-hook-debugging / homebrew-cask-release / mac-app-store-submission / privacy-policy / sparkle-release / telemetry）— 那是上游的发布文档，rebase 时不要冲突
- `PingIsland.xcodeproj/` 大改 — 加文件 OK，重排 Build Phases 不 OK
- `packaging/` / `releases/` — Sprint 5 distribution 阶段才动
- 上游已有的 Hook / Codex / Claude / Gemini / Kimi / OpenCode 业务逻辑 — 一个字符也不要改

**判断标准**：每一行 diff 都能追溯到 "为了让 `.mail` brand 工作"。做不到 → 这一行不该存在。

---

## 2. Rebase 友好（核心约束）

**目标**：月度 `git rebase upstream/main` 5 分钟内完成，零业务冲突。

为此：

1. **改动集中**：enum、ClientProfile、Assets、新文件 `MailAgentSessionView.swift` — 就这 4-5 个文件，diff 集中
2. **不改业务逻辑**：所有业务（事件 dispatch、AppleScript 跳转、BridgeResponse 处理、snooze）都在 **MailAgent 主仓** `~/Documents/MailAgent/src/notify/` 下，不在本 fork
3. **不重排上游代码**：不要 "顺手优化"、不要重命名、不要调 import 顺序
4. **提交粒度小**：每个 Sprint 1 任务一个 commit，commit message 前缀 `feat(mail-brand):` 便于 rebase 时识别

---

## 3. 文档优先级（信息冲突时怎么办）

1. [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2 (fork 改动清单) — **authoritative**
2. [`REVIEW-LOG.md`](./REVIEW-LOG.md) H-09 / H-10 / H-12 / H-16 / H-17 + §5.5 codex review 决议 — **覆盖 §1，最新口径**
3. [`PROJECT-PLAN.md`](./PROJECT-PLAN.md) §3 Sprint 拆分 — 任务边界
4. [`DESIGN.md`](./DESIGN.md) §7 + §16 + §17 — 视觉 / i18n / 主题约定
5. 其他文档 — 背景参考

**矛盾时**：相信 REVIEW-LOG 决议（那是最近一次评审拍的板）。如果还不确定，**停下来问用户**，不要猜。

---

## 4. 沟通约定

### 你（fork 内 Claude session）跟谁配合

- **用户**：所有重大决策（要不要动 `SessionLauncher.swift`、骨架版 `MailAgentSessionView` 字段集等）必须用户确认
- **MailAgent 主仓的 Claude session**（不同窗口）：Sprint 2-3 Python plugin 由那边做，你不需要直接对接，但 envelope schema 共享 — 任何 schema 变更（哪怕加一个字段）都要写到 [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §3.2，让两边对齐
- **MailAgent frontend Sprint 0 的 Claude session**（也是不同窗口）：完全无关，零交互

### 输出格式

- 进展更新：每完成 1 个 checklist 项报一次（commit hash + 1 句话）
- 卡住：立刻说哪里卡住，**不要静默尝试**
- 完工：按 [`HANDOFF.md`](./HANDOFF.md) §2 完工 checklist 逐项验证后总报

---

## 5. 工程纪律（沿用 MailAgent 主仓 CLAUDE.md）

来源：[`MAILAGENT-CLAUDE.md`](./MAILAGENT-CLAUDE.md) §"通用指南" 适用，**简化版**：

- 被要求做具体修改时，直接动手。不要花大量时间反复确认简单任务，**偏向行动**
- macOS 环境下 **没有 sudo**，不要尝试 sudo 命令
- 调试 Xcode build 时先看 `xcodebuild` 输出 tail，再看 Console.app 的 PingIsland 日志，最后才改代码
- 不要假设编译成功 — `xcodebuild` 必须显式跑过，看到 `** BUILD SUCCEEDED **`
- 不要"顺手优化"相邻代码 — Sprint 1 的红线（§1）就是为了 rebase 友好

---

## 6. Karpathy 编码原则（适用 Swift 端）

来源：MailAgent 主仓 OMC CLAUDE.md。

| 原则 | 在 fork 里怎么落地 |
|---|---|
| 编码前思考 | 不确定 `MailAgentSessionView` 字段就先问，不要先写一堆 SwiftUI |
| 简洁优先 | Sprint 1 骨架版就是 subject + sender + AI priority + AI action 4 个 label，**不要加 "未来可能要的" 折叠/动画/手势** |
| 精准修改 | enum 加一行 case，不要顺手把 enum 改 `enum AgentProvider: String, Codable, CaseIterable, Sendable, Hashable` 之类没人要的 |
| 目标驱动 | 把 "实现 .mail brand" 转成 "`nc -U /tmp/island.sock` 手发 envelope，能在 ping-island 看到 MailAgent mascot + subject"，写完跑这条验证 |

---

## 7. 当前任务

→ 打开 [`HANDOFF.md`](./HANDOFF.md)，按 §1 checklist 顺序执行。

不要绕到 Sprint 2/3 — 那些不在你这里。
