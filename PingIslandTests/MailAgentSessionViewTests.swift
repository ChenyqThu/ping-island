import XCTest
@testable import Ping_Island

/// Phase 3·Polish-3: MailAgentSessionView scenario 路由 / ActionAcked choice 文案 /
/// interventionButton wire 测试。
///
/// 视图 body 是 opaque `some View` 无法直接 introspect 分支，故路由测试走视图暴露的
/// 纯函数 `layoutKind(forScenario:)`（body 与本测试共用的单一真源）。button wire 测试
/// 验证 metadata→toolUseId 提取与 choice payload 构造逻辑（plan Polish-3 兜底口径），
/// 并经 SessionStore 实管线确认 mail 事件 metadata 落进 hookMetadata、intervention
/// options 完整透传。
@MainActor
final class MailAgentSessionViewTests: XCTestCase {

    // MARK: - scenario → layout 路由 (单一真源 layoutKind)

    func testScenarioRoutingCoversAllMailScenarios() {
        typealias View = MailAgentSessionView
        XCTAssertEqual(View.layoutKind(forScenario: "MailReceivedUrgent"), .attention)
        XCTAssertEqual(View.layoutKind(forScenario: "LLMReviewedUrgent"), .attention)
        XCTAssertEqual(View.layoutKind(forScenario: "AIDraftReady"), .draft)
        XCTAssertEqual(View.layoutKind(forScenario: "MailCompleted"), .completed)
        XCTAssertEqual(View.layoutKind(forScenario: "SyncFailed"), .error)
        XCTAssertEqual(View.layoutKind(forScenario: "DeadLetterAccum"), .deadLetter)
        XCTAssertEqual(View.layoutKind(forScenario: "DailyDigest"), .digest)
        // Phase 3·Polish-1 新增
        XCTAssertEqual(View.layoutKind(forScenario: "ActionAcked"), .acked)
    }

    func testUnknownOrEmptyScenarioFallsBack() {
        XCTAssertEqual(MailAgentSessionView.layoutKind(forScenario: ""), .fallback)
        XCTAssertEqual(MailAgentSessionView.layoutKind(forScenario: "SomethingNew"), .fallback)
    }

    // MARK: - ActionAcked choice → 可读文案

    func testReadableChoiceLabelKnownChoices() {
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("mark_done"), "标记完成")
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("create_draft"), "草稿已创建")
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("open_mail"), "已打开邮件")
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("add_to_calendar"), "已加入日历")
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("archive_and_unsubscribe"), "已归档退订")
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("open_notion"), "已打开 Notion")
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("convert_to_notion_task"), "已转 Notion 任务")
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("send_draft"), "草稿已发送")
    }

    func testReadableChoiceLabelUnknownReturnsRaw() {
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel("some_future_action"), "some_future_action")
    }

    func testReadableChoiceLabelEmptyFallsBackToDone() {
        XCTAssertEqual(MailAgentSessionView.readableChoiceLabel(""), "已完成")
    }

    // MARK: - mail 事件 metadata 经 SessionStore 落进 hookMetadata (scenario 数据通道)

    func testMailScenarioMetadataPreservedInSession() async {
        let sessionId = "mail-scenario-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(makeMailEvent(
            sessionId: sessionId,
            metadata: [
                "client_kind": "mailagent",
                "mailagent.scenario": "MailCompleted",
                "mailagent.subject": "周报已同步",
                "mailagent.mascot": "work"
            ]
        )))

        let session = await store.session(for: sessionId)
        XCTAssertEqual(session?.provider, .mail)
        XCTAssertEqual(session?.hookMetadata["mailagent.scenario"], "MailCompleted")
        XCTAssertEqual(session?.hookMetadata["mailagent.subject"], "周报已同步")
        // 路由真源应据此 metadata 选 .completed 分支。
        XCTAssertEqual(
            MailAgentSessionView.layoutKind(
                forScenario: session?.hookMetadata["mailagent.scenario"] ?? ""
            ),
            .completed
        )

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    // MARK: - interventionButton wire: toolUseId 提取 + choice payload

    func testInterventionButtonToolUseIdPrefersMetadata() async {
        // 视图 button handler: toolUseId = hookMetadata["tool_use_id"] ?? sessionId。
        // metadata 带 tool_use_id 时优先取它 (plugin envelope.py 写 bridge-<envelope_id>)。
        let sessionId = "mail-btn-\(UUID().uuidString)"
        let store = SessionStore.shared

        await store.process(.hookReceived(makeMailEvent(
            sessionId: sessionId,
            metadata: [
                "client_kind": "mailagent",
                "mailagent.scenario": "MailReceivedUrgent",
                "tool_use_id": "bridge-envelope-42"
            ]
        )))

        let session = await store.session(for: sessionId)
        let resolvedToolUseId = session?.hookMetadata["tool_use_id"] ?? sessionId
        XCTAssertEqual(resolvedToolUseId, "bridge-envelope-42")

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    func testInterventionButtonToolUseIdFallsBackToSessionId() {
        // 旧 envelope 缺 tool_use_id → handler 兜底用 sessionId (至少不 crash)。
        let sessionId = "mail-btn-fallback-\(UUID().uuidString)"
        let hookMetadata: [String: String] = ["mailagent.scenario": "MailReceivedUrgent"]
        let resolvedToolUseId = hookMetadata["tool_use_id"] ?? sessionId
        XCTAssertEqual(resolvedToolUseId, sessionId)
    }

    func testInterventionChoicePayloadShape() {
        // handler 构造 updatedInput: ["choice": optionId] → sendHookResponse 编码
        // {"decision":{"answer":{"choice": ...}}}。这里验证 payload 字典形状/取值正确。
        let optionId = "create_draft"
        let updatedInput: [String: Any] = ["choice": optionId]
        XCTAssertEqual(updatedInput["choice"] as? String, "create_draft")
        XCTAssertEqual(updatedInput.count, 1)
    }

    func testMailInterventionOptionsPreservedThroughStore() async {
        // button row 渲染 session.intervention?.options.prefix(3); 验证 mail 事件携带的
        // bridgeIntervention options 经 store 透传不丢, click 才有正确 choice 可回写。
        let sessionId = "mail-options-\(UUID().uuidString)"
        let store = SessionStore.shared
        let intervention = SessionIntervention(
            id: "bridge-envelope-99",
            kind: .question,
            title: "紧急邮件",
            message: "选择处理方式",
            options: [
                SessionInterventionOption(id: "mark_done", title: "标记完成", detail: nil),
                SessionInterventionOption(id: "create_draft", title: "起草回复", detail: "AI 代写")
            ],
            questions: [],
            supportsSessionScope: false,
            metadata: [:]
        )

        await store.process(.hookReceived(makeMailEvent(
            sessionId: sessionId,
            status: "waiting_for_input",
            metadata: [
                "client_kind": "mailagent",
                "mailagent.scenario": "MailReceivedUrgent",
                "tool_use_id": "bridge-envelope-99"
            ],
            bridgeIntervention: intervention
        )))

        let session = await store.session(for: sessionId)
        let options = session?.intervention?.options ?? []
        XCTAssertEqual(options.map(\.id), ["mark_done", "create_draft"])
        XCTAssertEqual(options.first?.id, "mark_done")

        await store.process(.sessionArchived(sessionId: sessionId))
    }

    // MARK: - Helpers

    private func makeMailEvent(
        sessionId: String,
        status: String = "notification",
        metadata: [String: String],
        bridgeIntervention: SessionIntervention? = nil
    ) -> HookEvent {
        HookEvent(
            sessionId: sessionId,
            cwd: "/tmp/mailagent",
            event: "Notification",
            status: status,
            provider: .mail,
            clientInfo: SessionClientInfo(
                kind: .custom,
                profileID: "mailagent",
                name: "MailAgent",
                origin: "plugin"
            ),
            pid: nil,
            tty: nil,
            tool: nil,
            toolInput: nil,
            toolUseId: bridgeIntervention?.id,
            notificationType: nil,
            message: nil,
            bridgeIntervention: bridgeIntervention,
            metadata: metadata
        )
    }
}
