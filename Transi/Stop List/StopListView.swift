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
    @State private var searchResults: [Stop] = []
    @State private var searchText = ""
    @Binding var isPresented: Bool
    @Binding var stop: Stop

    let fuse = Fuse()

    init(stop: Binding<Stop>, isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _stop = stop
    }

    var body: some View {
        ZStack {
            Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading) {
                Text("Search").font(.system(size: 36.0, weight: .bold))
                    .padding(.leading, 24.0)
                    .padding(.top, 50.0)
                SearchBar(text: $searchText, placeholder: "Search")
                    .padding(.horizontal, 12.0)
                    .padding(.bottom, 10.0)
                ScrollViewReader { _ in
                    List(searchResults.isEmpty ? stopsListProvider.stops : searchResults) { stop in
                        if stop.id == searchResults.first?.id {
                            EmptyView().id("top")
                        }
                        Label {
                            HStack {
                                Text(stop.name ?? "Error").font(.headline)
                                Spacer()
                            }
                        }
                        icon: {
                            StopListIcon(stop.type)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            self.stop = stop
                            self.isPresented = false
                        }
                    }
                    .gesture(
                        DragGesture().onChanged { _ in
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    )
                    .introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17, .v18)) { list in
                        list.contentInset.top = -35.0
                    }
                    .onChange(of: searchText) { searchText in
                        if searchText.isEmpty {
                            searchResults = []
                        } else {
                            DispatchQueue.global(qos: .userInitiated).async {
                                let pattern = fuse.createPattern(from: searchText.normalize())
                                let scoredStops = stopsListProvider.stops.map { stop -> (Stop) in
                                    var newStop: Stop = stop
                                    let score = (stop.id < 0) ? -2 : fuse.search(pattern, in: stop.normalizedName)?.score
                                    newStop.score = score
                                    return newStop
                                }

                                let sortedFilteredStops = scoredStops.filter {
                                    $0.id < 0 || $0.score != nil
                                }.sorted(by: {
                                    $0.score ?? 0 < $1.score ?? 0
                                })

                                DispatchQueue.main.async {
                                    searchResults = sortedFilteredStops
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
