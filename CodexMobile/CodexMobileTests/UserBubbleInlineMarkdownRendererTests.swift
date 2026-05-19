// FILE: UserBubbleInlineMarkdownRendererTests.swift
// Purpose: Verifies lightweight inline markdown rendering for user prompt bubbles.
// Layer: Unit Test
// Exports: UserBubbleInlineMarkdownRendererTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

@MainActor
final class UserBubbleInlineMarkdownRendererTests: XCTestCase {
    override func tearDown() {
        UserBubbleInlineMarkdownRenderer.reset()
        super.tearDown()
    }

    func testPlainTextUsesFastPath() {
        let rendered = UserBubbleInlineMarkdownRenderer.render("is this safe to merge?")

        guard case .plain = rendered else {
            return XCTFail("Expected plain text to skip markdown parsing.")
        }
    }

    func testUnpairedInlineMarkerUsesFastPath() {
        let rendered = UserBubbleInlineMarkdownRenderer.render("run ls *.swift")

        guard case .plain = rendered else {
            return XCTFail("Expected unpaired markdown markers to stay on the plain text path.")
        }
    }

    func testMarkdownLinkUsesLabelText() {
        let rendered = UserBubbleInlineMarkdownRenderer.render(
            "[Emanuele-web04/remodex#133](https://github.com/Emanuele-web04/remodex/pull/133)"
        )

        XCTAssertEqual(rendered.visibleText, "Emanuele-web04/remodex#133")
        XCTAssertTrue(rendered.hasUnderlinedLink)
    }

    func testBareURLIsLinkifiedWithoutKeepingTrailingPunctuation() {
        let rendered = UserBubbleInlineMarkdownRenderer.render("Review (https://example.com/test).")

        XCTAssertEqual(rendered.visibleText, "Review (https://example.com/test).")
        XCTAssertTrue(rendered.hasLink(to: "https://example.com/test"))
        XCTAssertTrue(rendered.hasUnderlinedLink)
    }

    func testBareURLKeepsBalancedTrailingParenthesis() {
        let rendered = UserBubbleInlineMarkdownRenderer.render("Read https://example.com/Foo_(bar)")

        XCTAssertEqual(rendered.visibleText, "Read https://example.com/Foo_(bar)")
        XCTAssertTrue(rendered.hasLink(to: "https://example.com/Foo_(bar)"))
    }

    func testBoldItalicAndCodeRemoveMarkdownMarkers() {
        let rendered = UserBubbleInlineMarkdownRenderer.render("Use **bold**, *italic*, and `code`.")

        XCTAssertEqual(rendered.visibleText, "Use bold, italic, and code.")
    }

    func testMalformedMarkdownFallsBackToVisibleText() {
        let rendered = UserBubbleInlineMarkdownRenderer.render("Look at [broken]( and keep going")

        XCTAssertFalse(rendered.visibleText.isEmpty)
    }
}

private extension UserBubbleInlineMarkdownRenderResult {
    var visibleText: String {
        switch self {
        case .plain:
            return ""
        case .rich(let attributed):
            return String(attributed.characters)
        }
    }

    func hasLink(to expectedURL: String) -> Bool {
        guard case .rich(let attributed) = self else {
            return false
        }

        return attributed.runs.contains { run in
            run.link?.absoluteString == expectedURL
        }
    }

    var hasUnderlinedLink: Bool {
        guard case .rich(let attributed) = self else {
            return false
        }

        return attributed.runs.contains { run in
            run.link != nil && run.underlineStyle != nil
        }
    }
}
