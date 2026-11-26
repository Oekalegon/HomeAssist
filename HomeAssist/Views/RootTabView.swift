import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Favourites", systemImage: "star.fill") { FavouritesView() }
            Tab("Rooms", systemImage: "square.grid.2x2") { RoomsView() }
        }
    }
}
