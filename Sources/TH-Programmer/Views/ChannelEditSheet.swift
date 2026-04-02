// ChannelEditSheet.swift — Sheet wrapper for ChannelEditView with Done/Cancel

import SwiftUI

struct ChannelEditSheet: View {
    let channelNumber: Int
    @EnvironmentObject var store: RadioStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft:    ChannelMemory = ChannelMemory(number: 0)
    @State private var original: ChannelMemory = ChannelMemory(number: 0)

    var body: some View {
        NavigationStack {
            ChannelEditView(channel: $draft)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            // Restore original data — modifiedChannels badge may linger but data is correct
                            store.memoryMap?.setChannel(original)
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            store.commitChannelEdit(draft)
                            dismiss()
                        }
                    }
                }
        }
        .frame(minWidth: 480, minHeight: 540)
        .onAppear {
            if let ch = store.memoryMap?.channel(number: channelNumber) {
                draft    = ch
                original = ch
            }
        }
    }
}
