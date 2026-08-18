import SwiftData
import SwiftUI

/// Import a recipe from pasted text or an Instagram reel.
///
/// Both paths end at the same place: `RecipeEditorView` in `.confirm` mode.
/// Nothing Claude produces is written to the store until the user saves there.
struct RecipeImportView: View {
    enum Kind {
        case pastedText
        case instagramReel
    }

    @Environment(\.dismiss) private var dismiss

    let kind: Kind

    @State private var input = ""
    @State private var pastedCaption = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showManualCaptionFallback = false
    @State private var draft: RecipeDraft?
    @State private var fetchStrategy: String?

    var body: some View {
        NavigationStack {
            Form {
                inputSection

                if let errorMessage {
                    Section {
                        ErrorBanner(message: errorMessage) { Task { await run() } }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                if showManualCaptionFallback {
                    manualFallbackSection
                }

                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView().padding(.trailing, 6)
                            }
                            Text(isWorking ? workingLabel : "Extract recipe")
                            Spacer()
                        }
                    }
                    .disabled(isWorking || !canSubmit)
                }

                if !APIKeyStore.hasKey {
                    Section {
                        Label("Add an Anthropic API key in Settings first.", systemImage: "key")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $draft) { prefilled in
                RecipeEditorView(mode: .confirm(prefilled), onSaved: { dismiss() })
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var inputSection: some View {
        switch kind {
        case .pastedText:
            Section {
                TextField(
                    "Paste the recipe here — ingredients, method, whatever you have.",
                    text: $input,
                    axis: .vertical
                )
                .lineLimit(6...20)
            } header: {
                Text("Recipe text")
            } footer: {
                Text("Claude will pull out the ingredients and steps. You get to check everything before it's saved.")
            }

        case .instagramReel:
            Section {
                TextField("https://www.instagram.com/reel/…", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Reel link")
            } footer: {
                Text("Pantry reads the reel's caption and cover image. Recipes that are only spoken aloud in the video won't come through — paste the caption in yourself if that happens.")
            }
        }
    }

    private var manualFallbackSection: some View {
        Section {
            TextField("Paste the caption text here", text: $pastedCaption, axis: .vertical)
                .lineLimit(4...15)
            Button("Extract from this caption") {
                Task { await runFromPastedCaption() }
            }
            .disabled(pastedCaption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
        } header: {
            Text("Paste it manually")
        } footer: {
            Text("Open the reel in Instagram, copy the caption, and paste it here.")
        }
    }

    // MARK: - State

    private var title: String {
        switch kind {
        case .pastedText: return "Paste a recipe"
        case .instagramReel: return "Import a reel"
        }
    }

    private var workingLabel: String {
        switch kind {
        case .pastedText: return "Reading recipe…"
        case .instagramReel: return "Fetching reel…"
        }
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Work

    private func run() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            switch kind {
            case .pastedText:
                let parsed = try await RecipeTextParser.parse(input)
                draft = RecipeDraft(parsed: parsed, source: .pastedText)

            case .instagramReel:
                let result = try await ReelRecipeExtractor.importReel(from: input)
                fetchStrategy = result.content.strategy
                draft = RecipeDraft(
                    parsed: result.recipe,
                    source: .instagramReel,
                    sourceURL: input.trimmingCharacters(in: .whitespacesAndNewlines),
                    author: result.content.author
                )
            }
        } catch let error as InstagramError {
            errorMessage = error.localizedDescription
            // Every scrape route failed — offer the always-works path.
            withAnimation { showManualCaptionFallback = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runFromPastedCaption() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let result = try await ReelRecipeExtractor.extract(
                fromPastedCaption: pastedCaption,
                sourceURL: input
            )
            draft = RecipeDraft(
                parsed: result.recipe,
                source: .instagramReel,
                sourceURL: input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : input,
                author: nil
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `navigationDestination(item:)` needs Hashable; the draft is only ever used as
/// a one-shot navigation payload so identity is enough.
extension RecipeDraft: Hashable {
    static func == (lhs: RecipeDraft, rhs: RecipeDraft) -> Bool {
        lhs.title == rhs.title && lhs.ingredients.map(\.id) == rhs.ingredients.map(\.id)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(ingredients.map(\.id))
    }
}
