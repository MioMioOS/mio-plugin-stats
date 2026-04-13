//
//  StatsPlugin.swift
//  StatsPlugin
//
//  Main plugin entry point. Wraps the analytics collector and stats view
//  as a native .bundle plugin for MioIsland.
//

import AppKit
import SwiftUI

final class StatsPlugin: NSObject, MioPlugin {
    var id: String { "stats" }
    var name: String { "Stats" }
    var icon: String { "chart.bar.fill" }
    var version: String { "1.0.0" }

    func activate() {
        Task { @MainActor in AnalyticsCollector.shared.start() }
    }

    func deactivate() {}

    func makeView() -> NSView {
        NSHostingView(rootView: StatsView())
    }
}
