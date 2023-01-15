//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject var dataProvider = DataProvider()
    
    var body: some View {
        List(dataProvider.tabs) { tab in
            let departureTime = tab.departureTime - Int(NSDate().timeIntervalSince1970)
            let departureTimeText = departureTime > 60 ? "\(departureTime/60) min" : departureTime > 0 ? "<1 min" : "now"
            HStack {
                Text(tab.line).font(.headline).frame(width: 40)
                Text(tab.headsign).font(.subheadline)
                Spacer()
                Text(departureTimeText).font(.headline)
            }.padding(2.5)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
