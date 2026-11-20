//
//  StopListView.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import Combine
import Fuse
import SwiftUI
import SwiftUIIntrospect

struct StopListView: View {
    @StateObject var stopsListProvider = GlobalController.stopsListProvider
    @ObservedObject var coordinator: ContentView.Coordinator
    @Binding var isPresented: Bool
    @Binding var stop: Stop
    @State var searchText = ""
    @State private var cachedFilteredStops: [Stop]? = nil
    /// Only stops the trip planner can route between: not railway stations outside IDS BK.
    let plannable: Bool

    let fuse = Fuse()

    init(
        coordinator: ContentView.Coordinator = .init(.init(selectedIndex: .constant(0))),
        stop: Binding<Stop> = .constant(.empty),
        isPresented: Binding<Bool> = .constant(false),
        plannable: Bool = false
    ) {
        self.coordinator = coordinator
        _isPresented = isPresented
        _stop = stop
        self.plannable = plannable
    }

    private var stops: [Stop] {
        plannable ? stopsListProvider.stops.filter { $0.stationId != nil } : stopsListProvider.stops
    }

    private var displayedItems: [Stop] {
        if let cachedFilteredStops = cachedFilteredStops { return cachedFilteredStops }
        let favoriteIds = Set(stopsListProvider.favoriteStopIds)
        // Actual location (id -1) stays first, then favorites, keeping the provider's order.
        let pinned = stops.filter { $0.id < 0 || favoriteIds.contains($0.id) }
        let others = stops.filter { $0.id >= 0 && !favoriteIds.contains($0.id) }
        return pinned + others
    }

    private func performSearch(_ text: String) {
        guard !text.isEmpty else {
            cachedFilteredStops = nil
            return
        }
        let pattern = fuse.createPattern(from: text.normalize())
        let scoredStops = stops.map { stop -> Stop in
            var newStop = stop
            let score = (stop.id < 0) ? -2 : fuse.search(pattern, in: stop.normalizedName)?.score
            newStop.score = score
            return newStop
        }
        cachedFilteredStops = scoredStops.filter {
            $0.id < 0 || $0.score != nil
        }.sorted(by: {
            $0.score ?? 0 < $1.score ?? 0
        })
    }

    var body: some View {
        ZStack {
            Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading) {
                if isPresented == true {
                    Text("Search").font(.largeTitle.bold())
                        .padding(.leading, 24.0)
                        .padding(.top, 45.0)
                        .padding(.bottom, -0.1)
                }
                ScrollViewReader { _ in
                    List(displayedItems) { stop in
                        let isFavorite = stopsListProvider.favoriteStopIds.contains(stop.id)
                        Label {
                            HStack {
                                Text(stop.name ?? "Error")
                                Spacer()
                                if isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .accessibilityLabel("Favorite")
                                }
                            }
                        }
                        icon: {
                            StopListIcon(stop.type)
                        }
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(.isButton)
                        .onTapGesture {
                            if isPresented == true {
                                self.stop = stop
                                self.isPresented = false
                            } else {
                                // Picking a stop pins it, even the one already shown; "Actual location" follows again.
                                GlobalController.virtualTable.switchLocationChanging(false)
                                GlobalController.virtualTable.changeStop(stop.id)
                                coordinator.parent.selectedIndex = 1
                            }
                        }
                        .swipeActions {
                            if stop.id > 0 {
                                Button {
                                    stopsListProvider.toggleFavorite(stop.id)
                                } label: {
                                    if isFavorite {
                                        Label("Remove Favorite", systemImage: "star.slash")
                                            .labelStyle(.iconOnly)
                                    } else {
                                        Label("Favorite", systemImage: "star")
                                    }
                                }
                                .tint(isFavorite ? .red : .yellow)
                            }
                        }
                    }

                    .gesture(
                        DragGesture().onChanged { _ in
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    )
                    .introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17, .v18, .v26)) { list in
                        if isPresented {
                            list.contentInset.top = -35.0
                        }
                    }
                }
            }
            if isPresented == true {
                VStack {
                    Spacer()
                    SearchBar(text: $searchText, placeholder: "Search")
                        .padding(.horizontal, 12.0)
                }
            }
        }
        .onChange(of: searchText) { newValue in
            if isPresented { performSearch(newValue) }
        }
        .onChange(of: coordinator.searchText) { newValue in
            if !isPresented { performSearch(newValue) }
        }
        // A search typed before the stop list loaded found nothing; run it again on the loaded list.
        .onChange(of: stopsListProvider.stops.count) { _ in
            performSearch(isPresented ? searchText : coordinator.searchText)
        }
        .onChange(of: isPresented) { newValue in
            if !newValue {
                cachedFilteredStops = nil
                searchText = ""
            }
        }
    }
}

#Preview {
    StopListView()
}
