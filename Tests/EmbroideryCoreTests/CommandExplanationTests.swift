// Checks the hover explanations for commands: every command has one, and each is one short, complete sentence.
import XCTest
@testable import EmbroideryCore

final class CommandExplanationTests: XCTestCase {
    func testEveryCommandExplainsItselfInAShortSentence() {
        for command in CommandID.allCases {
            let text = command.explanation
            XCTAssertTrue(text.first?.isUppercase == true && text.hasSuffix("."), "\(command): starts with a capital and ends with a full stop")
            XCTAssertLessThanOrEqual(text.count, 130, "\(command): short enough to read at a glance")
            XCTAssertGreaterThan(text.count, command.title.count + 10, "\(command): says what it does, not just its name again")
        }
    }
}
