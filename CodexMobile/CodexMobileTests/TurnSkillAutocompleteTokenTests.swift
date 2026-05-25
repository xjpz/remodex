// FILE: TurnSkillAutocompleteTokenTests.swift
// Purpose: Verifies trailing `$` and `/` token parsing and replacement for skill autocomplete.
// Layer: Unit Test
// Exports: TurnSkillAutocompleteTokenTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

@MainActor
final class TurnSkillAutocompleteTokenTests: XCTestCase {
    func testTrailingTokenParsesOnlyWhenItIsFinalToken() {
        let token = TurnViewModel.trailingSkillAutocompleteToken(in: "run $rev")
        XCTAssertEqual(token?.query, "rev")
        XCTAssertEqual(token?.trigger, Character("$"))
    }

    func testBareDollarParsesToOpenSkillList() {
        let token = TurnViewModel.trailingSkillAutocompleteToken(in: "$")
        XCTAssertEqual(token?.query, "")
    }

    func testPureNumericDollarTokenDoesNotParseAsSkill() {
        XCTAssertNil(TurnViewModel.trailingSkillAutocompleteToken(in: "$100"))
    }

    func testSlashSkillTokenParsesForSkillAutocomplete() {
        let token = TurnViewModel.trailingSkillAutocompleteToken(in: "run /check-code")
        XCTAssertEqual(token?.query, "check-code")
        XCTAssertEqual(token?.trigger, Character("/"))
    }

    func testPureNumericSlashTokenDoesNotParseAsSkill() {
        XCTAssertNil(TurnViewModel.trailingSkillAutocompleteToken(in: "/100"))
    }

    func testTrailingTokenDoesNotParseWhenDollarTokenIsNotFinal() {
        XCTAssertNil(TurnViewModel.trailingSkillAutocompleteToken(in: "run $rev now"))
    }

    func testReplacingTrailingTokenUpdatesOnlyFinalDollarToken() {
        let updated = TurnViewModel.replacingTrailingSkillAutocompleteToken(
            in: "compare $first and $rev",
            with: "review"
        )

        XCTAssertEqual(updated, "compare $first and $review ")
    }

    func testReplacingTrailingTokenPreservesSlashSkillTrigger() {
        let updated = TurnViewModel.replacingTrailingSkillAutocompleteToken(
            in: "run /check",
            with: "check-code"
        )

        XCTAssertEqual(updated, "run /check-code ")
    }
}
