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

    let fuse = Fuse()

    init(
        coordinator: ContentView.Coordinator = .init(.init(selectedIndex: .constant(0))),
        stop: Binding<Stop> = .constant(.empty),
        isPresented: Binding<Bool> = .constant(false)
    ) {
        self.coordinator = coordinator
        _isPresented = isPresented
        _stop = stop
    }

    private var displayedItems: [Stop] {
        cachedFilteredStops ?? stopsListProvider.stops
    }

    private func performSearch(_ text: String) {
        guard !text.isEmpty else {
            cachedFilteredStops = nil
            return
        }
        let pattern = fuse.createPattern(from: text.normalize())
        let scoredStops = stopsListProvider.stops.map { stop -> Stop in
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
                    Text("Search").font(.system(size: 36.0, weight: .bold))
                        .padding(.leading, 24.0)
                        .padding(.top, 45.0)
                        .padding(.bottom, -0.1)
                }
                ScrollViewReader { _ in
                    List(displayedItems) { stop in
                        Label {
                            HStack {
                                Text(stop.name ?? "Error")
                                Spacer()
                            }
                        }
                        icon: {
                            StopListIcon(stop.type)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isPresented == true {
                                self.stop = stop
                                self.isPresented = false
                            } else {
                                GlobalController.virtualTable.changeStop(stop.id)
                                coordinator.parent.selectedIndex = 1
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
