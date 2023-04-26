//
//  StopListView.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import Combine
import Fuse
import SwiftUI

struct StopListView: View {
    @State private var searchText = ""
    @State private var stopList = [Stop]()
    @Binding var isPresented: Bool
    @Binding var stopId: Int
    @State private var searchResults: [Stop]
    let fuse = Fuse()
    var dataProvider: DataProvider
    let searchTextPublisher = PassthroughSubject<String, Never>()

    init(stopId: Binding<Int>, dataProviderProp: DataProvider, isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _stopId = stopId
        dataProvider = dataProviderProp
        searchResults = dataProvider.stops
    }

    var body: some View {
        NavigationView {
            List(searchResults) { stop in
                Label {
                    Text(stop.name ?? "Error").font(.headline)
                    Spacer()
                }
            icon: {
                    StopListIcon(stop.type)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dataProvider.changeStop(stopId: stop.id ?? 0)
                    self.isPresented = false
                }
            }
        }
        .searchable(text: $searchText)
        .disableAutocorrection(true)
        .onChange(of: searchText) { searchText in
            searchTextPublisher.send(searchText)
        }
        .onReceive(
            searchTextPublisher
                .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
        ) { _ in
            if searchText.isEmpty {
                searchResults = dataProvider.stops
            } else {
                DispatchQueue.global(qos: .userInteractive).async {
                    let pattern = fuse.createPattern(from: searchText.simplify())
                    let scoredStops = dataProvider.stops
                        .map { stop -> (Stop) in
                            var newStop: Stop = stop
                            let score = (stop.id ?? 0 < 0) ? -2 : fuse.search(pattern, in: stop.name?.simplify() ?? "")?.score
                            newStop.score = score
                            return newStop
                        }
                    self.searchResults = scoredStops.filter {
                        $0.id ?? 0 < 0 || $0.score != nil
                    }
                    .sorted(by: {
                        $0.score ?? 0 < $1.score ?? 0
                    })
                }
            }
        }
    }
}
