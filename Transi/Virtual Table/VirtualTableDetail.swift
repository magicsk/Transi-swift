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
    var delayColor: Color = .gray

    private let iApiBaseUrl = (Bundle.main.infoDictionary?["I_API_URL"] as? String)!

    init(_ _tab: Tab, _vehicleInfo: VehicleInfo?) {
        tab = _tab
        vehicleInfo = _vehicleInfo
        switch tab.delay {
            case 0...1:
                delayColor = Color.green

            case 2...3:
                delayColor = Color.orange

            case 4...999:
                delayColor = Color.red

            default:
                delayColor = Color.purple
        }
    }

    var body: some View {
        let busID = String(tab.busID.dropFirst(2))

        NavigationView {
            VStack(alignment: .leading, spacing: 6.0) {
                Text("\(tab.stuck ? "would" : "will") depart in \(tab.departureTimeRemaining) at \(tab.departureTime)")
                    .font(.system(size: 24))
                HStack(spacing: 4.0) {
                    Text("\(tab.stuck ? "Stucked" : "Last seen") on \(tab.lastStopName)").font(.system(size: 12))
                    Image("stop").resizable(resizingMode: .stretch).frame(width: 7.0, height: 10.0)
                    Text(tab.delayText).font(.system(size: 12))
                    Image(systemName: "circle.fill")
                        .foregroundColor(delayColor)
                        .font(.system(size: 12))
                }
                if vehicleInfo != nil {
                    HStack(spacing: 4.0) {
                        Text("Vehicle is \(vehicleInfo!.ac ? "" : "not ")air conditioned").font(.system(size: 12))
                        Image(systemName: vehicleInfo!.ac ? "snowflake" : "snowflake.slash")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(vehicleInfo!.ac ? Color.accentColor : Color.red, Color.gray)
                            .font(.system(size: 14))
                    }

                    AsyncImage(url: URL(string: "\(iApiBaseUrl)/ba/media/\(vehicleInfo!.imgt)/\(String(vehicleInfo!.img).leftPadding(toLength: 8, withPad: "0"))/\(busID)")) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: .infinity).padding(.top, 60.0)
                    Text("\(vehicleInfo!.type) #\(busID)")
                        .font(.system(size: 10.0, weight: .thin))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 18.0)
            #if !os(macOS)
                .navigationBarItems(
                    leading: HStack {
                        Text(tab.line).font(.largeTitle.bold())
                        Text(tab.headsign).font(.largeTitle.bold())
                    },
                    trailing: Image(tab.stuck ? "exclamationmark.triangle.fill" : "")
                        .foregroundColor(.yellow)
                        .font(.system(size: 28))
                )
            #endif
        }
    }
}

struct VirtualTableDetailPreview: PreviewProvider {
    static var previews: some View {
        VirtualTableDetail(Tab.example, _vehicleInfo: VehicleInfo.example)
    }
}
