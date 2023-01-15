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
    var stopsList: DataProvider

    init(stopId: Binding<Int>, stopList: DataProvider, isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _stopId = stopId
        stopsList = stopList
    }


    var body: some View {
        NavigationStack {
            List(searchResults) { stop in
                Label {
                    Text(stop.name ?? "Error").font(.headline).onTapGesture {
                        self.stopId = stop.id ?? 1
                        stopsList.changeStop(stopId: stop.id ?? 1)
                        self.isPresented = false
                    }
                }
                icon: {
                    Text(stop.type ?? "bus").font(.headline).frame(width: 40)
                }

            }
        }
            .searchable(text: $searchText)
    }
    var searchResults: [Stop] {
        if searchText.isEmpty {
            return stopsList.stops
        } else {
            return stopsList.stops.filter { $0.name?.contains(searchText) ?? false }
        }
    }

}

//struct StopListView_Previews: PreviewProvider {
//    static var previews: some View {
//        StopListView()
//    }
//}
