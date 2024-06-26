//
//  VirtualTableDetail.swift
//  Transi
//
//  Created by magic_sk on 08/04/2023.
//

import SwiftUI

struct VirtualTableDetail: View {
    var tab: Tab
    var vehicleInfo: VehicleInfo?
    var platformLabels: [PlatformLabel]?

    init(_ tab: Tab, _ platformLabels: [PlatformLabel]?, _ vehicleInfo: VehicleInfo?) {
        self.tab = tab
        self.vehicleInfo = vehicleInfo
        self.platformLabels = platformLabels
    }

    var body: some View {
        let busID = String(tab.busID.dropFirst(2))

        NavigationView {
            VStack(alignment: .leading, spacing: 6.0) {
                Text("\(tab.stuck ? "would" : "will") depart in \(tab.departureTimeRemaining) at \(tab.departureTime)\nfrom platform \(getPlatformLabel(platformLabels, tab.platform))")
                    .font(.system(size: 24.0))
                HStack(spacing: 4.0) {
                    Text("\(tab.stuck ? "Stucked" : "Last seen") on \(tab.lastStopName)").font(.system(size: 12.0))
                    Image("stop").resizable(resizingMode: .stretch).frame(width: 7.0, height: 10.0)
                    Text(tab.delayText).font(.system(size: 12))
                    Image(systemName: "circle.fill")
                        .foregroundColor(getDelayColor(tab.delay, tab.type))
                        .font(.system(size: 12.0))
                }
                if vehicleInfo != nil {
                    HStack(spacing: 4.0) {
                        Text("Vehicle is \(vehicleInfo!.ac ? "" : "not ")air conditioned").font(.system(size: 12.0))
                        Image(systemName: vehicleInfo!.ac ? "snowflake" : "snowflake.slash")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(vehicleInfo!.ac ? Color.accent : Color.red, Color.gray)
                            .font(.system(size: 14.0))
                    }

                    AsyncImage(url: URL(string: "\(GlobalController.iApiBaseUrl)/ba/media/\(vehicleInfo!.imgt)/\(String(vehicleInfo!.img).leftPadding(toLength: 8, withPad: "0"))/\(busID)")) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: UIScreen.main.bounds.size.width - 44.0).padding(.top, 60.0)
                    Text("\(vehicleInfo!.type) #\(busID)")
                        .font(.system(size: 10.0, weight: .thin))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 2.0)
            .padding(.horizontal, 22.0)
            .navigationBarItems(
                leading: HStack {
                    LineText(tab.line)
                    Text(tab.headsign).font(.largeTitle.bold())
                },
                trailing: Image(tab.stuck ? "exclamationmark.triangle.fill" : "")
                    .foregroundColor(.yellow)
                    .font(.system(size: 28))
            )
        }
    }
}

struct VirtualTableDetailPreview: PreviewProvider {
    static var previews: some View {
        VirtualTableDetail(Tab.example, [PlatformLabel.example] , VehicleInfo.example)
    }
}
