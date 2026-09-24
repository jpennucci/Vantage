import SwiftData
import SwiftUI

/// Copy a ready-made prompt to paste into any AI chat tool, so the user doesn't have
/// to remember/type the JSON import schema themselves — then paste the reply right
/// back here to import, no file-saving step required.
struct ImportHelpView: View {
    /// When set ("Find More Near This Trip"), the prompt is narrowed to this trip's
    /// area and imported spots are added to it instead of a new trip.
    var trip: TripModel? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [LocationEntryModel]
    @State private var area: TripArea?
    @State private var isLoadingArea = false
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

                    if let trip {
                        Label(
                            isLoadingArea ? "Reading where \(trip.name) is…" : "Narrowed to the area around \(trip.name) — new spots will be added to that trip.",
                            systemImage: "scope"
                        )
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.cobaltLight)
                    }

                    Text(prompt)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.moduleBackground)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppTheme.moduleBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        copyToClipboard(prompt)
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy Prompt", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.cobalt)
                    .disabled(isLoadingArea)

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
            .navigationTitle(trip.map { "Find More Near \($0.name)" } ?? "Import from AI")
            .task(id: trip?.id) {
                guard let trip else { return }
                isLoadingArea = true
                area = await SpotImportService.area(of: allEntries.filter { $0.tripID == trip.id })
                isLoadingArea = false
            }
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

    private var prompt: String {
        SpotImportService.aiPrompt(near: area)
    }

    private func pasteAndImport() async {
        guard let text = pasteFromClipboard(), let data = text.data(using: .utf8) else {
            importSummary = "Nothing to paste — copy the AI's reply first."
            return
        }
        isImporting = true
        let result = await SpotImportService.importSpotsWithDetails(from: data, into: modelContext, addingTo: trip)
        importSummary = result.summary + (result.imported.isEmpty ? "" : " Pictures will appear on the new spots over the next minute.")
        isImporting = false
        // Keeps running after this sheet closes.
        let context = modelContext
        Task { @MainActor in
            for item in result.imported {
                await SpotPictureService.addPicture(to: item.entry, imageURL: item.imageURL, in: context)
            }
        }
    }
}
