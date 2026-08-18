import SwiftData
import SwiftUI

struct InventoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]

    @State private var searchText = ""
    @State private var showingManualAdd = false
    @State private var showingPhotoAdd = false
    @State private var editingItem: InventoryItem?

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        symbol: "refrigerator",
                        title: "Nothing in the kitchen yet",
                        message: "Add what you have and Pantry will keep track of what needs using up.",
                        actionTitle: "Add from a photo",
                        action: { showingPhotoAdd = true }
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Inventory")
            .searchable(text: $searchText, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add from photo", systemImage: "camera") { showingPhotoAdd = true }
                        Button("Add manually", systemImage: "square.and.pencil") { showingManualAdd = true }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingManualAdd) {
                ItemEditorView(mode: .create)
            }
            .sheet(isPresented: $showingPhotoAdd) {
                PhotoAddFlowView()
            }
            .sheet(item: $editingItem) { item in
                ItemEditorView(mode: .edit(item))
            }
        }
        .task(id: items.count) { await rescheduleNotifications() }
    }

    // MARK: - List

    private var list: some View {
        List {
            if !useSoon.isEmpty && searchText.isEmpty {
                Section {
                    ForEach(useSoon) { item in
                        row(for: item)
                    }
                } header: {
                    Label("Use soon", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Ordered by what goes off first. The Recipes tab ranks meals that use these up.")
                }
            }

            ForEach(groupedCategories, id: \.self) { category in
                Section(category.displayName) {
                    ForEach(grouped[category] ?? []) { item in
                        row(for: item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for item: InventoryItem) -> some View {
        Button {
            editingItem = item
        } label: {
            InventoryRow(item: item)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                markUsed(item)
            } label: {
                Label("Used", systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    // MARK: - Data shaping

    private var filtered: [InventoryItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var useSoon: [InventoryItem] {
        filtered
            .filter { $0.status.needsAttention }
            .sorted { $0.status < $1.status }
    }

    /// Everything not already surfaced in "Use soon", grouped by category.
    private var grouped: [FoodCategory: [InventoryItem]] {
        let remaining = searchText.isEmpty
            ? filtered.filter { !$0.status.needsAttention }
            : filtered
        return Dictionary(grouping: remaining, by: \.category)
            .mapValues { $0.sorted { $0.status < $1.status } }
    }

    private var groupedCategories: [FoodCategory] {
        grouped.keys.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Actions

    private func delete(_ item: InventoryItem) {
        context.delete(item)
        try? context.save()
    }

    /// "Used" and "deleted" are the same operation today, but they're separate
    /// affordances because they mean different things to the user — and this is
    /// where a "cooked with" history would hook in later.
    private func markUsed(_ item: InventoryItem) {
        context.delete(item)
        try? context.save()
    }

    private func rescheduleNotifications() async {
        await NotificationScheduler.reschedule(for: items)
    }
}

struct InventoryRow: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.category)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if !item.quantityDescription.isEmpty {
                        Text(item.quantityDescription)
                    }
                    if item.expirySource == .estimated {
                        Label("estimated", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            ExpiryBadge(status: item.status)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
