// FILE: ChatEmptyStatePlaceholder.swift
// Purpose: Centered AppLogo + title + subtitle placeholder used by TurnView's
//          empty/loading states. The New Chat draft surface intentionally uses
//          its own tighter prompt-and-picker layout instead of this hero block.
// Layer: View Component
// Exports: ChatEmptyStatePlaceholder
// Depends on: SwiftUI, AppFont, adaptiveGlass

import SwiftUI

struct ChatEmptyStatePlaceholder: View {
    let title: Text
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .adaptiveGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            title
                .font(AppFont.title2(weight: .regular))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Text(subtitle)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// Composes the standard "What should we do in {folder}?" / "Hi! How can I help you?"
// title used in the chat empty states. Centralized so the draft surface stays
// visually identical to the regular TurnView placeholder.
enum ChatEmptyStateTitleBuilder {
    static func makeTitle(for folderName: String?) -> Text {
        guard let folderName,
              !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Text("Hi! How can I help you?")
        }
        return Text("What should we do in ")
            + Text(folderName).foregroundStyle(.secondary)
            + Text("?")
    }
}
