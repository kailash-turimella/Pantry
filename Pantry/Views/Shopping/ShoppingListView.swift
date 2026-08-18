import SwiftData
import SwiftUI

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.addedAt) private var items: [ShoppingItem]
    @Query private var inventory: [InventoryItem]

    @State private var newItemName = ""
    @FocusState private var addFieldFocused: Bool

    /// An entry paired with the pantry item that already covers it, if any.
    private struct Entry: Identifiable {
        let item: ShoppingItem
        let owned: InventoryItem?
        var id: UUID { item.id }
    }

    private var entries: [Entry] {
        items.map { item in
            Entry(item: item, owned: IngredientMatcher.bestMatch(for: item.name, in: inventory))
        }
    }

    private var toBuy: [Entry] { entries.filter { $0.owned == nil && !$0.item.isChecked } }
    private var alreadyHave: [Entry] { entries.filter { $0.owned != nil && !$0.item.isChecked } }
    private var checked: [Entry] { entries.filter { $0.item.isChecked } }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        symbol: "cart",
                        title: "Shopping list is empty",
                        message: "Add things by hand, or open a recipe and tap \"Add missing to shopping list\"."
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Shopping")
            .safeAreaInset(edge: .bottom) { addBar }
            .toolbar {
                if !checked.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Move ticked items to inventory", systemImage: "refrigerator") {
                                moveCheckedToInventory()
                            }
                            Button("Clear ticked items", systemImage: "trash", role: .destructive) {
                                clearChecked()
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            if !toBuy.isEmpty {
                Section {
                    ForEach(toBuy) { entry in row(entry) }
                        .onDelete { delete(toBuy, at: $0) }
                } header: {
                    Label("Need to buy (\(toBuy.count))", systemImage: "cart.fill")
                }
            }

            if !alreadyHave.isEmpty {
                Section {
                    ForEach(alreadyHave) { entry in row(entry) }
                        .onDelete { delete(alreadyHave, at: $0) }
                } header: {
                    Label("Already in your kitchen (\(alreadyHave.count))", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } footer: {
                    Text("These matched something you already have, so you probably don't need to buy them.")
                }
            }

            if !checked.isEmpty {
                Section("Ticked off") {
                    ForEach(checked) { entry in row(entry) }
                        .onDelete { delete(checked, at: $0) }
                }
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { entry.item.isChecked.toggle(); try? context.save() }
            } label: {
                Image(systemName: entry.item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.item.isChecked ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.item.name)
                    .strikethrough(entry.item.isChecked)
                    .foregroundStyle(entry.item.isChecked ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let quantity = entry.item.displayQuantity {
                        Text(quantity)
                    }
                    if let recipe = entry.item.sourceRecipeTitle {
                        Text("· for \(recipe)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let owned = entry.owned {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("have \(owned.quantityDescription.isEmpty ? owned.name : owned.quantityDescription)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    ExpiryBadge(status: owned.status, compact: true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Add bar

    private var addBar: some View {
        HStack(spacing: 10) {
            TextField("Add an item", text: $newItemName)
                .textFieldStyle(.roundedBorder)
                .focused($addFieldFocused)
                .submitLabel(.done)
                .onSubmit(addItem)

            Button(action: addItem) {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(ShoppingItem(name: name))
        try? context.save()
        newItemName = ""
    }

    private func delete(_ source: [Entry], at offsets: IndexSet) {
        for index in offsets { context.delete(source[index].item) }
        try? context.save()
    }

    private func clearChecked() {
        for entry in checked { context.delete(entry.item) }
        try? context.save()
    }

    /// Closes the loop: you shopped, so the ticked things are now in the kitchen.
    /// Shelf life is estimated on the way in, same as any other add.
    private func moveCheckedToInventory() {
        let toMove = checked.map(\.item)
        Task {
            for item in toMove {
                let category = FoodCategory.other
                let estimate = await ShelfLifeEstimator.estimate(for: item.name, category: category)
                context.insert(
                    InventoryItem(
                        name: item.name,
                        quantity: item.quantity ?? 1,
                        unit: item.unit,
                        category: category,
                        expiryDate: estimate?.estimate.suggestedDate,
                        expirySource: estimate == nil ? .none : .estimated,
                        estimateNote: estimate?.estimate.note
                    )
                )
                context.delete(item)
            }
            try? context.save()
        }
    }
}
