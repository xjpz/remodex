// FILE: FileMentionChip.swift
// Purpose: Shared file-mention chip UI used in the composer (removable) and message timeline (read-only).
// Layer: View Component
// Exports: FileMentionChip, SkillMentionChip, PluginMentionChip, ComposerActionChip, FileMentionChipRow, UserMentionChipRow, UserMessageParser, UserMessageParsed, SkillDisplayNameFormatter
// Depends on: SwiftUI, TurnMentionChips

import SwiftUI

// MARK: - Single chip

/// Compact inline `</> filename` pill with optional remove affordance.
struct FileMentionChip: View {
    let fileName: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        TurnMentionChip(ref: .file(fileName, label: fileName), onRemove: onRemove)
    }
}

/// Compact inline `"$ skill"` pill with optional remove affordance.
struct SkillMentionChip: View {
    let skillName: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        TurnMentionChip(ref: .skill(skillName), onRemove: onRemove)
    }
}

/// Compact inline `@ plugin` pill with optional remove affordance.
struct PluginMentionChip: View {
    let pluginName: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        TurnMentionChip(ref: .plugin(pluginName), onRemove: onRemove)
    }
}

/// Compact inline action pill shown when the composer is armed for a slash-command shortcut.
struct ComposerActionChip: View {
    let title: String
    let symbolName: String
    let tintColor: Color
    let removeAccessibilityLabel: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        TurnMentionChip(
            ref: .action(title: title, symbolName: symbolName, tintColor: tintColor),
            removeAccessibilityLabelOverride: removeAccessibilityLabel,
            onRemove: onRemove
        )
    }
}

// MARK: - Composer chip row

/// Horizontal scrolling row of file chips used in the composer input area.
struct FileMentionChipRow: View {
    let files: [TurnComposerMentionedFile]
    var onRemove: ((TurnComposerMentionedFile) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TurnMentionChipTokens.rowSpacing) {
                ForEach(files) { file in
                    FileMentionChip(
                        fileName: file.fileName,
                        onRemove: onRemove.map { callback in
                            { callback(file) }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

// MARK: - Timeline chip row (read-only)

/// Horizontal scrolling row of read-only file chips shown inside a sent message bubble.
struct UserMentionChipRow: View {
    let mentions: [String]  // raw file paths

    var body: some View {
        TurnMentionChipRow(
            chips: mentions.map { .file($0) },
            layout: .scrollLeading
        )
    }
}

// MARK: - Message parser

struct UserMessageParsed: Equatable {
    let mentions: [String]  // raw paths, e.g. "src/Views/Foo.swift"
    let body: String        // remaining text after mention tokens
}

enum SkillDisplayNameFormatter {
    // Converts slug names like "skill-builder" to "Skill Builder".
    static func displayName(for rawName: String) -> String {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return rawName
        }

        let parts = normalized
            .split(omittingEmptySubsequences: true, whereSeparator: { $0 == "-" || $0 == "_" })
            .map { part in
                let token = String(part)
                return token.prefix(1).uppercased() + token.dropFirst().lowercased()
            }

        guard !parts.isEmpty else {
            return normalized
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - Previews

#Preview("Chips") {
    TurnMentionChipCatalog()
}

// MARK: - Flow layout (wraps chips + text field inline)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if i > 0 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            if i > 0 { y += spacing }
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubview]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width + spacing > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentRowWidth += size.width + spacing
        }

        return rows
    }
}

// MARK: - Parser

enum UserMessageParser {
    // Supports both legacy `@token` mentions and file paths with spaces ending in a file extension.
    private static let leadingFileMentionRegex = try? NSRegularExpression(
        pattern: #"^@((?:[^@\n]+?\.[A-Za-z0-9]+)|(?:[^\s@]+))(?=[\s,.;:!?)\]}>]|$)"#
    )

    /// Splits a user message into leading `@path` mention tokens and the rest of the body.
    /// File mentions can contain spaces as long as they still resolve to a path-like token.
    static func parse(_ text: String) -> UserMessageParsed {
        var mentions: [String] = []
        var remainingText = text[...]

        while true {
            let trimmedLeadingText = remainingText.drop(while: \.isWhitespace)
            guard trimmedLeadingText.first == "@",
                  let regex = leadingFileMentionRegex else {
                break
            }

            let workingText = String(trimmedLeadingText)
            let fullRange = NSRange(workingText.startIndex..., in: workingText)
            guard let match = regex.firstMatch(in: workingText, range: fullRange),
                  match.range.location == 0,
                  let mentionRange = Range(match.range(at: 1), in: workingText),
                  let fullMatchRange = Range(match.range, in: workingText) else {
                break
            }

            let mention = String(workingText[mentionRange])
            guard isAllowedFileMentionToken(mention) else {
                break
            }

            mentions.append(mention)
            remainingText = workingText[fullMatchRange.upperBound...]
        }

        let body = String(remainingText).trimmingCharacters(in: .whitespacesAndNewlines)

        return UserMessageParsed(mentions: mentions, body: body)
    }

    // Keeps legacy `@filename` support while rejecting known Swift attribute syntax.
    private static func isAllowedFileMentionToken(_ mention: String) -> Bool {
        TurnFileMentionHeuristics.isAllowedInlineMentionToken(mention)
    }
}
