//
//  StopListView.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import SwiftUI
import FuzzyFind

struct StopListView: View {
    @State private var searchText = ""
    @State private var stopList = [Stop]()
    @Binding var isPresented: Bool
    @Binding var stopId: Int
    @State private var searchResults: [Stop]
    var dataProvider: DataProvider
    
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
            
            if searchText.isEmpty {
                searchResults = dataProvider.stops
            } else {
                DispatchQueue.global(qos: .userInteractive).async {
                    self.searchResults = dataProvider.stops.filter {
                        $0.id ?? 0 < 0 || bestMatch(query: searchText.folding(options: .diacriticInsensitive, locale: .current).lowercased(), input: $0.name?.lowercased().folding(options: .diacriticInsensitive, locale: .current) ?? "") != nil
                    }
                }
            }
        }
        
    }
}
