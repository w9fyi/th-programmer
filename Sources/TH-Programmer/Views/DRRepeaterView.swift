// DRRepeaterView.swift — D-STAR DR repeater list (placeholder)

import SwiftUI

struct DRRepeaterView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("DR Repeater List")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Viewing and editing the D-STAR repeater list is coming in a future update.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Text("In the meantime, use Menu 812 on the radio to import a Kenwood-format repeater list (.tsv) from a microSD card.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DR Repeater List. Not yet available. Use Menu 812 on the radio to import a Kenwood repeater list from a microSD card.")
    }
}
