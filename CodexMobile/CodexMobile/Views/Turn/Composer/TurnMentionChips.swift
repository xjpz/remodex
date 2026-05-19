// FILE: TurnMentionChips.swift
// Purpose: Shared mention/action chip tokens, semantic refs, row layout, and preview catalog.
// Layer: View Component
// Exports: TurnMentionChipRef, TurnMentionChip, TurnMentionChipRow, UserMentionChipStrip, SlashCommandChip, TurnMentionChipCatalog
// Depends on: SwiftUI, TurnComposerCommandState

import SwiftUI

// MARK: - Tokens

enum TurnMentionChipTokens {
    static let iconFont = AppFont.system(size: 9, weight: .semibold)
    static let labelFont = AppFont.footnote(weight: .medium)
    static let removeFont = AppFont.system(size: 8, weight: .bold)
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 4
    static let cornerRadius: CGFloat = 8
    static let removeButtonSize: CGFloat = 14
    static let contentSpacing: CGFloat = 4
    static let rowSpacing: CGFloat = 6
}

struct TurnMentionChipStyle: Equatable {
    let symbolName: String
    let tintColor: Color

    static let file = TurnMentionChipStyle(
        symbolName: "chevron.left.forwardslash.chevron.right",
        tintColor: .blue
    )

    static let skill = TurnMentionChipStyle(
        symbolName: "square.stack.3d.up",
        tintColor: .indigo
    )

    static let plugin = TurnMentionChipStyle(
        symbolName: "circle.grid.2x2",
        tintColor: .blue
    )

    static let review = TurnMentionChipStyle(
        symbolName: "checklist",
        tintColor: .teal
    )

    static let subagents = TurnMentionChipStyle(
        symbolName: "point.3.connected.trianglepath.dotted",
        tintColor: .teal
    )

    static func slashCommand(_ command: TurnComposerSlashCommand) -> TurnMentionChipStyle {
        TurnMentionChipStyle(
            symbolName: command.symbolName,
            tintColor: slashCommandTint(for: command)
        )
    }

    private static func slashCommandTint(for command: TurnComposerSlashCommand) -> Color {
        switch command {
        case .codeReview, .subagents:
            return .teal
        case .compact:
            return .purple
        case .feedback:
            return .pink
        case .fork:
            return .blue
        case .status:
            return .secondary
        }
    }
}

// MARK: - Semantic ref

struct TurnMentionChipRef: Identifiable, Equatable {
    enum Kind: Equatable {
        case file
        case skill
        case plugin
        case slashCommand(TurnComposerSlashCommand)
        case review(TurnComposerReviewTarget)
        case subagents
        case action(TurnMentionChipStyle)
    }

    let kind: Kind
    let label: String
    let identity: String

    var id: String {
        switch kind {
        case .slashCommand(let command):
            return "slash:\(command.rawValue):\(identity)"
        case .review(let target):
            return "review:\(target.rawValue):\(identity)"
        case .action:
            return "action:\(identity)"
        default:
            return "\(kindKey):\(identity)"
        }
    }

    private var kindKey: String {
        switch kind {
        case .file: return "file"
        case .skill: return "skill"
        case .plugin: return "plugin"
        case .slashCommand: return "slash"
        case .review: return "review"
        case .subagents: return "subagents"
        case .action: return "action"
        }
    }

    var style: TurnMentionChipStyle {
        switch kind {
        case .file:
            return .file
        case .skill:
            return .skill
        case .plugin:
            return .plugin
        case .slashCommand(let command):
            return .slashCommand(command)
        case .review:
            return .review
        case .subagents:
            return .subagents
        case .action(let style):
            return style
        }
    }

    var removeAccessibilityLabel: String {
        switch kind {
        case .file:
            return "Remove file mention"
        case .skill:
            return "Remove skill mention"
        case .plugin:
            return "Remove plugin mention"
        case .slashCommand(let command):
            return "Remove \(command.title)"
        case .review:
            return "Remove code review"
        case .subagents:
            return "Remove subagents"
        case .action:
            return "Remove action"
        }
    }

    static func file(_ path: String, label: String? = nil) -> TurnMentionChipRef {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayLabel = label ?? trimmed.pathDisplayName
        let identity = TurnMessageRegexCache.removingTrailingLineColumnSuffix(from: trimmed).lowercased()
        return TurnMentionChipRef(kind: .file, label: displayLabel, identity: identity)
    }

    static func skill(_ name: String) -> TurnMentionChipRef {
        TurnMentionChipRef(
            kind: .skill,
            label: name,
            identity: name.lowercased()
        )
    }

    static func plugin(_ name: String, label: String? = nil) -> TurnMentionChipRef {
        TurnMentionChipRef(
            kind: .plugin,
            label: label ?? name,
            identity: name.lowercased()
        )
    }

    static func slashCommand(_ command: TurnComposerSlashCommand) -> TurnMentionChipRef {
        TurnMentionChipRef(
            kind: .slashCommand(command),
            label: command.title,
            identity: command.rawValue
        )
    }

    static func review(_ target: TurnComposerReviewTarget) -> TurnMentionChipRef {
        TurnMentionChipRef(
            kind: .review(target),
            label: "Code Review: \(target.title)",
            identity: target.rawValue
        )
    }

    static var subagents: TurnMentionChipRef {
        TurnMentionChipRef(kind: .subagents, label: "Subagents", identity: "subagents")
    }

    static func action(
        title: String,
        symbolName: String,
        tintColor: Color,
        identity: String? = nil
    ) -> TurnMentionChipRef {
        TurnMentionChipRef(
            kind: .action(TurnMentionChipStyle(symbolName: symbolName, tintColor: tintColor)),
            label: title,
            identity: identity ?? title
        )
    }
}

// MARK: - Chip

struct TurnMentionChip: View {
    let ref: TurnMentionChipRef
    var removeAccessibilityLabelOverride: String? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        let style = ref.style
        HStack(spacing: TurnMentionChipTokens.contentSpacing) {
            RemodexIcon.image(systemName: style.symbolName)
                .font(TurnMentionChipTokens.iconFont)
                .foregroundStyle(style.tintColor)

            Text(displayLabel)
                .font(TurnMentionChipTokens.labelFont)
                .foregroundStyle(style.tintColor)
                .lineLimit(1)

            if let onRemove {
                removeButton(tintColor: style.tintColor, action: onRemove)
            }
        }
        .padding(.horizontal, TurnMentionChipTokens.horizontalPadding)
        .padding(.vertical, TurnMentionChipTokens.verticalPadding)
        .background(style.tintColor.opacity(0.08), in: RoundedRectangle(cornerRadius: TurnMentionChipTokens.cornerRadius))
    }

    private var displayLabel: String {
        switch ref.kind {
        case .skill, .plugin:
            return SkillDisplayNameFormatter.displayName(for: ref.label)
        default:
            return ref.label
        }
    }

    private func removeButton(tintColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RemodexIcon.image(systemName: "xmark")
                .font(TurnMentionChipTokens.removeFont)
                .foregroundStyle(tintColor)
                .frame(width: TurnMentionChipTokens.removeButtonSize, height: TurnMentionChipTokens.removeButtonSize)
                .background(tintColor.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(removeAccessibilityLabelOverride ?? ref.removeAccessibilityLabel)
    }
}

struct SlashCommandChip: View {
    let command: TurnComposerSlashCommand
    var onRemove: (() -> Void)? = nil

    var body: some View {
        TurnMentionChip(ref: .slashCommand(command), onRemove: onRemove)
    }
}

// MARK: - Timeline strip

/// Read-only mention chips shown above a sent user bubble, matching attachment strip placement.
struct UserMentionChipStrip: View {
    let chips: [TurnMentionChipRef]

    var body: some View {
        TurnMentionChipRow(chips: chips, layout: .scrollTrailing)
    }
}

// MARK: - Row

struct TurnMentionChipRow: View {
    enum Layout {
        case scrollLeading
        case scrollTrailing
        case inlineLeading
        case inlineTrailing
    }

    let chips: [TurnMentionChipRef]
    var layout: Layout = .scrollLeading
    var horizontalPadding: CGFloat = 0
    var topPadding: CGFloat = 0
    var onRemove: ((TurnMentionChipRef) -> Void)? = nil

    var body: some View {
        chipStack
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
    }

    @ViewBuilder
    private var chipStack: some View {
        switch layout {
        case .scrollLeading, .scrollTrailing:
            ScrollView(.horizontal, showsIndicators: false) {
                chipHStack
            }
            .defaultScrollAnchor(layout == .scrollLeading ? .leading : .trailing, for: .initialOffset)
            .frame(maxWidth: .infinity, alignment: layout == .scrollLeading ? .leading : .trailing)

        case .inlineLeading, .inlineTrailing:
            chipHStack
        }
    }

    private var chipHStack: some View {
        HStack(spacing: TurnMentionChipTokens.rowSpacing) {
            ForEach(chips) { chip in
                TurnMentionChip(
                    ref: chip,
                    onRemove: onRemove.map { callback in
                        { callback(chip) }
                    }
                )
            }
        }
    }
}

// MARK: - Preview catalog

struct TurnMentionChipCatalog: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                catalogSection("Files") {
                    chipWrap {
                        TurnMentionChip(ref: .file("src/Views/SidebarView.swift"))
                        TurnMentionChip(ref: .file("src/index.ts"))
                        TurnMentionChip(ref: .file("config.json"))
                    }
                }

                catalogSection("Skills") {
                    chipWrap {
                        TurnMentionChip(ref: .skill("skill-builder"))
                        TurnMentionChip(ref: .skill("check-code"))
                        TurnMentionChip(ref: .skill("frontend-design"))
                    }
                }

                catalogSection("Plugins") {
                    chipWrap {
                        TurnMentionChip(ref: .plugin("linear"))
                        TurnMentionChip(ref: .plugin("github"))
                        TurnMentionChip(ref: .plugin("playwright"))
                    }
                }

                catalogSection("Slash Commands") {
                    chipWrap {
                        ForEach(TurnComposerSlashCommand.allCommands) { command in
                            SlashCommandChip(command: command)
                        }
                    }
                }

                catalogSection("Composer Actions") {
                    chipWrap {
                        TurnMentionChip(ref: .subagents)
                        TurnMentionChip(ref: .review(.uncommittedChanges))
                        TurnMentionChip(ref: .review(.baseBranch))
                    }
                }

                catalogSection("Removable") {
                    chipWrap {
                        TurnMentionChip(ref: .file("TurnView.swift")) {}
                        TurnMentionChip(ref: .skill("refactor-code")) {}
                        TurnMentionChip(ref: .plugin("linear")) {}
                        SlashCommandChip(command: .codeReview) {}
                        TurnMentionChip(ref: .review(.uncommittedChanges)) {}
                        TurnMentionChip(ref: .subagents) {}
                    }
                }

                catalogSection("Composer Row") {
                    TurnMentionChipRow(
                        chips: [
                            .file("UserMessageBubble.swift"),
                            .skill("ui-component-extractor"),
                            .plugin("linear"),
                            .subagents,
                        ],
                        layout: .scrollLeading,
                        horizontalPadding: 16,
                        topPadding: 10,
                        onRemove: { _ in }
                    )
                }

                catalogSection("Bubble Row") {
                    VStack(alignment: .trailing, spacing: 4) {
                        UserMentionChipStrip(
                            chips: [
                                .file("TurnMentionChips.swift"),
                                .skill("check-code"),
                                .slashCommand(.compact),
                            ]
                        )
                        Text("can you")
                            .font(AppFont.body())
                            .foregroundStyle(.primary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func catalogSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.subheadline(weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            content()
        }
    }

    private func chipWrap<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TurnMentionChipTokens.rowSpacing) {
                content()
            }
            .padding(.horizontal, 16)
        }
    }
}

#Preview("Mention Chips — Catalog") {
    TurnMentionChipCatalog()
}
