# MailAgent · ping-island Hybrid 集成文档

> 这个目录（`docs/mailagent/`）是 **MailAgent 项目在 ping-island fork 内的 SSoT 副本**。
> 上游 ping-island 自带的 `README.md` / `AGENTS.md` / `docs/*.md` **不在这里**，请不要混淆。
>
> **隔离原则**：所有 MailAgent 相关文档都在本目录内，fork 根目录与上游 `docs/` 一律不动 ——
> 这样月度 `git rebase upstream/main` 时本目录零冲突。
>
> **同步源**：`~/Documents/MailAgent/frontend/`（每次同步用 `cp` 全量覆盖即可，文档体系是 SSoT）。
>
> **最后同步**：2026-05-17

---

## 0. 你是新来的 Claude session — 按顺序读这 4 份就够

| # | 文件 | 时长 | 用途 |
|---|---|---|---|
| 1 | [`CLAUDE.md`](./CLAUDE.md) | 5 min | fork 内 Claude 工作纪律（动什么 / 不动什么 / rebase 友好） |
| 2 | [`HANDOFF.md`](./HANDOFF.md) | 5 min | 当前任务 = Island-Sprint 1，启动 checklist |
| 3 | [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) §2 | 15 min | 6 个 Swift 文件的具体改动清单（authoritative） |
| 4 | [`PROJECT-PLAN.md`](./PROJECT-PLAN.md) §3 | 10 min | Island-Sprint 1-5 全景 + 跟 L1 V1 Electron 的并行关系 |

读完这 4 份就可以动手。其余文档按需要查（下方 §1 索引）。

---

## 1. 文档索引

### 1.1 必读（任务背景）

| 文件 | 体量 | 说明 | 在主仓的路径 |
|---|---|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | 小 | **fork 内 Claude 工作指引**（本文档新写，非 cp） | — |
| [`HANDOFF.md`](./HANDOFF.md) | 小 | **Island-Sprint 1 任务交接**（本文档新写，非 cp） | — |
| [`ISLAND-PLUGIN.md`](./ISLAND-PLUGIN.md) | 30KB | Island Hybrid 主 spec（authoritative）| `frontend/ISLAND-PLUGIN.md` |
| [`PROJECT-PLAN.md`](./PROJECT-PLAN.md) | 29KB | L1/L2/L3 三轨 Sprint 拆分，§3 是 Island | `frontend/PROJECT-PLAN.md` |

### 1.2 设计约束（动 Swift 之前必扫）

| 文件 | 体量 | 关键章节 |
|---|---|---|
| [`DESIGN.md`](./DESIGN.md) | 75KB | **§7 Dynamic Island 视觉约定** / **§16 i18n** / **§17 主题三态** / §14 八条非协商 |
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | 23KB | §3.4 Island 数据流图（事件源 → envelope → ping-island UI） |
| [`BACKEND-INTERFACES.md`](./BACKEND-INTERFACES.md) | 26KB | MailAgent 主仓的 IPC / webhook / CLI 契约（Sprint 2 Python plugin 要对齐这些） |

### 1.3 评审记录（避免踩坑）

| 文件 | 体量 | 关键 issue |
|---|---|---|
| [`REVIEW-LOG.md`](./REVIEW-LOG.md) | 45KB | **H-09 / H-10 / H-12 / H-16 / H-17** 都是 Island 相关，§5.5 是 codex Island Bridge review |

**Sprint 1 必看的 review 决议**：
- **H-10**：Sprint 1 工作量从 1.5-2 天调到 **2-3 天**（含 `MailAgentSessionView.swift` 至少骨架）
- **H-12**：Sprint 2/3 的 AppleScript 跳转必须用 `open location "message://<message-id>"` URL scheme，**不是** `tell app "Mail" to open message id <int>`
- **H-16 / H-17**：Sprint 2 Python plugin 必须 `socket.settimeout(3.0)` + sleep/wake 自动重连

### 1.4 上下文 / 调研历史（可选）

| 文件 | 用途 |
|---|---|
| [`FRONTEND-README.md`](./FRONTEND-README.md) | MailAgent frontend 项目总览（L1 Electron 主线），看 Island 在大图里的位置 |
| [`MAILAGENT-CLAUDE.md`](./MAILAGENT-CLAUDE.md) | MailAgent 主仓的 CLAUDE.md（v3/v4 架构、CLI、LLM agent 等）—— 写 Python plugin 时按需查 |
| [`_research-ping-island-integration.md`](./_research-ping-island-integration.md) | 2026-05 调研报告，记录"为什么走 Hybrid 不走 Full Fork / 纯 Plugin"，已归档但有决策上下文 |

---

## 2. 三轨并行关系（一眼图）

```
L1 V1 Electron      ░░░░░░░░░░░░░░░░░░░░░░░░░░  ← MailAgent/frontend/ 主线
                    └─ 当前在 Sprint 0（脚手架）

L2 Island Hybrid    ──░░░░░░░░░░░░░░░░░         ← 本仓 + MailAgent/src/notify/
                    └─ ⭐ 你在这里，从 Island-Sprint 1 起步

L3 V2 远程访问                  ────░░░░░░       ← 后续
```

- **Island-Sprint 1-3** 完全独立，Day 1 起步，与 L1 零冲突
- **Island-Sprint 4** 端到端联调依赖 L1 Sprint 5 完工
- 详见 [`PROJECT-PLAN.md`](./PROJECT-PLAN.md) §3 + §6 时间轴

---

## 3. 工作区分（两个 git 仓库，物理隔离）

| 仓库 | 路径 | 语言 | 改什么 |
|---|---|---|---|
| **本仓 ping-island fork** | `~/Documents/ping-island/` | Swift 6.1 / SwiftUI | enum + ClientProfile + Mascot 资源 + `MailAgentSessionView.swift` |
| **MailAgent 主仓** | `~/Documents/MailAgent/` | Python | `src/notify/ping_island.py` 等 4 文件 + 事件挂钩 |

**Sprint 1 你只动本仓**。Sprint 2/3/4/5 跨两仓（但 Python 部分由 MailAgent 主仓里的 Claude session 做，本 session 不需要关心）。

---

## 4. 同步策略

**主仓 frontend/ 文档更新时，本目录怎么同步？**

```bash
FRONTEND=~/Documents/MailAgent/frontend
DEST=~/Documents/ping-island/docs/mailagent

# 全量覆盖（SSoT 原则，不做增量 diff）
cp "$FRONTEND/ISLAND-PLUGIN.md"        "$DEST/ISLAND-PLUGIN.md"
cp "$FRONTEND/PROJECT-PLAN.md"         "$DEST/PROJECT-PLAN.md"
cp "$FRONTEND/DESIGN.md"               "$DEST/DESIGN.md"
cp "$FRONTEND/ARCHITECTURE.md"         "$DEST/ARCHITECTURE.md"
cp "$FRONTEND/BACKEND-INTERFACES.md"   "$DEST/BACKEND-INTERFACES.md"
cp "$FRONTEND/REVIEW-LOG.md"           "$DEST/REVIEW-LOG.md"
cp "$FRONTEND/README.md"               "$DEST/FRONTEND-README.md"

# README.md / HANDOFF.md / CLAUDE.md 是本目录原创，不需要从主仓同步
```

**反向**：如果在 fork 里发现了文档 bug / 信息缺口，**回填到主仓** `~/Documents/MailAgent/frontend/` 而不是只改本副本（避免文档 drift）。

---

## 5. 关键决策记录（已拍板，不要重新讨论）

| 决策 | 来源 | 内容 |
|---|---|---|
| 走 Hybrid，不走 Full Fork / 纯 Plugin | `_research-ping-island-integration.md` §2 + `ISLAND-PLUGIN.md` §1 | Swift 改动 < 200 行，业务逻辑全在 MailAgent 仓 |
| brand 用 `.mail` | `ISLAND-PLUGIN.md` §2.1 / §2.2 | 不复用 `.kimi` / `.gemini` |
| fail-open（不告警） | `REVIEW-LOG.md` §A-09 | ping-island 没装/没跑时 mail-sync 不受影响、不告警 |
| 月度 rebase upstream | `ISLAND-PLUGIN.md` §0 + §6 | fork 内只动 enum/资源/profile，业务逻辑零修改 |
| 跳转协议用 `message://` URL scheme | `REVIEW-LOG.md` H-12 | **不是** `tell app "Mail"`（错的） |
| Socket 必须 `settimeout(3.0)` + 重连 | `REVIEW-LOG.md` H-16 / H-17 | Sprint 2 Python plugin 必做 |

---

下一步：打开 [`HANDOFF.md`](./HANDOFF.md)。
