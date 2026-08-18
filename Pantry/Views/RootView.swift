import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Inventory", systemImage: "refrigerator") {
                InventoryListView()
            }
            Tab("Recipes", systemImage: "book") {
                RecipeListView()
            }
            Tab("Shopping", systemImage: "cart") {
                ShoppingListView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
