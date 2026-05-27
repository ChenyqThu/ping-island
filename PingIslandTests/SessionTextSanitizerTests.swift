import XCTest
@testable import Ping_Island

/// SessionTextSanitizer 清洗测试 — 重点覆盖 Claude Code 斜杠命令包裹标签
/// (`/clear` 等) 的剥离，防止 `<command-message>…` 泄漏到列表标题
/// (见 `SessionState.displayTitle` → `InstanceRow.titleLine`)。
final class SessionTextSanitizerTests: XCTestCase {

    func testStripsClearSlashCommandWrapper() {
        let raw = "<command-name>/clear</command-name><command-message>clear</command-message><command-args></command-args>"
        XCTAssertNil(SessionTextSanitizer.sanitizedDisplayText(raw))
    }

    func testStripsCommandWrapperButKeepsSurroundingText() {
        let raw = "请帮我 <command-name>/compact</command-name><command-message>compact</command-message> 一下"
        XCTAssertEqual(SessionTextSanitizer.sanitizedDisplayText(raw), "请帮我 一下")
    }

    func testStripsTruncatedUnclosedCommandTag() {
        let raw = "前缀<command-message>cl"
        XCTAssertEqual(SessionTextSanitizer.sanitizedDisplayText(raw), "前缀")
    }

    func testStripsLocalCommandStdout() {
        let raw = "<local-command-stdout>some output</local-command-stdout>结果"
        XCTAssertEqual(SessionTextSanitizer.sanitizedDisplayText(raw), "结果")
    }

    func testPlainTextUnaffected() {
        let raw = "回复: 商用系统2026技术规划汇报"
        XCTAssertEqual(SessionTextSanitizer.sanitizedDisplayText(raw), "回复: 商用系统2026技术规划汇报")
    }

    func testSystemReminderStillStripped() {
        // 回归保护：既有 <system-reminder> 清洗不受新增 command-* 逻辑影响。
        let raw = "正文 <system-reminder>hook success</system-reminder>"
        XCTAssertEqual(SessionTextSanitizer.sanitizedDisplayText(raw), "正文")
    }
}
