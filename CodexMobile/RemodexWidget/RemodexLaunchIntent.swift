// FILE: RemodexLaunchIntent.swift
// Purpose: OpenIntent used by the Control Center quick-launch button to bring
//          Remodex to the foreground. This file is compiled into both the app
//          and widget targets because Control Widgets require that membership
//          before an intent can open the parent app.
// Layer: Widget Extension

import AppIntents

enum RemodexLaunchTarget: String, AppEnum {
    case home

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Remodex")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .home: "Remodex"
    ]
}

struct RemodexLaunchIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Remodex"
    static var description = IntentDescription("Brings Remodex to the foreground.")

    @Parameter(title: "Target")
    var target: RemodexLaunchTarget

    init() {
        self.target = .home
    }

    init(target: RemodexLaunchTarget) {
        self.target = target
    }
}
