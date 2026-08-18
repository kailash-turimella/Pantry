import SwiftData
import SwiftUI

/// Add or edit a single pantry item. Also the place where an expiry date gets
/// estimated when the user doesn't have one.
struct ItemEditorView: View {
    enum Mode {
        case create
        case edit(InventoryItem)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name = ""
    @State private var quantity = 1.0
    @State private var unit: MeasureUnit = .piece
    @State private var category: FoodCategory = .other
    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var notes = ""
    @State private var expirySource: ExpirySource = .none
    @State private var estimateNote: String?

    @State private var isEstimating = false
    @State private var estimateError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("1", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Picker("Unit", selection: $unit) {
                            ForEach(MeasureUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .labelsHidden()
                    }

                    Picker("Category", selection: $category) {
                        ForEach(FoodCategory.allCases) { category in
                            Label(category.displayName, systemImage: category.symbolName).tag(category)
                        }
                    }
                }

                expirySection

                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Edit item" : "New item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
        }
    }

    // MARK: - Expiry

    @ViewBuilder
    private var expirySection: some View {
        Section {
            Toggle("Has an expiry date", isOn: $hasExpiry.animation())

            if hasExpiry {
                DatePicker("Use by", selection: $expiryDate, displayedComponents: .date)
                    .onChange(of: expiryDate) { _, _ in
                        // A hand-picked date is no longer an estimate.
                        expirySource = .manual
                        estimateNote = nil
                    }
            }

            Button {
                Task { await estimateExpiry() }
            } label: {
                HStack {
                    Label(
                        hasExpiry ? "Re-estimate shelf life" : "Estimate shelf life",
                        systemImage: "sparkles"
                    )
                    Spacer()
                    if isEstimating { ProgressView() }
                }
            }
            .disabled(isEstimating || name.trimmingCharacters(in: .whitespaces).isEmpty)

        } header: {
            Text("Expiry")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let estimateNote {
                    Label(estimateNote, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                if let estimateError {
                    Text(estimateError).foregroundStyle(.orange)
                }
                if !hasExpiry {
                    Text("Leave this off and Pantry will estimate a date when you save — common items use a built-in table, anything unusual asks Claude.")
                }
            }
            .font(.footnote)
        }
    }

    private func estimateExpiry() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isEstimating = true
        estimateError = nil
        defer { isEstimating = false }

        guard let result = await ShelfLifeEstimator.estimate(for: trimmed, category: category) else {
            estimateError = "Couldn't estimate a date for this one — set it by hand."
            return
        }

        withAnimation {
            expiryDate = result.estimate.suggestedDate
            hasExpiry = true
            expirySource = .estimated
            estimateNote = result.estimate.note
        }
    }

    // MARK: - Persistence

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func loadExistingValues() {
        guard case .edit(let item) = mode else { return }
        name = item.name
        quantity = item.quantity
        unit = item.unit
        category = item.category
        notes = item.notes ?? ""
        expirySource = item.expirySource
        estimateNote = item.estimateNote
        if let date = item.expiryDate {
            hasExpiry = true
            expiryDate = date
        }
    }

    private func save() {
        Task {
            // No date and none requested: estimate one so the item still shows up
            // in "use soon" at the right time. This is the requirement that an
            // item without a printed date still gets a sensible shelf life.
            if !hasExpiry, expirySource != .manual {
                await estimateExpiry()
            }

            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

            switch mode {
            case .create:
                let item = InventoryItem(
                    name: trimmedName,
                    quantity: quantity,
                    unit: unit,
                    category: category,
                    expiryDate: hasExpiry ? expiryDate : nil,
                    expirySource: hasExpiry ? expirySource : .none,
                    estimateNote: estimateNote,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
                context.insert(item)
            case .edit(let item):
                item.name = trimmedName
                item.quantity = quantity
                item.unit = unit
                item.category = category
                item.expiryDate = hasExpiry ? expiryDate : nil
                item.expirySource = hasExpiry ? expirySource : .none
                item.estimateNote = estimateNote
                item.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            }

            try? context.save()
            dismiss()
        }
    }
}
