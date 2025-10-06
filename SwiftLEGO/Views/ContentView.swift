import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionList.name, animation: .default) private var lists: [CollectionList]
    @State private var selectedList: CollectionList?

    var body: some View {
        NavigationSplitView {
            ListSidebarView(selection: $selectedList)
        } detail: {
            if let selectedList {
                SetCollectionView(list: selectedList)
                    .id(selectedList.persistentModelID)
            } else if let first = lists.first {
                SetCollectionView(list: first)
                    .onAppear {
                        selectedList = first
                    }
            } else {
                EmptyStateView(
                    icon: "square.stack.3d.up.slash",
                    title: "No Lists Yet",
                    message: "Create a list to start organizing your LEGO sets."
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedList == nil {
                selectedList = lists.first
            }
        }
    }
}

#Preview("App Root") {
    ContentView()
        .modelContainer(SwiftLEGOModelContainer.preview)
}
