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
}
