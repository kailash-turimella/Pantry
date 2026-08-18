import SwiftData
import SwiftUI

/// The one screen where recipes are created or changed — whether you typed it,
/// pasted it, or imported it from a reel.
struct RecipeEditorView: View {
    enum Mode {
        case create
        case edit(Recipe)
        /// Reviewing an AI extraction before it's saved.
        case confirm(RecipeDraft)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    /// Called after a successful save — lets the import flow dismiss its whole stack.
    var onSaved: (() -> Void)?

    @State private var draft = RecipeDraft()
    @State private var hasLoaded = false

    var body: some View {
        Form {
            if isConfirming {
                Section {
                    ReviewNoticeBanner(
                        message: "Claude pulled this out of the source. Check the ingredients and steps, fix anything it got wrong, then save."
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    if draft.isLowConfidence {
                        Label(
                            "Confidence was low — this one probably needs a once-over.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                    if let warning = draft.extractionWarning, !warning.isEmpty {
                        Label(warning, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Recipe") {
                TextField("Title", text: $draft.title)
                    .textInputAutocapitalization(.words)
                TextField("Short description (optional)", text: $draft.summary, axis: .vertical)
                    .lineLimit(1...3)
                HStack {
                    TextField("Serves", text: $draft.servingsText)
                        .keyboardType(.numberPad)
                    Divider()
                    TextField("Minutes", text: $draft.minutesText)
                        .keyboardType(.numberPad)
                }
            }

            ingredientsSection
            stepsSection
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!draft.isValid)
            }
            if case .create = mode {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadOnce)
    }

    // MARK: - Sections

    private var ingredientsSection: some View {
        Section {
            ForEach($draft.ingredients) { $ingredient in
                IngredientDraftRow(ingredient: $ingredient)
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            .onMove { draft.ingredients.move(fromOffsets: $0, toOffset: $1) }

            Button {
                withAnimation { draft.ingredients.append(IngredientDraft()) }
            } label: {
                Label("Add ingredient", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Ingredients")
        } footer: {
            Text("Keep names simple — \"chicken\", not \"2 chicken breasts, diced\" — so Pantry can match them against what you have.")
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(draft.steps.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                        .padding(.top, 8)
                    TextField("Step \(index + 1)", text: $draft.steps[index], axis: .vertical)
                        .lineLimit(1...6)
                }
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }

            Button {
                withAnimation { draft.steps.append("") }
            } label: {
                Label("Add step", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Method")
        }
    }

    // MARK: - Plumbing

    private var isConfirming: Bool {
        if case .confirm = mode { return true }
        return false
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New recipe"
        case .edit: return "Edit recipe"
        case .confirm: return "Check the recipe"
        }
    }

    private func loadOnce() {
        guard !hasLoaded else { return }
        hasLoaded = true
        switch mode {
        case .create:
            draft = RecipeDraft()
        case .edit(let recipe):
            draft = RecipeDraft(recipe: recipe)
        case .confirm(let prefilled):
            draft = prefilled
        }
    }

    private func save() {
        switch mode {
        case .create, .confirm:
            draft.insert(into: context)
        case .edit(let recipe):
            draft.apply(to: recipe, in: context)
        }
        try? context.save()
        onSaved?()
        dismiss()
    }
}

private struct IngredientDraftRow: View {
    @Binding var ingredient: IngredientDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Ingredient", text: $ingredient.name)
                Spacer(minLength: 8)
                TextField("Qty", text: $ingredient.quantityText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                Picker("Unit", selection: $ingredient.unit) {
                    ForEach(MeasureUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .labelsHidden()
            }
            HStack {
                TextField("Note (optional)", text: $ingredient.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Optional", isOn: $ingredient.isOptional)
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
        }
        .padding(.vertical, 2)
    }
}
