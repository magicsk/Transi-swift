//
//  StopListIcon.swift
//  Transi
//
//  Created by magic_sk on 10/03/2023.
//

import SwiftUI


struct StopListIcon: View {
    
    let iconType: String?

    init(_ type: String?) {
        iconType = type
    }
    
    
    var body: some View {
        switch(iconType) {
        case "bus":
            Image(systemName: "bus.fill").foregroundColor(.red)
        case "regio_bus":
            Image(systemName: "bus.fill").foregroundColor(.yellow)
        case "train":
            Image(systemName: "tram.fill").foregroundColor(.blue)
        case "location":
            Image(systemName: "location.fill").foregroundColor(.blue)
        default:
            Image(systemName: "bus.fill").foregroundColor(.gray)
        }
        
    }
}

struct StopListIcon_Previews: PreviewProvider {
    static var previews: some View {
        StopListIcon("bus")
    }
}
