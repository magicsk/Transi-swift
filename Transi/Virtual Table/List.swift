//
//  List.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SwiftUI

struct VirtualTableList: View {
    @ObservedObject var dataProvider: DataProvider
    
    init(_ _dataProvider: DataProvider) {
        dataProvider = _dataProvider
    }
    
    var body: some View {
        List(dataProvider.tabs) { tab in
            let vehicleInfo = dataProvider.vehicleInfo.first(where: { $0.issi == tab.busID })
            VirtualTableListItem(tab, _vehicleInfo: vehicleInfo )
        }
    }
}

struct VirtualTableList_Previews: PreviewProvider {
    static var previews: some View {
        @ObservedObject var dataProvider = DataProvider()
        VirtualTableList(dataProvider)
    }
}
