import SwiftUI

/// MailAgent session detail view — Sprint 1 骨架（2026-05-17 fork-session 1）。
///
/// 当前状态：**文件存在，未被路由调用**。详 `docs/mailagent/ISLAND-PLUGIN.md` §2.5。
///
/// Sprint 1 范围（REVIEW-LOG H-10 契约）:
/// - 渲染 4 个邮件专属字段占位：subject / senderName / priority chip / aiAction label
/// - 预留 `openUrl: String?`（H-12 Mail.app 跳转字段，`message://<message-id>` URL scheme）
///
/// Sprint 4 联调时需要决定的接入点：
/// 1. metadata 字段来源 —— 加 `SessionState.metadata: [String: String]`，还是从
///    `session.intervention?.rawContext` 取（urgent only）？
/// 2. 真实路由 —— 在 `IslandOpenedContentView` / `IslandExpandedRouteResolver` 哪一层加 mail 分支？
///    （目前 mail event 默认走 generic `HoverSessionCard`，detail view 暂未触发）
///
/// 字段约定（envelope `metadata` 命名空间，详 ISLAND-PLUGIN §3.2）:
/// - `mailagent.subject` — 邮件主题（subject 行）
/// - `mailagent.senderName` — 发件人显示名（"From: …"）
/// - `mailagent.priority` — Urgent / High / Normal / Low
/// - `mailagent.aiAction` — LLM 给出的"需要回复" / "可归档" 等动作建议
/// - `mailagent.openUrl` — Mail.app 跳转 URL（`message://<message-id>`）
struct MailAgentSessionView: View {
    let session: SessionState
    let sessionMonitor: SessionMonitor
    @ObservedObject var viewModel: NotchViewModel
    @State private var isHeaderHovered = false

    // MARK: - Placeholder field accessors (Sprint 4 wire to real metadata)

    private var subject: String {
        session.previewText ?? ""
    }

    private var senderName: String {
        // TODO Sprint 4: read from envelope metadata "mailagent.senderName"
        ""
    }

    private var priority: String {
        // TODO Sprint 4: read from envelope metadata "mailagent.priority"
        ""
    }

    private var aiAction: String {
        // TODO Sprint 4: read from envelope metadata "mailagent.aiAction"
        ""
    }

    private var openUrl: String? {
        // TODO Sprint 4: read from envelope metadata "mailagent.openUrl"
        // Format: "message://<message-id>" (REVIEW-LOG H-12)
        nil
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryCard
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.exitChat()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.6))
                        .frame(width: 24, height: 24)

                    Text(verbatim: "MailAgent")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHeaderHovered ? Color.white.opacity(0.08) : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Subject (line 1)
            Text(subject.isEmpty ? "(no subject)" : subject)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Sender (line 2)
            if !senderName.isEmpty {
                Text(verbatim: "From: \(senderName)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }

            // Priority chip + AI action label (line 3)
            HStack(spacing: 8) {
                if !priority.isEmpty {
                    Text(verbatim: priority)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.85))
                        )
                }
                if !aiAction.isEmpty {
                    Text(verbatim: aiAction)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
    }
}
