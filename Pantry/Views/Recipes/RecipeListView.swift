import SwiftData
import SwiftUI

struct RecipeListView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case suggested = "Use what's expiring"
        case all = "All recipes"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @Query private var inventory: [InventoryItem]

    @State private var filter: Filter = .suggested
    @State private var showingManualAdd = false
    @State private var showingTextImport = false
    @State private var showingReelImport = false

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    EmptyStateView(
                        symbol: "book.closed",
                        title: "No recipes yet",
                        message: "Add recipes by hand, paste one in, or import one from an Instagram reel. Pantry will then suggest what to cook based on what's about to go off.",
                        actionTitle: "Import from a reel",
                        action: { showingReelImport = true }
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("From an Instagram reel", systemImage: "play.rectangle.on.rectangle") {
                            showingReelImport = true
                        }
                        Button("Paste recipe text", systemImage: "doc.on.clipboard") {
                            showingTextImport = true
                        }
                        Button("Write it myself", systemImage: "square.and.pencil") {
                            showingManualAdd = true
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .sheet(isPresented: $showingManualAdd) {
                NavigationStack { RecipeEditorView(mode: .create) }
            }
            .sheet(isPresented: $showingTextImport) {
                RecipeImportView(kind: .pastedText)
            }
            .sheet(isPresented: $showingReelImport) {
                RecipeImportView(kind: .instagramReel)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if filter == .suggested {
                suggestedSection
            } else {
                Section {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeRow(match: RecipeRanker.match(recipe: recipe, inventory: inventory))
                        }
                    }
                    .onDelete(perform: deleteFromAll)
                }
            }
        }
    }

    @ViewBuilder
    private var suggestedSection: some View {
        let ranked = RecipeRanker.rank(recipes: recipes, inventory: inventory)
        let usingExpiring = ranked.filter { !$0.expiringUsed.isEmpty }
        let rest = ranked.filter { $0.expiringUsed.isEmpty }

        if usingExpiring.isEmpty {
            Section {
                Text(inventory.contains(where: { $0.status.needsAttention })
                     ? "None of your recipes use what's expiring right now."
                     : "Nothing in your kitchen needs using up urgently.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(usingExpiring) { match in
                    NavigationLink(value: match.recipe) {
                        RecipeRow(match: match)
                    }
                }
            } header: {
                Label("Cook these first", systemImage: "flame")
                    .foregroundStyle(.orange)
            } footer: {
                Text("Ranked by how much expiring food each one uses up, and how much of it you already have.")
            }
        }

        if !rest.isEmpty {
            Section("Everything else") {
                ForEach(rest) { match in
                    NavigationLink(value: match.recipe) {
                        RecipeRow(match: match)
                    }
                }
            }
        }
    }

    private func deleteFromAll(at offsets: IndexSet) {
        for index in offsets { context.delete(recipes[index]) }
        try? context.save()
    }
}

struct RecipeRow: View {
    let match: RecipeMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: match.recipe.source.symbolName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(match.recipe.title)
                    .font(.body.weight(.medium))
            }

            HStack(spacing: 8) {
                if match.canCookNow {
                    Label("Can make now", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Missing \(match.missing.count)", systemImage: "cart")
                        .foregroundStyle(.secondary)
                }

                if let soonest = match.expiringUsed.min(by: { $0.status < $1.status }) {
                    Text("·").foregroundStyle(.secondary)
                    Label(
                        match.expiringUsed.count == 1
                            ? "uses \(soonest.name)"
                            : "uses \(match.expiringUsed.count) expiring",
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .foregroundStyle(soonest.status.tint)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
