//
//  StopListView.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import SwiftUI

struct StopListView: View {
    @State private var searchText = ""
    @State private var stopList = [Stop]()
    @Binding var isPresented: Bool
    @Binding var stopId: Int
    var dataProvider: DataProvider

    init(stopId: Binding<Int>, dataProviderProp: DataProvider, isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _stopId = stopId
        dataProvider = dataProviderProp
    }


    var body: some View {
        NavigationStack {
            List(searchResults) { stop in
                Label {
                    Text(stop.name ?? "Error").font(.headline)
                    Spacer()
                }
                icon: {
                    Image(systemName: "bus.fill").foregroundColor(.blue)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    self.stopId = stop.id ?? 1
                    dataProvider.changeStop(stopId: stop.id ?? 1)
                    self.isPresented = false
                }
            }
        }
            .searchable(text: $searchText)
    }
    var searchResults: [Stop] {
        if searchText.isEmpty {
            return dataProvider.stops
        } else {
            return dataProvider.stops.filter { $0.name?.lowercased().folding(options: .diacriticInsensitive, locale: .current).contains(searchText.folding(options: .diacriticInsensitive, locale: .current).lowercased()) ?? false || $0.id ?? 0 < 0 }
        }
    }

}

//struct StopListView_Previews: PreviewProvider {
//    static var previews: some View {
//        StopListView()
//    }
//}
