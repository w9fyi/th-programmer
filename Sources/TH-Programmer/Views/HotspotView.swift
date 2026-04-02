// HotspotView.swift — D-STAR hotspot list (placeholder)

import SwiftUI

struct HotspotView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Hotspot List")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Viewing and editing the hotspot list (up to 30 entries) is coming in a future update.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Text("Use Menu 230 on the radio to add or edit hotspot entries directly.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hotspot List. Not yet available. Use Menu 230 on the radio to manage hotspot entries.")
    }
}
