// FILE: UserMessageBubble.swift
// Purpose: Renders user prompt bubbles, attachment previews, mention chips, and retry/copy actions.
// Layer: View Component
// Exports: UserMessageBubble
// Depends on: SwiftUI, UIKit, UserAttachmentViews, UserBubbleTextBlock, UserBubbleInlineMarkdownText

import SwiftUI
import UIKit

struct UserMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(UserBubbleColor.storageKey) private var userBubbleColorRawValue = UserBubbleColor.defaultStoredRawValue
    private static let bubbleCornerRadius: CGFloat = 22
    private static let darkColoredBubbleOpacity = 0.75

    let message: CodexMessage
    let text: String
    let actionText: String
    var isProgressiveTextWindow: Bool = false
    let isRetryAvailable: Bool
    let onRetryUserMessage: (String) -> Void

    @State private var previewImage: PreviewImagePayload?

    var body: some View {
        let bubbleColor = selectedUserBubbleColor
        let renderModel = UserBubbleRenderModelCache.model(for: message, text: text)
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                if !message.attachments.isEmpty {
                    UserAttachmentStrip(attachments: message.attachments) { tappedAttachment in
                        if let image = AttachmentPreviewImageResolver.resolve(tappedAttachment) {
                            previewImage = PreviewImagePayload(image: image)
                        }
                    }
                }

                if !renderModel.chips.isEmpty {
                    UserMentionChipStrip(chips: renderModel.chips)
                }

                if !renderModel.text.isEmpty {
                    userBubbleTextContent(renderModel, bubbleColor: bubbleColor)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background {
                            RoundedRectangle(cornerRadius: Self.bubbleCornerRadius, style: .continuous)
                                .fill(userBubbleBackground(for: bubbleColor))
                        }
                }

                if let statusText = deliveryStatusText {
                    Text(statusText)
                        .font(AppFont.caption2())
                        .foregroundStyle(message.deliveryState == .failed ? .red : .secondary)
                }
            }
            .contextMenu {
                if !actionText.isEmpty {
                    Button {
                        HapticFeedback.shared.triggerImpactFeedback(style: .light)
                        UIPasteboard.general.string = actionText
                    } label: {
                        RemodexIcon.menuLabel("Copy", systemName: "doc.on.doc")
                    }
                }
                if isRetryAvailable, !actionText.isEmpty {
                    Button {
                        HapticFeedback.shared.triggerImpactFeedback(style: .light)
                        onRetryUserMessage(actionText)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .fullScreenCover(item: $previewImage) { payload in
            ZoomableImagePreviewScreen(
                payload: payload,
                onDismiss: { previewImage = nil }
            )
        }
    }

    private var selectedUserBubbleColor: UserBubbleColor {
        UserBubbleColor(rawValue: userBubbleColorRawValue) ?? .default
    }

    // Softens saturated palettes in dark mode without muting the neutral/default choices.
    private func userBubbleBackground(for bubbleColor: UserBubbleColor) -> Color {
        guard colorScheme == .dark else {
            return bubbleColor.bubbleBackground(for: colorScheme)
        }

        switch bubbleColor {
        case .default, .black:
            return bubbleColor.bubbleBackground(for: colorScheme)
        default:
            return Color(uiColor: bubbleColor.uiColor).opacity(Self.darkColoredBubbleOpacity)
        }
    }

    private var deliveryStatusText: String? {
        switch message.deliveryState {
        case .pending:
            return "Sending"
        case .failed:
            return "Failed"
        case .confirmed:
            return message.createdAt.formatted(date: .omitted, time: .shortened)
        }
    }

    @ViewBuilder
    private func userBubbleTextContent(_ renderModel: UserBubbleRenderModel, bubbleColor: UserBubbleColor) -> some View {
        if isProgressiveTextWindow {
            userBubbleText(renderModel.text, bubbleColor: bubbleColor)
        } else {
            UserBubbleTextBlock(
                contentIdentity: message.id,
                rawText: renderModel.text,
                contentResetKey: renderModel.textFingerprint
            ) {
                userBubbleText(renderModel.text, bubbleColor: bubbleColor)
            }
        }
    }

    private func userBubbleText(_ rawText: String, bubbleColor: UserBubbleColor) -> some View {
        UserBubbleInlineMarkdownText(
            rawText,
            foreground: bubbleColor.bubbleForeground(for: colorScheme)
        )
            .font(AppFont.body())
    }
}

private struct UserBubbleRenderModel: Equatable {
    let text: String
    let textFingerprint: String
    let chips: [TurnMentionChipRef]
}

enum UserBubbleRenderModelCache {
    private static let cache = BoundedCache<String, UserBubbleRenderModel>(maxEntries: 512)

    fileprivate static func model(for message: CodexMessage, text: String) -> UserBubbleRenderModel {
        let displayFingerprint = TurnTextCacheKey.stableFingerprint(for: text)
        let fileMentionsKey = message.fileMentions
            .map { TurnTextCacheKey.stableFingerprint(for: $0) }
            .joined(separator: ",")
        let skillMentionsKey = message.skillMentions
            .map { TurnTextCacheKey.stableFingerprint(for: $0) }
            .joined(separator: ",")
        let pluginMentionsKey = message.pluginMentions
            .map { TurnTextCacheKey.stableFingerprint(for: $0) }
            .joined(separator: ",")
        let key = [
            message.id,
            "\(message.textRenderSignature.byteCount):\(message.textRenderSignature.revision)",
            displayFingerprint,
            fileMentionsKey,
            skillMentionsKey,
            pluginMentionsKey,
        ].joined(separator: "|")

        return cache.getOrSet(key) {
            UserBubbleMentionExtractor.renderModel(
                text: text,
                displayFingerprint: displayFingerprint,
                fileMentions: message.fileMentions,
                skillMentions: message.skillMentions,
                pluginMentions: message.pluginMentions
            )
        }
    }

    static func reset() {
        cache.removeAll()
    }
}

private enum UserBubbleMentionExtractor {
    private struct Replacement {
        let range: NSRange
        let text: String
    }

    private static let repeatedHorizontalWhitespace = try? NSRegularExpression(pattern: #"[ \t]{2,}"#)
    private static let slashCommandRegex: NSRegularExpression? = {
        let tokens = TurnComposerSlashCommand.allCommands
            .map(\.commandToken)
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        guard !tokens.isEmpty else { return nil }
        return try? NSRegularExpression(
            pattern: "(?<!\\S)(\(tokens))(?=[\\s,.;:!?\\)\\]\\}>]|$)"
        )
    }()

    static func renderModel(
        text rawText: String,
        displayFingerprint: String,
        fileMentions: [String],
        skillMentions: [String] = [],
        pluginMentions: [String] = []
    ) -> UserBubbleRenderModel {
        var chips: [TurnMentionChipRef] = []
        var seenChipIDs: Set<String> = []
        let confirmedFileMentions = normalizedConfirmedFileMentions(fileMentions)

        for mention in fileMentions {
            let trimmed = mention.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            appendChip(.file(trimmed), to: &chips, seenChipIDs: &seenChipIDs)
        }

        for mention in skillMentions {
            let trimmed = mention.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            appendChip(.skill(trimmed), to: &chips, seenChipIDs: &seenChipIDs)
        }

        for mention in pluginMentions {
            let trimmed = mention.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            appendChip(.plugin(trimmed), to: &chips, seenChipIDs: &seenChipIDs)
        }

        let normalizedText = SkillReferenceFormatter.replacingSkillReferences(
            in: rawText,
            style: .mentionToken
        )
        var replacements: [Replacement] = []
        collectSlashCommandReplacements(
            in: normalizedText,
            replacements: &replacements,
            chips: &chips,
            seenChipIDs: &seenChipIDs
        )

        if normalizedText.contains("@") || normalizedText.contains("$"),
           let mentionRegex = TurnMessageRegexCache.userMentionToken {
            let nsText = normalizedText as NSString
            let matches = mentionRegex.matches(
                in: normalizedText,
                range: NSRange(location: 0, length: nsText.length)
            )

            for match in matches {
                guard let parsed = parsedMention(match: match, in: nsText) else {
                    continue
                }

                switch parsed.trigger {
                case "@":
                    let normalizedFileToken = TurnMessageRegexCache.removingTrailingLineColumnSuffix(from: parsed.token)
                    if confirmedFileMentions.contains(normalizedFileToken) {
                        replacements.append(Replacement(range: match.range, text: parsed.trailingPunctuation))
                    } else if isLikelyPluginMention(parsed.token) {
                        appendChip(.plugin(parsed.token), to: &chips, seenChipIDs: &seenChipIDs)
                        replacements.append(Replacement(range: match.range, text: parsed.trailingPunctuation))
                    }
                case "$":
                    guard isLikelySkillMention(parsed.token) else { continue }
                    appendChip(.skill(parsed.token), to: &chips, seenChipIDs: &seenChipIDs)
                    replacements.append(Replacement(range: match.range, text: parsed.trailingPunctuation))
                default:
                    continue
                }
            }
        }

        let displayText = cleanedText(
            replacing: replacements,
            in: normalizedText
        )
        return UserBubbleRenderModel(
            text: displayText,
            textFingerprint: TurnTextCacheKey.stableFingerprint(for: displayText),
            chips: chips
        )
    }

    private static func collectSlashCommandReplacements(
        in text: String,
        replacements: inout [Replacement],
        chips: inout [TurnMentionChipRef],
        seenChipIDs: inout Set<String>
    ) {
        guard let slashCommandRegex else { return }

        let nsText = text as NSString
        let matches = slashCommandRegex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return }

        for match in matches {
            let token = nsText.substring(with: match.range)
            guard let command = TurnComposerSlashCommand.allCommands.first(where: { $0.commandToken == token }) else {
                continue
            }

            appendChip(.slashCommand(command), to: &chips, seenChipIDs: &seenChipIDs)
            replacements.append(Replacement(range: match.range, text: ""))
        }
    }

    private static func normalizedConfirmedFileMentions(_ mentions: [String]) -> Set<String> {
        Set(
            mentions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map(TurnMessageRegexCache.removingTrailingLineColumnSuffix)
                .filter { !$0.isEmpty }
        )
    }

    private static func appendChip(
        _ chip: TurnMentionChipRef,
        to chips: inout [TurnMentionChipRef],
        seenChipIDs: inout Set<String>
    ) {
        guard seenChipIDs.insert(chip.id).inserted else { return }
        chips.append(chip)
    }

    private static func parsedMention(
        match: NSTextCheckingResult,
        in nsText: NSString
    ) -> (trigger: String, token: String, trailingPunctuation: String)? {
        let triggerRange = match.range(at: 1)
        let tokenRange = match.range(at: 2)
        guard triggerRange.location != NSNotFound,
              tokenRange.location != NSNotFound else {
            return nil
        }

        let trigger = nsText.substring(with: triggerRange)
        let rawToken = nsText.substring(with: tokenRange)
        let normalized = normalizedMentionToken(rawToken)
        guard !normalized.token.isEmpty else {
            return nil
        }

        return (trigger, normalized.token, normalized.trailingPunctuation)
    }

    private static func normalizedMentionToken(_ token: String) -> (token: String, trailingPunctuation: String) {
        let punctuationSet = CharacterSet(charactersIn: ".,;:!?)]}")
        let scalars = Array(token.unicodeScalars)

        var splitIndex = scalars.count
        while splitIndex > 0, punctuationSet.contains(scalars[splitIndex - 1]) {
            splitIndex -= 1
        }

        let pathScalars = scalars.prefix(splitIndex)
        let trailingScalars = scalars.suffix(scalars.count - splitIndex)
        let path = String(String.UnicodeScalarView(pathScalars))
        let trailing = String(String.UnicodeScalarView(trailingScalars))
        return (path, trailing)
    }

    private static func cleanedText(replacing replacements: [Replacement], in text: String) -> String {
        guard !replacements.isEmpty else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let mutableText = NSMutableString(string: text)
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            mutableText.replaceCharacters(in: replacement.range, with: replacement.text)
        }

        let collapsed = TurnMessageRegexCache.replaceMatches(
            in: String(mutableText),
            regex: repeatedHorizontalWhitespace,
            template: " "
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Keeps plugin chips to app-style slugs so Swift attributes and scoped build labels stay plain.
    private static func isLikelyPluginMention(_ token: String) -> Bool {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = normalized.first,
              first.isLowercase || first.isNumber else {
            return false
        }

        return normalized.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }

    private static func isLikelySkillMention(_ token: String) -> Bool {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.contains(where: \.isLetter) else {
            return false
        }

        return normalized.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
    }
}

// MARK: - Previews

private struct UserBubblePreviewCatalog: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                previewSection("Skill chip + text") {
                    bubblePreview(
                        text: "can you",
                        skillMentions: ["check-code"],
                        actionText: "can you $check-code",
                        bubbleColor: .purple
                    )
                }

                previewSection("Skill + file + plugin") {
                    bubblePreview(
                        text: "review this module",
                        fileMentions: ["TurnView.swift"],
                        skillMentions: ["check-code"],
                        pluginMentions: ["linear"],
                        actionText: "review this module @TurnView.swift $check-code @linear",
                        bubbleColor: .indigo
                    )
                }

                previewSection("Text only") {
                    bubblePreview(
                        text: "can you help me refactor this?",
                        actionText: "can you help me refactor this?"
                    )
                }

                previewSection("Slash command + skill") {
                    bubblePreview(
                        text: "run on local changes",
                        skillMentions: ["frontend-design"],
                        actionText: "/review run on local changes $frontend-design",
                        bubbleColor: .blue
                    )
                }
            }
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func previewSection<Content: View>(
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

    private func bubblePreview(
        text: String,
        fileMentions: [String] = [],
        skillMentions: [String] = [],
        pluginMentions: [String] = [],
        actionText: String,
        bubbleColor: UserBubbleColor = .default
    ) -> some View {
        UserMessageBubble(
            message: CodexMessage(
                id: "preview-\(titleFingerprint(text, skillMentions, pluginMentions))",
                threadId: "preview-thread",
                role: .user,
                text: text,
                fileMentions: fileMentions,
                skillMentions: skillMentions,
                pluginMentions: pluginMentions,
                deliveryState: .confirmed
            ),
            text: text,
            actionText: actionText,
            isRetryAvailable: false,
            onRetryUserMessage: { _ in }
        )
        .defaultAppStorage(previewDefaults(for: bubbleColor))
    }

    private func previewDefaults(for color: UserBubbleColor) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "user-bubble-preview-\(color.rawValue)") ?? .standard
        defaults.set(color.rawValue, forKey: UserBubbleColor.storageKey)
        return defaults
    }

    private func titleFingerprint(
        _ text: String,
        _ skills: [String],
        _ plugins: [String]
    ) -> String {
        ([text] + skills + plugins).joined(separator: "-")
    }
}

#Preview("User Bubble — Mention Chips") {
    UserBubblePreviewCatalog()
}
