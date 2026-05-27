import SwiftUI

/// MailAgent session detail view — Phase 1 (PRD §5.1 / T3 routing decision).
///
/// 渲染分支由 `session.hookMetadata["mailagent.scenario"]` 决定 (mockup-dynamic-island.html v4 §2)：
/// - `MailReceivedUrgent` / `LLMReviewedUrgent`  → Scene 3 task acknowledge (mascot + crit pip + AI summary + buttons)
/// - `AIDraftReady`                              → Scene 2 input required (draft preview card)
/// - `MailCompleted`                             → Scene 4 task complete (绿副标 click to jump)
/// - `SyncFailed`                                → error scene (devbot + fail pip + error)
/// - `DeadLetterAccum`                           → aggregate chip
/// - `DailyDigest`                               → 今日总结 (counts chips + summary + bulk intervention buttons)
/// - else / scenario 缺失                         → fallback (4 字段 minimal card)
///
/// **数据来源**：`session.hookMetadata`，来自 HookEvent.metadata，来自 envelope.metadata
/// (Plugin `src/notify/island_envelope.py` 端 `mailagent.*` namespace)。
///
/// **接入点**：`SessionAttentionNotificationView` (T3 路由决策 §3.2 接入点 A)，
/// `SessionHoverDashboardView` / `SessionListView` 接入点 B/C 待下次 session。
///
/// **button click** (Phase 1·T7 follow-up + Phase 2·T2.2 后):
/// 1. `HookSocketServer.shared.respondToIntervention(toolUseId:, decision:"answer",
///    updatedInput:["choice": opt.id])` — sendHookResponse 写 BridgeResponse JSON
///    `{"decision":{"answer":{"choice": ...}}}` 回 plugin → `island_response.handle_response`
///    触发 17 个 action handler (Phase 1 静态 5 + Phase 2 dynamic 12) 之一.
/// 2. `SessionStore.shared.process(.interventionResolved(...))` 让 view dismiss.
///
/// option.detail 字段渲染待 Phase 2·T2.5 跟进 (button 高度 30→44, 显示 title + detail 二行).
struct MailAgentSessionView: View {
    let session: SessionState
    let sessionMonitor: SessionMonitor
    var density: HoverPreviewDensity = .regular
    var onActionCompleted: () -> Void = {}

    /// 渲染分支枚举 (scenario → layout 的单一真源)。`body` 与单测 (Phase 3·Polish-3)
    /// 都走 `layoutKind(forScenario:)`, 避免 switch 在视图私有代码里无法独立验证。
    enum LayoutKind: Equatable {
        case attention      // MailReceivedUrgent / LLMReviewedUrgent
        case draft          // AIDraftReady
        case completed      // MailCompleted
        case error          // SyncFailed
        case deadLetter     // DeadLetterAccum
        case digest         // DailyDigest
        case acked          // ActionAcked (Phase 3·Polish-1)
        case fallback       // else / scenario 缺失
    }

    /// scenario 字符串 → LayoutKind。纯函数, 无 SwiftUI 依赖, 便于路由单测。
    static func layoutKind(forScenario scenario: String) -> LayoutKind {
        switch scenario {
        case "MailReceivedUrgent", "LLMReviewedUrgent": return .attention
        case "AIDraftReady":                            return .draft
        case "MailCompleted":                           return .completed
        case "SyncFailed":                              return .error
        case "DeadLetterAccum":                         return .deadLetter
        case "DailyDigest":                             return .digest
        case "ActionAcked":                             return .acked
        default:                                        return .fallback
        }
    }

    var body: some View {
        Group {
            switch Self.layoutKind(forScenario: scenario) {
            case .attention:
                attentionLayout
            case .draft:
                draftLayout
            case .completed:
                completedLayout
            case .error:
                errorLayout
            case .deadLetter:
                deadLetterLayout
            case .digest:
                digestLayout
            case .acked:
                ackedLayout
            case .fallback:
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
    private var digestUnread: Int { Int(meta("mailagent.digestUnread")) ?? 0 }
    private var digestUrgent: Int { Int(meta("mailagent.digestUrgent")) ?? 0 }
    private var digestHeadline: String { meta("mailagent.digestHeadline") }
    private var digestSummary: String { meta("mailagent.aiSummary") }  // 复用 aiSummary 通道
    private var actionAckedChoice: String { meta("mailagent.actionAckedChoice") }
    private var actionAckedOk: Bool { meta("mailagent.actionAckedOk") == "true" }
    private var actionAckedError: String { meta("mailagent.error") }  // 复用 error 通道 (失败时 ≤200 char)

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

    // MARK: - DailyDigest (今日总结: counts chips + summary + bulk intervention buttons)

    /// Phase 3 DailyDigest layout (plan §5 决策点 5): 头(mascot + eyebrow "今日总结" +
    /// headline) + counts chips (未读 / 紧急) + 2-4 句 summary + bulk action buttons.
    /// bulk action 复用 `interventionButtonRow` (prefix(3) + respondToIntervention 回写),
    /// 零新协议: plugin 端 `Intervention(options=[InterventionOption(id="bulk_*", ...)])` →
    /// fork 原样渲染 + click 走相同 socket 路径 (envelope.metadata.digestBulk.<id>.ids 携带 ids).
    private var digestLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                mascotView
                VStack(alignment: .leading, spacing: 2) {
                    eyebrowLine(suffix: "今日总结")
                    Text(digestHeadline.isEmpty ? "今日邮件汇总" : digestHeadline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            digestCountsRow
            if !digestSummary.isEmpty {
                Text(digestSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            interventionButtonRow
        }
    }

    private var digestCountsRow: some View {
        HStack(spacing: 6) {
            if digestUnread > 0 {
                countChip("\(digestUnread) 未读", tint: Color(red: 0.479, green: 0.498, blue: 0.541))
            }
            if digestUrgent > 0 {
                countChip("\(digestUrgent) 紧急", tint: Color(red: 0.898, green: 0.388, blue: 0.310))
            }
            Spacer(minLength: 0)
        }
    }

    /// counts chip — 照 priorityChip 风格 (实心 Capsule 染 tint, 白字).
    private func countChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.85))
            )
    }

    // MARK: - ActionAcked (button 点击后 subprocess 成功/失败反馈, plugin dispatch_action_acked)

    /// Phase 3·Polish-1: 用户点 interventionButton → plugin 跑 action subprocess →
    /// 回发 `ActionAcked` envelope (metadata.actionAckedChoice / actionAckedOk / error)。
    /// expand 态渲染 inline 卡片 (复用 completedLayout/errorLayout 视觉语言): 成功显 ✓ +
    /// "已完成" + choice 可读文案; 失败显 ✗ + error 文案。MVP 轻量反馈, 不做 toast/动画系统。
    private var ackedLayout: some View {
        let ok = actionAckedOk
        let successTint = Color(red: 0.365, green: 0.729, blue: 0.549)
        let failTint = Color(red: 0.890, green: 0.384, blue: 0.384)
        let tint = ok ? successTint : failTint
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    mascotView
                    pip(color: tint, pulses: false)
                        .offset(x: 4, y: 4)
                }
                VStack(alignment: .leading, spacing: 2) {
                    eyebrowLine(suffix: ok ? "已完成" : "操作失败")
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(tint)
                        Text(ok
                             ? Self.readableChoiceLabel(actionAckedChoice)
                             : "操作失败")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !ok, !actionAckedError.isEmpty {
                        Text(actionAckedError)
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

    /// ActionAcked choice id → 中文可读文案 (plugin 17 个 action handler 子集)。
    /// 未知 id 原样返回, 防止新增 handler 时 fork 端漏配导致空白。
    /// `internal static` 便于单测 (Phase 3·Polish-3) 独立验证映射, 不依赖 SwiftUI 渲染。
    static func readableChoiceLabel(_ choice: String) -> String {
        switch choice {
        case "mark_done":                return "标记完成"
        case "create_draft":             return "草稿已创建"
        case "open_mail":                return "已打开邮件"
        case "add_to_calendar":          return "已加入日历"
        case "archive_and_unsubscribe":  return "已归档退订"
        case "open_notion":              return "已打开 Notion"
        case "convert_to_notion_task":   return "已转 Notion 任务"
        case "send_draft":               return "草稿已发送"
        default:                         return choice.isEmpty ? "已完成" : choice
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

    /// Intervention buttons row — Phase 2·T2.2 后 options 数量是 dynamic 1-3 (LLM
    /// recommended_actions) 或 fallback 静态 5 (open_notion/create_draft/mark_done/
    /// snooze_1h/open_mail). 这里 prefix(3) 限制视觉密度: 静态 5 模式只渲前 3 button,
    /// snooze_1h/open_mail 走 expanded view; dynamic 模式 1-3 全显示.
    ///
    /// button click 真触发 plugin handler 走 `interventionButton` onTap 内
    /// `HookSocketServer.shared.respondToIntervention` 路径 (Phase 1·T7 follow-up
    /// commit bbcf85a ship). detail 字段渲染待 Phase 2·T2.5 跟进.
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
        // Phase 2·T2.5: button 高度 30 → 44, detail 非空时渲染 title + detail 二行
        // (Apple Notification action style); detail 空时单行 title 居中 (44 维持高度
        // 防 row 内静态/动态混排时高度跳变).
        let hasDetail = !(opt.detail?.isEmpty ?? true)
        return Button {
            // Phase 1·T7 follow-up (button real action wire, 2026-05-25):
            // 1. HookSocketServer.respondToIntervention 反向 socket response 回 plugin
            //    → plugin `_extract_choice({"decision":{"answer":{"choice": opt.id}}})` 拿 option id
            //    → `island_response.handle_response` 触发对应业务 handler
            //      (Phase 1 静态 5 + Phase 2 dynamic 12 = 17 个 handler)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(opt.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if hasDetail, let detail = opt.detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(
                            (isPrimary ? Color.black : Color.white).opacity(0.55)
                        )
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 80, minHeight: 44, alignment: .leading)
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
