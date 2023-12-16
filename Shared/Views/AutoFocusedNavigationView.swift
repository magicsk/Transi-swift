//
//  AutoFocusedNavigationView.swift
//  Transi
//
//  Created by magic_sk on 16/12/2023.
//

import SwiftUI

struct AutoFocusedNavigationView <Content: View>: View {
    @State private var searchBarFocus = true
    @Binding var searchText: String
    var content: () -> Content

    init(_ searchText: Binding<String>, @ViewBuilder content: @escaping () -> Content) {
        _searchText = searchText
        self.content = content
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            NavigationView {
                content()
            }.searchable(text: $searchText, isPresented: $searchBarFocus, placement: .navigationBarDrawer(displayMode: .always))
        } else {
            NavigationView {
                content()
            }.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        }
    }
}

// #Preview {
//    AutoFocusedNavigationView()
// }
