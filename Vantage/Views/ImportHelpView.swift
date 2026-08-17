import SwiftData
import SwiftUI

/// Copy a ready-made prompt to paste into any AI chat tool, so the user doesn't have
/// to remember/type the JSON import schema themselves — then paste the reply right
/// back here to import, no file-saving step required.
struct ImportHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var didCopy = false
    @State private var isImporting = false
    @State private var importSummary: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Copy this into any AI chat tool — Claude, ChatGPT, whatever — fill in what you're looking for at the end. When it replies, copy the reply and paste it back here.")
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

                    Divider()

                    Text("Got a reply? Paste it here to import directly — no need to save a file first.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await pasteAndImport() }
                    } label: {
                        if isImporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Paste & Import", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.shutterGreen)
                    .disabled(isImporting)
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
            .alert("Import", isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })) {
                Button("OK") { importSummary = nil }
            } message: {
                Text(importSummary ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 480)
        #endif
    }

    private func pasteAndImport() async {
        guard let text = pasteFromClipboard(), let data = text.data(using: .utf8) else {
            importSummary = "Nothing to paste — copy the AI's reply first."
            return
        }
        isImporting = true
        importSummary = await SpotImportService.importSpots(from: data, into: modelContext)
        isImporting = false
    }
}
