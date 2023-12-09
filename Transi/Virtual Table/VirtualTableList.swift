//
//  VirtualTableList.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SwiftUI

struct VirtualTableList: View {
    @ObservedObject var dataProvider: DataProvider
    
    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
    }
    
    var body: some View {
        List(dataProvider.tabs) { tab in
            let vehicleInfo = dataProvider.vehicleInfo.first(where: { $0.issi == tab.busID })
            VirtualTableListItem(tab, dataProvider.currentStop.platformLabels, vehicleInfo )
        }
    }
}

//struct VirtualTableList_Previews: PreviewProvider {
//    static var previews: some View {
//        @ObservedObject var dataProvider = DataProvider()
//        VirtualTableList(dataProvider)
//    }
//}
