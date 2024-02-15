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
    let searchTextPublisher = PassthroughSubject<String, Never>()
    var stopList: [Stop]

    init(stop: Binding<Stop>, stopList: [Stop], isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _stop = stop
        self.stopList = stopList
        searchResults = stopList
    }

    var body: some View {
        AutoFocusedNavigationView($searchText) {
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
                    self.stop = stop
                    self.isPresented = false
                }
            }
            .introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17)) { list in
                list.contentInset.top = -30
            }
        }
        .disableAutocorrection(true)
        .textInputAutocapitalization(.never)
        .onChange(of: searchText) { searchText in
            searchTextPublisher.send(searchText)
        }
        .onReceive(
            searchTextPublisher
                .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        ) { _ in
            if searchText.isEmpty {
                searchResults = stopList
            } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    let pattern = fuse.createPattern(from: searchText.simplify())
                    let scoredStops = stopList.map { stop -> (Stop) in
                        var newStop: Stop = stop
                        let score = (stop.id < 0) ? -2 : fuse.search(pattern, in: stop.name?.simplify() ?? "")?.score
                        newStop.score = score
                        return newStop
                    }

                    let filteredStops = scoredStops.filter {
                        $0.id < 0 || $0.score != nil
                    }

                    let sortedStops = filteredStops.sorted(by: {
                        $0.score ?? 0 < $1.score ?? 0
                    })

                    DispatchQueue.main.async {
                        self.searchResults = sortedStops
                    }
                }
            }
        }
    }
}
