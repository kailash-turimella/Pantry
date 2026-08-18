import SwiftData
import SwiftUI

@main
struct PantryApp: App {
    /// Single local-only SwiftData store. No CloudKit, no sync — everything lives on device.
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: InventoryItem.self, Recipe.self, RecipeIngredient.self, ShoppingItem.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("Could not open the local Pantry store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
