# Island-Sprint 1 任务交接

> **当前任务**：Island-Sprint 1 — fork ping-island + 加 `.mail` brand
> **预计工作量**：**1.5-2 天 Swift**（2026-05-17 fork-session 实测后再调，比 REVIEW-LOG H-10 估的 2-3 天再省 —— 不改 IslandOpenedContentView，详 ISLAND-PLUGIN.md §2.0 / §2.5）
> **依赖**：无。与 MailAgent frontend Sprint 0 完全并行，Day 1 可起。
> **本文档**：手把手把 Sprint 1 跑完的 checklist + 验证标准。
> **关键修正**：实际改动是 **8 个文件**（不是 6 个；多了 `SessionProvider.swift` + `HookSocketServer.swift` 的私有 `BridgeProvider` enum），且 **§2.5 spec 路由 diff 错位 → Sprint 1 不动 `IslandOpenedContentView.swift`**。详 [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2.0 实测修正记录（含 H-A/B/C/D/E 5 条 spec 错位）。

---

## 0. 前置确认（5 分钟）

```bash
# 1. 仓库状态
cd ~/Documents/ping-island
git status                          # 应该 clean
git remote -v                       # 应显示 origin = ChenyqThu/ping-island
git log --oneline -3                # 看最近 commit

# 2. Xcode 工具链
xcode-select -p                     # 应有路径
xcodebuild -version                 # Xcode 15+

# 3. 关键文件存在（2026-05-17 实测修正路径）
ls Prototype/Sources/IslandShared/Models.swift                  # AgentProvider enum（§2.1）
ls PingIsland/Models/SessionProvider.swift                      # SessionProvider enum（§2.1b，spec 漏列）
ls PingIsland/Models/ClientProfile.swift                        # SessionClientBrand + registry（§2.2 + §2.3）
ls PingIsland/UI/Views/IslandOpenedContentView.swift            # ⚠️ Sprint 1 不动（§2.5 spec 路由错位）
ls PingIsland/UI/Views/SessionHoverPreviewView.swift            # generic HoverSessionCard 在这（mail 实际渲染入口）
ls PingIsland/Assets.xcassets/                                  # mascot 资源加这里（命名 *Logo.imageset，§2.4）
```

如果任何一项失败，**先解决再继续**（不要硬上）。

---

## 1. Sprint 1 任务 checklist（按顺序做）

来源：[`PROJECT-PLAN.md`](./PROJECT-PLAN.md) §3 Island-Sprint 1，结合 [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2 详细 diff。

### 1.1 仓库准备

- [ ] **加 upstream remote**（便于后续 rebase）
  ```bash
  cd ~/Documents/ping-island
  git remote add upstream https://github.com/erha19/ping-island.git
  git fetch upstream
  git remote -v   # 验证两个 remote 都在
  ```
- [ ] **建工作分支**
  ```bash
  git checkout -b feat/mail-brand
  ```

### 1.2 Swift 改动（authoritative diff 在 [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2，2026-05-17 实测修正后）

**8 个文件 ~150-300 行 diff**（spec 原 6 个；加 SessionProvider + HookSocketServer 内 private BridgeProvider；IslandOpenedContentView 退出 Sprint 1）：

- [ ] **`Prototype/Sources/IslandShared/Models.swift`** — `AgentProvider` enum 加 `case mail`（[`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2.1）
- [ ] **`PingIsland/Models/SessionProvider.swift`** — `SessionProvider` enum 加 `case mail` + `displayName` switch 补 `.mail → "MailAgent"`（§2.1b，**spec 原漏，实测必加**）
- [ ] **`PingIsland/Services/Hooks/HookSocketServer.swift`** — 内部 `private enum BridgeProvider` 加 `case mail`（§2.1c，**wire 解码真入口；spec 原漏，smoke test 后才暴露**）+ 同文件 2 处依赖 switch（line 780 SessionClientKind / line 1042 sessionProvider extension）
- [ ] **`PingIsland/Models/ClientProfile.swift`** §1 — `SessionClientBrand` 加 `case mail`（§2.2）
- [ ] **`PingIsland/Models/ClientProfile.swift`** §2 — `ClientProfileRegistry.managedHookProfiles` 数组末尾（line ~547+）append `ManagedHookClientProfile(id: "mailagent", brand: .mail, …)`（§2.3，**位置实测在 ClientProfile.swift 不在 HookInstaller.swift**）
- [ ] **Mascot 资源** — `PingIsland/Assets.xcassets/` 加 4 个 `.imageset/`：`MailLogo` + `MailMascotWork` + `MailMascotPersonal` + `MailMascotDev`（§2.4，**PascalCase 跟仓内惯例 *Logo 一致**）
- [ ] **`PingIsland/UI/Views/MailAgentSessionView.swift`**（新文件，骨架版）— 4 字段 subject / senderName / priority chip / aiAction label + 预留 `openUrl: String?`，SwiftUI ~80 行（§2.5，REVIEW-LOG H-10 契约，**Sprint 1 建文件但不路由**）
- [ ] **`SessionLauncher.swift`** — 不动（§2.8，邮件无 "启动 session" 语义；2026-05-17 review 确认）
- [ ] **`IslandOpenedContentView.swift`** — ⚠️ **不动**（§2.5 spec diff 错位 —— `switch route` 不是 `switch provider`；mail event 实际走 `.attentionNotification` / `.hoverDashboard` / `.sessionList` 由 generic `HoverSessionCard` 渲染。MailAgentSessionView 真实接入点等 Sprint 4 联调决定）

### 1.3 编译 + 本地验证

- [ ] **xcodebuild 通过**
  ```bash
  cd ~/Documents/ping-island
  xcodebuild -scheme PingIsland -configuration Debug build 2>&1 | tail -20
  ```
- [ ] **本地装 .app**（手动 Run from Xcode 或 Product → Archive）
- [ ] **socket 手测 .mail brand 识别**
  ```bash
  # 用 nc 手发一个最小 envelope，验证 ping-island 能识别 .mail 并显示
  echo '{"provider":"mail","brand":"mail","sessionId":"test-1","title":"Test email","subtitle":"From: alice@example.com","phase":"phase1_full"}' | nc -U /tmp/island.sock
  ```
  预期：ping-island 刘海展开一次，显示 MailAgent mascot + "Test email" 标题。
- [ ] **MailAgent profile 在 Settings UI 出现**（`PingIsland.app` → Settings → Clients 列表里应能看到 "MailAgent"）

---

## 2. Sprint 1 完工 checklist

来源：[`PROJECT-PLAN.md`](./PROJECT-PLAN.md) §3 末尾的 "Island ship checklist"（Sprint 1 部分）+ [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2 末尾。

- ✅ `xcodebuild -scheme PingIsland build` 通过，零 warning（fork 内）
- ✅ `.mail` brand 在 envelope decode 后能正确路由到 MailAgent profile
- ✅ Mascot 资源在 Assets.xcassets 注册，编译进 .app bundle
- ✅ `MailAgentSessionView.swift` 至少骨架可渲染（subject / sender 字段不糊）
- ✅ Settings 里 MailAgent profile alwaysVisibleInSettings 生效
- ✅ 本地装 .app + `nc -U /tmp/island.sock` 手测能看到 MailAgent envelope 上岛
- ✅ git diff 集中在 enum + ClientProfile + 资源 + 新文件，**没有改业务逻辑**（rebase 友好）

---

## 3. 退出 Sprint 1，进 Sprint 2

Sprint 1 完工后：
- [ ] commit + push 到 `feat/mail-brand` 分支
- [ ] **不 merge 到 main**（等 Sprint 5 polish + 月度 rebase upstream 演练完）
- [ ] 通知 MailAgent 主仓的 Claude session 起 **Island-Sprint 2**（Python plugin 在 `MailAgent/src/notify/` 下，4 个文件）
- [ ] Sprint 2 任务清单见 [`PROJECT-PLAN.md`](./PROJECT-PLAN.md) §3 Island-Sprint 2

> **重要**：Sprint 2-3 在 MailAgent **主仓**做，不在本仓。本仓只在 Sprint 4 联调时回来加 ipcMain 转发（§4 + [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §8）。

---

## 4. 常见坑（已被 review 抓出）

| 坑 | 来源 | 怎么避 |
|---|---|---|
| Mail.app 用 URL 标识消息不是整数 id | REVIEW-LOG **H-12** | 跳转协议必须 `open location "message://<message-id>"`，Sprint 2/3 Python 端 emit envelope 时 `mailagent.openUrl` 字段就要这么填。Swift 端 Sprint 1 暂不实施跳转，但 `MailAgentSessionView` 字段定义要预留 `openUrl: String?` |
| MailAgentSessionView 想跳过 → Sprint 4 联调时邮件字段糊掉 | REVIEW-LOG **H-10** | Sprint 1 至少做骨架，subject + sender 两个 label 是底线（即使 Sprint 1 不路由） |
| Sprint 1 改 SessionLauncher 引入退化 | REVIEW-LOG H-10 + ISLAND-PLUGIN §2.8 | 默认不动，要动先确认邮件 vs Claude session 的 intent 差异 |
| 月度 rebase upstream 冲突大 | ISLAND-PLUGIN §0 | 改动只能在 enum/资源/profile 文件，**业务逻辑零修改** |
| Mascot 资源命名不一致 → fork 内多 brand 混乱 | ISLAND-PLUGIN §2.4 (2026-05-17 实测修正) | 跟仓内 18 个 `*Logo.imageset` 惯例对齐：`MailLogo` (profile) + `MailMascot{Work,Personal,Dev}` (view)。**不**用 `mascot-mail-*` |
| **照搬 §2.5 spec diff 改 IslandOpenedContentView** | ISLAND-PLUGIN §2.5 (2026-05-17 review) | spec 写的 `switch session.provider` diff 在实际文件里没对应代码 (实际是 `switch route` 五分支)。Sprint 1 **完全不动 IslandOpenedContentView**；mail event 走 generic `HoverSessionCard` 渲染，Sprint 4 联调再决定 MailAgentSessionView 接入点 |
| **只加 AgentProvider.mail 漏 SessionProvider.mail / BridgeProvider.mail** | ISLAND-PLUGIN §2.1b / §2.1c (2026-05-17 review) | 仓内有 **4 个** provider/brand enum：`AgentProvider`(outbound wire, BridgeEnvelope 出) / `SessionProvider`(session/UI) / `SessionClientBrand`(profile) / `BridgeProvider`(**inbound wire 解码**, HookSocketServer 内 private)，**全部** 都要加。前 3 个 spec 原漏 1 个（SessionProvider），第 4 个 spec 完全没提，build 不报错但 smoke test 时 socket 收到 `"provider":"mail"` 会 silent reject |
| **ClientProfile registry 找错文件** | ISLAND-PLUGIN §2.3 (2026-05-17 review) | spec 原说 "HookInstaller.swift 或同级"，**错**。实际在 `PingIsland/Models/ClientProfile.swift:547 ClientProfileRegistry.managedHookProfiles` 数组 |

---

## 5. 卡住怎么办

| 情况 | 行动 |
|---|---|
| Xcode 编译错误 | 先看是不是漏改了 enum 的 `CaseIterable` switch 穷举（Swift 编译会硬报）；其次看 ClientProfile registry 里 brand 字段类型 |
| `nc -U /tmp/island.sock` 没反应 | 先 `ls -la /tmp/island.sock` 看 socket 是否存在；其次确认 .app 已启动；最后看 ping-island 日志（`Console.app` → "PingIsland"） |
| envelope schema 不确定 | 看 [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §3.2 完整 BridgeEnvelope JSON spec |
| 跨仓信息缺口（要查 MailAgent 主仓的 Python / CLI 行为） | 读 [`MAILAGENT-CLAUDE.md`](./MAILAGENT-CLAUDE.md) 或直接读 `~/Documents/MailAgent/` 源码 |
| 文档里有矛盾 | 优先级：[`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) > [`PROJECT-PLAN.md`](./PROJECT-PLAN.md) > [`REVIEW-LOG.md`](./REVIEW-LOG.md) 决议 > 其他。回填修复到主仓 `~/Documents/MailAgent/frontend/` |

---

完工后回报：commit hash + xcodebuild 输出 tail + `nc -U` 手测截图。
