//
//  VirtualTableConnectionDetail.swift
//  Transi
//
//  Created by magic_sk on 01/03/2024.
//

import SwiftUI

struct VirtualTableConnectionDetail: View {
    var connection: Connection
    var vehicleInfo: VehicleInfo?
    var virtualTable: Bool

    init(_ connection: Connection, _ vehicleInfo: VehicleInfo?, _ virtualTable: Bool = false) {
        self.connection = connection
        self.vehicleInfo = vehicleInfo
        self.virtualTable = virtualTable
    }

    var body: some View {
        let busID = String(connection.busID.dropFirst(2))
        // The table's row follows the text size; the Live Activity keeps its fixed layout.
        let font: Font = virtualTable ? .caption : .system(size: 14.0)
        let smallFont: Font = virtualTable ? .caption : .system(size: 12.0)
        VStack {
            HStack(alignment: .bottom) {
                if connection.type == "online" && vehicleInfo != nil {
                    // Decorative: VoiceOver would read the asset name; the vehicle type is spelled out below.
                    Image(decorative: "\(vehicleInfo!.imgt)-\(String(vehicleInfo!.img).leftPadding(toLength: 4, withPad: "0"))")
                        .resizable()
                        .scaledToFit()
                        .maxHeight(virtualTable ? 40.0 : 55.0)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Expected departure: \(connection.departureTime)")
                        // Wraps in the app, where the text grows with the text size, rather than hide the time.
                        .lineLimit(virtualTable ? nil : 1)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: virtualTable)
                        .frame(minWidth: 180.0, alignment: .trailing)
                    if connection.type == "online" {
                        HStack {
                            StopIcon(color: .accent).scaleEffect(1.3)
                            Text(connection.lastStopName)
                                .fixedSize(horizontal: false, vertical: virtualTable)
                        }
                    }
                }
                .padding(.bottom, 3.0)
            }
            .font(font)
            HStack {
                if connection.type == "online" {
                    if let vehicleInfo = vehicleInfo {
                        HStack(spacing: 2.0) {
                            Text("\(vehicleInfo.type) #\(busID)")
                                .font(virtualTable ? .caption.weight(.light) : .system(size: 12.0, weight: .thin))
                                .lineLimit(1)
                            Image(systemName: vehicleInfo.ac ? "snowflake" : "snowflake.slash")
                                .symbolRenderingMode(.palette)
                                // Blue for air conditioning: the red accent made both states read as a warning.
                                .foregroundStyle(vehicleInfo.ac ? Color.systemBlue : Color.red, Color.gray)
                                .font(smallFont)
                                .accessibilityLabel(vehicleInfo.ac ? "Air-conditioned" : "Not air-conditioned")
                        }
                    }
                }
                Spacer()
                HStack(alignment: .center, spacing: 5.0) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(getDelayColor(connection.delay, connection.type))
                        .font(smallFont)
                        .accessibilityHidden(true)
                    Text(connection.delayText).font(font)
                }
            }
        }
    }
}

#Preview {
    VStack {
        VirtualTableConnectionDetail(Connection.example, VehicleInfo.example, true)
        Divider()
        VirtualTableConnectionDetail(Connection.example2, VehicleInfo.example2, false)
        Divider()
        VirtualTableConnectionDetail(Connection.example3, VehicleInfo.example, true)
    }
}
