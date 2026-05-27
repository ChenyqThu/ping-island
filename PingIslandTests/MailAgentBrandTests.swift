import XCTest
@testable import Ping_Island

/// Phase 3·Polish-3: MailAgent brand 推导测试。
///
/// fork 端 mail 染色靠 `SessionClientInfo.brand` computed property，它先查
/// `ClientProfileRegistry.runtimeProfile(id: profileID)` 拿 brand。mailagent 5-key
/// (client_kind=mailagent 等) 经 `matchRuntimeProfile` 命中 "mailagent" profile
/// (kind=.custom / brand=.mail)；缺 5-key 的 mail-provider envelope 无 profile 命中 →
/// profileID 为 nil → brand 落 .custom/.unknown fallback 的 .neutral。
///
/// 这两条路径正是 `MailAgentSessionView` / `SessionAttentionNotificationView` 内
/// `if session.clientInfo.brand == .mail` 分支触发与否的判据。
final class MailAgentBrandTests: XCTestCase {

    // MARK: - 5-key present → mailagent profile → brand .mail

    func testMailAgentExplicitKindMatchesMailProfile() {
        let profile = ClientProfileRegistry.matchRuntimeProfile(
            provider: .mail,
            explicitKind: "mailagent",
            explicitName: "MailAgent",
            explicitBundleIdentifier: nil,
            terminalBundleIdentifier: nil,
            origin: "plugin",
            originator: nil,
            threadSource: nil,
            processName: nil
        )

        XCTAssertEqual(profile?.id, "mailagent")
        XCTAssertEqual(profile?.kind, .custom)
        XCTAssertEqual(profile?.brand, .mail)
    }

    func testMailAgentClientInfoWith5KeyResolvesBrandMail() {
        // 模拟 makeClientInfo 在命中 mailagent profile 后构造的 SessionClientInfo:
        // kind=.custom + profileID="mailagent"。
        let clientInfo = SessionClientInfo(
            kind: .custom,
            profileID: "mailagent",
            name: "MailAgent",
            origin: "plugin"
        )

        XCTAssertEqual(clientInfo.brand, .mail)
    }

    func testMailAgentHyphenAndSpaceAliasesMatchMailProfile() {
        for alias in ["mail-agent", "mail agent", "mail_agent"] {
            let profile = ClientProfileRegistry.matchRuntimeProfile(
                provider: .mail,
                explicitKind: alias,
                explicitName: nil,
                explicitBundleIdentifier: nil,
                terminalBundleIdentifier: nil,
                origin: nil,
                originator: nil,
                threadSource: nil,
                processName: nil
            )
            XCTAssertEqual(profile?.id, "mailagent", "alias \(alias) 应命中 mailagent profile")
            XCTAssertEqual(profile?.brand, .mail, "alias \(alias) brand 应为 .mail")
        }
    }

    // MARK: - 5-key absent → no profile → brand .neutral (降级)

    func testMailProviderWithoutClientKindDoesNotMatchProfile() {
        // mail-provider envelope 但缺 client_kind/client_name 等 5-key → 无任何信号
        // 命中 mailagent profile。
        let profile = ClientProfileRegistry.matchRuntimeProfile(
            provider: .mail,
            explicitKind: nil,
            explicitName: nil,
            explicitBundleIdentifier: nil,
            terminalBundleIdentifier: nil,
            origin: nil,
            originator: nil,
            threadSource: nil,
            processName: nil
        )

        XCTAssertNil(profile, "缺 5-key 时不应命中 mailagent profile")
    }

    func testCustomClientInfoWithoutProfileFallsBackToNeutral() {
        // 无 profileID 的 .custom client → brand computed property 走
        // .custom/.unknown → .neutral 降级分支。
        let clientInfo = SessionClientInfo(kind: .custom, profileID: nil, name: nil)

        XCTAssertEqual(clientInfo.brand, .neutral)
    }

    func testUnknownProfileIDFallsBackToNeutral() {
        // profileID 存在但 registry 查不到 (拼写错 / 未注册) → 同样降级 .neutral,
        // 不会误判成 .mail。
        let clientInfo = SessionClientInfo(
            kind: .custom,
            profileID: "not-a-real-profile",
            name: "Mystery"
        )

        XCTAssertEqual(clientInfo.brand, .neutral)
    }

    // MARK: - Mail list presentation (subject/sender/summary → 列表标题 & 预览)
    //
    // 邮件推送会话 cwd="/" → projectName="/"，旧逻辑 displayTitle 回退到 "/" → 列表显 "/ · /"。
    // 新增 `mailListTitle`/`mailListPreview`/`shouldHideProjectContextInUI` 让列表行
    // (InstanceRow) 直接读 hookMetadata 的真实主题/摘要/发件人。

    private func makeMailSession(metadata: [String: String]) -> SessionState {
        SessionState(
            sessionId: "mail-1",
            cwd: "/",
            clientInfo: SessionClientInfo(kind: .custom, profileID: "mailagent", name: "MailAgent"),
            hookMetadata: metadata
        )
    }

    func testMailSubjectDrivesTitleAndSummaryDrivesPreview() {
        let session = makeMailSession(metadata: [
            "mailagent.subject": "回复: 商用系统2026技术规划汇报",
            "mailagent.aiSummary": "张三已生成草稿，待你确认",
            "mailagent.senderName": "张三"
        ])

        XCTAssertTrue(session.isMailAgentSession)
        XCTAssertEqual(session.mailListTitle, "回复: 商用系统2026技术规划汇报")
        XCTAssertEqual(session.displayTitle, "回复: 商用系统2026技术规划汇报")
        XCTAssertEqual(session.mailListPreview, "张三已生成草稿，待你确认")
        XCTAssertTrue(session.shouldHideProjectContextInUI)
    }

    func testMailFallsBackToSenderWhenSubjectEmpty() {
        let session = makeMailSession(metadata: [
            "mailagent.subject": "",
            "mailagent.senderName": "张三",
            "mailagent.sender": "zhangsan@example.com"
        ])

        XCTAssertEqual(session.mailListTitle, "张三")
        XCTAssertEqual(session.displayTitle, "张三")
        // 无 aiSummary → 预览回退 "name · address"
        XCTAssertEqual(session.mailListPreview, "张三 · zhangsan@example.com")
    }

    func testMailFallsBackToBrandLabelWhenAllEmpty() {
        let session = makeMailSession(metadata: [:])

        XCTAssertEqual(session.mailListTitle, "MailAgent")
        XCTAssertEqual(session.displayTitle, "MailAgent")
        XCTAssertNil(session.mailListPreview)
    }

    func testNonMailSessionLeavesTitleHelpersUntouched() {
        // 普通 Claude 会话 (默认 provider .claude) → 非 mail，mail helper 全 nil，
        // displayTitle 不被 mail 守卫影响，回退到 projectName。
        let session = SessionState(sessionId: "claude-1", cwd: "/Users/x/myproj")

        XCTAssertFalse(session.isMailAgentSession)
        XCTAssertNil(session.mailListTitle)
        XCTAssertNil(session.mailListPreview)
        XCTAssertEqual(session.displayTitle, "myproj")
        XCTAssertFalse(session.shouldHideProjectContextInUI)
    }

    // MARK: - Mail 生命周期：始终可手动移除 + 5min 短退场
    //
    // 邮件是一次性通知, 非活会话。处理 (skip/done/…) 后 phase=.ended 但旧逻辑要等
    // endedArchiveActionDelay(10min) 才给 archive 按钮、autoArchiveDelay(30min) 才自动消失
    // → skip 后赖 10–30min 且前 10min 无按钮可移除。新逻辑: mail 无待办即始终可 archive,
    // 且空闲 5min 自动退场; 紧急待办 (needsManualAttention) 仍停留。

    private func mailLifecycleSession(phase: SessionPhase, idleMinutes: Double) -> SessionState {
        SessionState(
            sessionId: "mail-lc",
            cwd: "/",
            clientInfo: SessionClientInfo(kind: .custom, profileID: "mailagent", name: "MailAgent"),
            phase: phase,
            lastActivity: Date().addingTimeInterval(-idleMinutes * 60),
            hookMetadata: ["mailagent.subject": "测试邮件"]
        )
    }

    private func claudeLifecycleSession(phase: SessionPhase, idleMinutes: Double) -> SessionState {
        SessionState(
            sessionId: "claude-lc",
            cwd: "/Users/x/proj",
            phase: phase,
            lastActivity: Date().addingTimeInterval(-idleMinutes * 60)
        )
    }

    func testMailEndedShowsArchiveImmediately() {
        // 刚 skip 完 (.ended, 无待办, 刚处理) → 立即可手动移除, 不等 10min。
        let session = mailLifecycleSession(phase: .ended, idleMinutes: 0)
        XCTAssertTrue(session.shouldShowArchiveActionInPrimaryUI)
    }

    func testMailIdleInfoRowShowsArchive() {
        // 信息类邮件 (.idle, 无待办) 也始终可移除。
        let session = mailLifecycleSession(phase: .idle, idleMinutes: 0)
        XCTAssertTrue(session.shouldShowArchiveActionInPrimaryUI)
    }

    func testMailPendingAttentionHidesArchive() {
        // 紧急待办 (.waitingForInput → needsManualAttention) 不显示 archive, 防误清。
        let session = mailLifecycleSession(phase: .waitingForInput, idleMinutes: 0)
        XCTAssertTrue(session.needsManualAttention)
        XCTAssertFalse(session.shouldShowArchiveActionInPrimaryUI)
    }

    func testMailAutoHidesAfterFiveMinutesIdle() {
        let session = mailLifecycleSession(phase: .ended, idleMinutes: 6)
        XCTAssertTrue(session.shouldAutoArchiveFromPrimaryUI)
        XCTAssertTrue(session.shouldHideFromPrimaryUI)
    }

    func testMailStaysVisibleWithinFiveMinutes() {
        let session = mailLifecycleSession(phase: .ended, idleMinutes: 2)
        XCTAssertFalse(session.shouldAutoArchiveFromPrimaryUI)
        XCTAssertFalse(session.shouldHideFromPrimaryUI)
    }

    func testMailPendingAttentionNeverAutoHides() {
        // 紧急待办即使闲置很久也不自动退场 (needsManualAttention 守卫)。
        let session = mailLifecycleSession(phase: .waitingForInput, idleMinutes: 60)
        XCTAssertFalse(session.shouldAutoArchiveFromPrimaryUI)
    }

    func testClaudeEndedRetainsThirtyMinuteModel() {
        // 回归: claude .ended 空闲 6min → 仍无 archive 按钮 (<10min) 且不自动退场 (<30min)。
        let session = claudeLifecycleSession(phase: .ended, idleMinutes: 6)
        XCTAssertFalse(session.isMailAgentSession)
        XCTAssertFalse(session.shouldShowArchiveActionInPrimaryUI)
        XCTAssertFalse(session.shouldAutoArchiveFromPrimaryUI)
    }

    func testClaudeStillAutoHidesAtThirtyMinutes() {
        // 回归: claude 仍用 30min auto-archive (mail 短 delay 没污染 claude 路径)。
        let session = claudeLifecycleSession(phase: .idle, idleMinutes: 31)
        XCTAssertTrue(session.shouldAutoArchiveFromPrimaryUI)
    }
}
