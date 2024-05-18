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
        switch iconType {
            case "bus":
                Image(systemName: "bus.fill").foregroundColor(.systemRed)
            case "regio_bus":
                Image(systemName: "bus.fill").foregroundColor(.systemYellow)
            case "train":
                Image(systemName: "tram.fill").foregroundColor(.systemBlue)
            case "location":
                Image(systemName: "location.fill").foregroundColor(.systemBlue)
            default:
                Image(systemName: "bus.fill").foregroundColor(.systemGray)
        }
    }
}

struct StopListIcon_Previews: PreviewProvider {
    static var previews: some View {
        StopListIcon("bus")
    }
}
