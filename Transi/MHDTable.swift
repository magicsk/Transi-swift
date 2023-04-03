//
//  List.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SwiftUI

struct TableView: View {
    var tabs: [Tab]
    
    init(_ _tabs: [Tab]) {
        tabs = _tabs
    }
    
    var body: some View {
        List(tabs) { tab in
            let departureTime = Int(tab.departureTime - Date().timeIntervalSince1970)
            let timeInMins = departureTime / 60
            let departureTimeFull = Date(timeIntervalSince1970: TimeInterval(tab.departureTime)).formatted(date: .omitted, time: .shortened)
            let departureTimeText = departureTime > 59 ?
            timeInMins > 59 ?
            departureTimeFull :
            "\(timeInMins) min" :
            departureTime > 0 ? "<1 min" : "now"
            let isDelay = tab.delay > 0
            let isInAdvance = tab.delay < 0
            let delayColor = isDelay ? Color.red : isInAdvance ? Color.purple : nil

            
            Label {
                HStack(alignment: .center){
                    VStack(alignment: .leading){
                        Text(tab.headsign).font(.subheadline)
                        Text(tab.lastStopName).font(.system(size: 10, weight: .light, design: .default))
                    }
                    Spacer()
                    VStack(alignment: .trailing){
                        Text(departureTimeText).font(.headline)
                        Text(tab.delayText ?? departureTimeFull).font(.system(size: 10, weight: .light, design: .default)).foregroundColor(delayColor ?? .none)
                    }
                }
            }
            icon: {
                Text(tab.line).font(.headline).frame(width: 40).offset(y: 6)
            }
        }
    }
}

struct TableView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
