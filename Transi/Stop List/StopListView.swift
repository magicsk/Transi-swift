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
    @State private var searchResults: [Stop]
    @State private var searchText = ""
    @Binding var isPresented: Bool
    @Binding var stop: Stop

    let fuse = Fuse()
    var stopList: [Stop]

    init(stop: Binding<Stop>, stopList: [Stop], isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _stop = stop
        self.stopList = stopList
        searchResults = stopList
    }

    var body: some View {
        SearchBar(text: $searchText, placeholder: "Search").padding(.horizontal, 12.0)
        ScrollViewReader { proxy in
            List(searchResults) { stop in
                if stop.id == searchResults.first?.id {
                    EmptyView().id("top")
                }
                Label {
                    Text(stop.name ?? "Error").font(.headline)
                    Spacer()
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
            .introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17)) { list in
                list.contentInset.top = -35.0
            }
            .onChange(of: searchText) { searchText in
                if searchText.isEmpty {
                    searchResults = stopList
                } else {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let pattern = fuse.createPattern(from: searchText.normalize())
                        let scoredStops = stopList.map { stop -> (Stop) in
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
                            self.searchResults = sortedFilteredStops
                            withAnimation {
                                proxy.scrollTo("top", anchor: .init(x: 0.0, y: 0.0))
                            }
                        }
                    }
                }
            }
        }
    }
}
