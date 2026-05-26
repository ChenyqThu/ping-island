import SwiftUI

/// MailAgent session detail view — Phase 1 (PRD §5.1 / T3 routing decision).
///
/// 渲染分支由 `session.hookMetadata["mailagent.scenario"]` 决定 (mockup-dynamic-island.html v4 §2)：
/// - `MailReceivedUrgent` / `LLMReviewedUrgent`  → Scene 3 task acknowledge (mascot + crit pip + AI summary + buttons)
/// - `AIDraftReady`                              → Scene 2 input required (draft preview card)
/// - `MailCompleted`                             → Scene 4 task complete (绿副标 click to jump)
/// - `SyncFailed`                                → error scene (devbot + fail pip + error)
/// - `DeadLetterAccum`                           → aggregate chip
/// - else / scenario 缺失                         → fallback (4 字段 minimal card)
///
/// **数据来源**：`session.hookMetadata`，来自 HookEvent.metadata，来自 envelope.metadata
/// (Plugin `src/notify/island_envelope.py` 端 `mailagent.*` namespace)。
///
/// **接入点**：`SessionAttentionNotificationView` (T3 路由决策 §3.2 接入点 A)，
/// `SessionHoverDashboardView` / `SessionListView` 接入点 B/C 待下次 session。
///
/// **button click**：当前是视觉占位 (no-op + log)。下次 session 接 `HookSocketServer.shared.respondToIntervention`
/// + `SessionStore.shared.process(.interventionResolved(...))`，参考 `SessionMonitor.swift:183-195`。
struct MailAgentSessionView: View {
    let session: SessionState
    let sessionMonitor: SessionMonitor
    var density: HoverPreviewDensity = .regular
    var onActionCompleted: () -> Void = {}

    var body: some View {
        Group {
            switch scenario {
            case "MailReceivedUrgent", "LLMReviewedUrgent":
                attentionLayout
            case "AIDraftReady":
                draftLayout
            case "MailCompleted":
                completedLayout
            case "SyncFailed":
                errorLayout
            case "DeadLetterAccum":
                deadLetterLayout
            default:
                fallbackLayout
            }
        }
        .padding(.horizontal, density == .detachedCompact ? 12 : 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Metadata accessors

    private var scenario: String { meta("mailagent.scenario") }
    private var subject: String { meta("mailagent.subject") }
    private var senderName: String { meta("mailagent.senderName") }
    private var sender: String { meta("mailagent.sender") }
    private var aiSummary: String { meta("mailagent.aiSummary") }
    private var aiAction: String { meta("mailagent.aiAction") }
    private var aiPriority: String { meta("mailagent.aiPriority") }
    private var mailbox: String { meta("mailagent.mailbox") }
    private var attachCount: Int { Int(meta("mailagent.attachCount")) ?? 0 }
    private var mascotId: String { metaWithDefault("mailagent.mascot", "default") }
    private var accentKey: String { metaWithDefault("mailagent.accent", "coral") }
    private var errorText: String { meta("mailagent.error") }
    private var deadLetterCount: Int { Int(meta("mailagent.deadLetterCount")) ?? 0 }

    private func meta(_ key: String) -> String {
        session.hookMetadata[key] ?? ""
    }

    private func metaWithDefault(_ key: String, _ fallback: String) -> String {
        let v = session.hookMetadata[key] ?? ""
        return v.isEmpty ? fallback : v
    }

    // MARK: - Scene 3: Task acknowledge (urgent mail / LLM reviewed urgent)

    private var attentionLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            mailHeader(showSender: true)
            if !aiSummary.isEmpty {
                Text(aiSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            chipsRow
            interventionButtonRow
        }
    }

    // MARK: - Scene 2: Input required (AI draft ready)

    private var draftLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            mailHeader(showSender: true)
            draftPreviewCard
            interventionButtonRow
        }
    }

    private var draftPreviewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DRAFT REPLY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(accentColor)
                .kerning(0.6)
            Text(aiSummary.isEmpty ? subject : aiSummary)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accentColor.opacity(0.30), lineWidth: 1)
                )
        )
    }

    // MARK: - Scene 4: Task complete (绿副标 click to jump)

    private var completedLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    mascotView
                    pip(color: Color(red: 0.365, green: 0.729, blue: 0.549), pulses: false)
                        .offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    eyebrowLine(suffix: "已同步")
                    Text(subject.isEmpty ? "(no subject)" : subject)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text("Done — click to jump")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(red: 0.365, green: 0.729, blue: 0.549))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - SyncFailed (DevBot + fail pip + error)

    private var errorLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    mascotView
                    pip(color: Color(red: 0.890, green: 0.384, blue: 0.384), pulses: false)
                        .offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    eyebrowLine(suffix: "sync error")
                    Text(subject.isEmpty ? "邮件同步失败" : subject)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - DeadLetterAccum aggregate

    private var deadLetterLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                mascotView
                VStack(alignment: .leading, spacing: 2) {
                    Text("MailAgent · dead letter")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(red: 0.479, green: 0.498, blue: 0.541))
                    Text("\(deadLetterCount) 封邮件累积死信")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("查看 mailagent admin dead-letter list")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Fallback (compact 4 字段)

    private var fallbackLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            mailHeader(showSender: false)
            if !aiSummary.isEmpty {
                Text(aiSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Shared header (mascot + eyebrow + title + sender)

    private func mailHeader(showSender: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                mascotView
                if let priorityPip = priorityPipColor {
                    pip(color: priorityPip, pulses: aiPriority.contains("紧急"))
                        .offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                eyebrowLine(suffix: nil)
                Text(subject.isEmpty ? "(no subject)" : subject)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if showSender, !senderName.isEmpty || !sender.isEmpty {
                    Text(senderLine)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func eyebrowLine(suffix: String?) -> some View {
        var parts: [String] = ["MailAgent"]
        if !mailbox.isEmpty {
            parts.append(mailbox)
        }
        if let suffix, !suffix.isEmpty {
            parts.append(suffix)
        }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(Color(red: 0.479, green: 0.498, blue: 0.541))
            .lineLimit(1)
    }

    private var senderLine: String {
        let name = senderName.isEmpty ? "" : senderName
        let addr = sender.isEmpty ? "" : sender
        if !name.isEmpty, !addr.isEmpty {
            return "from: \(name) · \(addr)"
        }
        return "from: \(name.isEmpty ? addr : name)"
    }

    // MARK: - Mascot (T6: 真 pixel-art PNG imageset, NEAREST interpolation 保锐利)

    @ViewBuilder
    private var mascotView: some View {
        Image(mascotAssetName)
            .resizable()
            .interpolation(.none)  // 保留 pixel-art 锐利, 禁止 SwiftUI 默认抗锯齿
            .scaledToFit()
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(mascotBackgroundTint)
            )
    }

    /// MailAgent mascot asset name → Asset Catalog imageset 目录名 (Sprint 1 fork 67c8fd9 ship,
    /// T6 (commit pending) 内置真 pixel-art PNG @1x/@2x/@3x 替换 CSS 占位).
    private var mascotAssetName: String {
        switch mascotId {
        case "work":     return "MailMascotWork"
        case "personal": return "MailMascotPersonal"
        case "dev":      return "MailMascotDev"
        default:         return "MailLogo"
        }
    }

    /// Mascot 背景染色块 (mockup §3 pi-avatar-* tint, 让 mascot 在灵动岛黑底上跳出来).
    private var mascotBackgroundTint: Color {
        switch mascotId {
        case "work":     return Color(red: 0.165, green: 0.122, blue: 0.078)
        case "personal": return Color(red: 0.122, green: 0.125, blue: 0.141)
        case "dev":      return Color(red: 0.071, green: 0.125, blue: 0.090)
        default:         return accentColor.opacity(0.14)
        }
    }

    // MARK: - Chips + buttons

    private var chipsRow: some View {
        HStack(spacing: 6) {
            if !aiPriority.isEmpty {
                priorityChip
            }
            if !aiAction.isEmpty {
                actionChip
            }
            if attachCount > 0 {
                attachChip
            }
            Spacer(minLength: 0)
        }
    }

    private var priorityChip: some View {
        Text(aiPriority)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(priorityPipColor ?? accentColor.opacity(0.85))
            )
    }

    private var actionChip: some View {
        Text(aiAction)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private var attachChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "paperclip")
                .font(.system(size: 9, weight: .semibold))
            Text("\(attachCount)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.white.opacity(0.55))
    }

    /// Intervention buttons row — 占位实现 (visual only, T4 next iteration wire to
    /// HookSocketServer.shared.respondToIntervention + SessionStore.interventionResolved).
    private var interventionButtonRow: some View {
        let opts = session.intervention?.options ?? []
        return HStack(spacing: 8) {
            ForEach(Array(opts.prefix(3))) { opt in
                interventionButton(opt, isPrimary: opt.id == opts.first?.id)
            }
            Spacer(minLength: 0)
        }
    }

    private func interventionButton(_ opt: SessionInterventionOption, isPrimary: Bool) -> some View {
        Button {
            // Phase 1·T7 follow-up (button real action wire, 2026-05-25):
            // 1. HookSocketServer.respondToIntervention 反向 socket response 回 plugin
            //    → plugin `_extract_choice({"decision":{"answer":{"choice": opt.id}}})` 拿 option id
            //    → `island_response.handle_response` 触发对应业务 handler
            //      (open_mail / open_notion / create_draft / mark_done / snooze_1h)
            // 2. 本地 SessionStore.interventionResolved 让 view dismiss
            // toolUseId 来源: plugin envelope.py `to_wire_dict` 在 metadata 写 `tool_use_id =
            // "bridge-<envelope_id>"`, 跟 fork HookSocketServer line 1791 fallback 一致.
            // fallback 用 sessionId (旧 envelope 没含 tool_use_id 兜底, 至少不 crash).
            let sessionId = session.sessionId
            let optionId = opt.id
            let toolUseId = session.hookMetadata["tool_use_id"] ?? sessionId
            HookSocketServer.shared.respondToIntervention(
                toolUseId: toolUseId,
                decision: "answer",
                updatedInput: ["choice": optionId]
            )
            Task {
                await SessionStore.shared.process(
                    .interventionResolved(
                        sessionId: sessionId,
                        nextPhase: .ended,
                        submittedAnswers: [optionId: ["1"]]
                    )
                )
                await MainActor.run {
                    onActionCompleted()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(opt.title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPrimary ? Color.white : Color(red: 0.122, green: 0.141, blue: 0.169))
            )
            .foregroundColor(isPrimary ? .black : .white)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isPrimary ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pip / color helpers

    private var priorityPipColor: Color? {
        if aiPriority.contains("紧急") {
            return Color(red: 0.898, green: 0.388, blue: 0.310)  // crit
        }
        if aiPriority.contains("重要") {
            return Color(red: 0.910, green: 0.608, blue: 0.290)  // urg
        }
        if aiPriority.contains("一般") {
            return Color(red: 0.831, green: 0.647, blue: 0.239)  // impt
        }
        return nil
    }

    private func pip(color: Color, pulses: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(
                Circle().stroke(Color.black, lineWidth: 2)
            )
    }

    /// MailAgent accent 主题色（DESIGN.md §2.7 六色板）→ SwiftUI Color。
    /// 由 plugin envelope.metadata.mailagent.accent 透传（Phase 1·T5 broadcast 已 ready）。
    private var accentColor: Color {
        switch accentKey {
        case "cobalt":
            return Color(red: 0.290, green: 0.471, blue: 0.898)
        case "teal":
            return Color(red: 0.176, green: 0.710, blue: 0.651)
        case "rose":
            return Color(red: 0.859, green: 0.357, blue: 0.486)
        case "slate":
            return Color(red: 0.494, green: 0.525, blue: 0.580)
        case "olive":
            return Color(red: 0.612, green: 0.647, blue: 0.322)
        default:
            return Color(red: 0.898, green: 0.396, blue: 0.294)  // coral
        }
    }
}
