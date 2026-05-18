// FILE: SidebarBottomActionBar.swift
// Purpose: Bottom-anchored sidebar bar. Hosts the Terminal pill on the leading
//          edge and the primary Chat pill on the trailing edge. Both pills are
//          built from the same reusable `SidebarActionPill` component so they
//          share font, icon size, padding and capsule shape — only the style
//          differs. iOS 26 wraps the pair in `AdaptiveGlassContainer` so the
//          Terminal pill participates in the Liquid Glass sampling region.
// Layer: View Component
// Exports: SidebarBottomActionBar
// Depends on: SwiftUI, SidebarActionPill, AdaptiveGlassModifier

import SwiftUI

struct SidebarBottomActionBar: View {
    let isChatEnabled: Bool
    let isCreatingThread: Bool
    let onTapChat: () -> Void
    let onTapTerminal: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                iOS26LiquidGlassLayout
            } else {
                iOS18FallbackLayout
            }
        }
        .padding(.horizontal, 16)
        // safeAreaBar(edge:.bottom) on iOS 26 already adds the system safe-area
        // inset, so we only need a tiny visual gap above/below the controls.
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Pills (built from the shared SidebarActionPill component)

    private var terminalPill: SidebarActionPill {
        SidebarActionPill(
            title: "Terminal",
            iconSystemName: "terminal.fill",
            style: .glass,
            hapticStyle: .light,
            accessibilityLabel: "Terminal",
            onTap: onTapTerminal
        )
    }

    private var chatPill: SidebarActionPill {
        SidebarActionPill(
            title: "Chat",
            iconSystemName: "square.and.pencil",
            style: .accent,
            isEnabled: isChatEnabled,
            isLoading: isCreatingThread,
            accessibilityLabel: "New chat",
            onTap: onTapChat
        )
    }

    // MARK: - Layouts

    private var iOS26LiquidGlassLayout: some View {
        // Groups the Terminal pill and Chat pill in the same native Liquid
        // Glass sampling region so Terminal's glass background stays
        // consistent with the surrounding sidebar surface.
        AdaptiveGlassContainer(spacing: 10) {
            pillRow
        }
    }

    private var iOS18FallbackLayout: some View {
        pillRow
    }

    private var pillRow: some View {
        HStack(spacing: 10) {
            terminalPill
            Spacer(minLength: 0)
            chatPill
        }
    }
}

#if DEBUG
#Preview {
    SidebarBottomActionBar(
        isChatEnabled: true,
        isCreatingThread: false,
        onTapChat: {},
        onTapTerminal: {}
    )
}
#endif
