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
    @Binding var isPresented: Bool
    @Binding var stop: Stop
    @State private var searchResults: [Stop]
    let fuse = Fuse()
    var stopList: [Stop]
    let searchTextPublisher = PassthroughSubject<String, Never>()

    init(stop: Binding<Stop>, stopList: [Stop], isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _stop = stop
        self.stopList = stopList
        searchResults = stopList
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
                    self.stop = stop
                    self.isPresented = false
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer)
        .disableAutocorrection(true)
        .textInputAutocapitalization(.never)
        .onChange(of: searchText) { searchText in
            searchTextPublisher.send(searchText)
        }
        .onReceive(
            searchTextPublisher
                .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
        ) { _ in
            if searchText.isEmpty {
                searchResults = stopList
            } else {
                DispatchQueue.global(qos: .userInteractive).async {
                    let pattern = fuse.createPattern(from: searchText.simplify())
                    let scoredStops = stopList
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
