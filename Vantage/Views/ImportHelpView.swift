import SwiftUI

/// Copy a ready-made prompt to paste into any AI chat tool, so the user doesn't have
/// to remember/type the JSON import schema themselves.
struct ImportHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Copy this into any AI chat tool — Claude, ChatGPT, whatever — fill in what you're looking for at the end, then save its reply as a .json file to import here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(SpotImportService.aiPromptTemplate)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.moduleBackground)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.moduleBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        copyToClipboard(SpotImportService.aiPromptTemplate)
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy Prompt", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.cobalt)
                }
                .padding()
            }
            .navigationTitle("Import from AI")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}
