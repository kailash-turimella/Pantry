import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var inventory: [InventoryItem]
    @Query private var shoppingItems: [ShoppingItem]

    let recipe: Recipe

    @State private var showingEditor = false
    @State private var addedToList = false

    private var match: RecipeMatch {
        RecipeRanker.match(recipe: recipe, inventory: inventory)
    }

    var body: some View {
        List {
            headerSection
            ingredientsSection
            if !recipe.steps.isEmpty { stepsSection }
            sourceSection
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                RecipeEditorView(mode: .edit(recipe))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingEditor = false }
                        }
                    }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary).font(.callout)
            }

            HStack(spacing: 16) {
                if let servings = recipe.servings {
                    Label("Serves \(servings)", systemImage: "person.2")
                }
                if let minutes = recipe.totalMinutes {
                    Label("\(minutes) min", systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !match.expiringUsed.isEmpty {
                Label(
                    "Uses \(match.expiringUsed.map(\.name).joined(separator: ", ")) — due soon",
                    systemImage: "flame.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(recipe.orderedIngredients) { ingredient in
                let owned = match.matched.first { $0.ingredient.id == ingredient.id }?.item
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: owned != nil ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(owned != nil ? Color.green : Color.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.displayLine)
                        if let owned {
                            Text("have: \(owned.name) · \(owned.status.label)")
                                .font(.caption2)
                                .foregroundStyle(owned.status.tint)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        } header: {
            HStack {
                Text("Ingredients")
                Spacer()
                Text("\(match.matched.count)/\(recipe.ingredients.count) in stock")
                    .font(.caption)
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if !match.missing.isEmpty {
                Button {
                    addMissingToShoppingList()
                } label: {
                    Label(
                        addedToList ? "Added to shopping list" : "Add \(match.missing.count) missing to shopping list",
                        systemImage: addedToList ? "checkmark" : "cart.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(addedToList)
                .padding(.top, 8)
            }
        }
    }

    private var stepsSection: some View {
        Section("Method") {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor, in: Circle())
                    Text(step)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var sourceSection: some View {
        Section("Source") {
            Label(recipe.source.displayName, systemImage: recipe.source.symbolName)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let author = recipe.sourceAuthor {
                Text("@\(author)").font(.footnote).foregroundStyle(.secondary)
            }
            if let urlString = recipe.sourceURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label("Open original", systemImage: "arrow.up.right.square")
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Actions

    private func addMissingToShoppingList() {
        for ingredient in match.missing {
            // Don't add something that's already on the list.
            let alreadyListed = shoppingItems.contains {
                IngredientMatcher.matches($0.name, ingredient.name)
            }
            guard !alreadyListed else { continue }

            context.insert(
                ShoppingItem(
                    name: ingredient.name,
                    quantity: ingredient.quantity,
                    unit: ingredient.unit,
                    sourceRecipeTitle: recipe.title
                )
            )
        }
        try? context.save()
        withAnimation { addedToList = true }
    }
}
