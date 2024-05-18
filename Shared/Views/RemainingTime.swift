//
//  RemainingTime.swift
//  Transi
//
//  Created by magic_sk on 27/02/2024.
//

import SwiftUI

struct RemainingTime: View {
    var time: String
    
    init(_ time: String) {
        self.time = time
    }
    
    var body: some View {
        if time == "now" {
            NowIndicator()
        } else if time == "~now" {
            NowIndicator(true)
        } else {
            Text(time).font(.headline)
        }
    }
}

#Preview {
    RemainingTime("1 min")
}
