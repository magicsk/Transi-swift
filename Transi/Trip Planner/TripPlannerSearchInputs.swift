//
//  TripPlannerSearchInputs.swift
//  Transi
//
//  Created by magic_sk on 04/02/2024.
//

import SwiftUI

struct TripPlannerSearchInputs: View {
    @Binding private var lastField: String
    @Binding private var showStopList: Bool
    @StateObject var tripPlannerController = GlobalController.tripPlanner

    init(lastField: Binding<String>, showStopList: Binding<Bool>) {
        _lastField = lastField
        _showStopList = showStopList
    }

    var body: some View {
        VStack(spacing: .zero) {
            HStack(spacing: .zero) {
                Button {
                    lastField = "from"
                    showStopList = true
                } label: {
                    HStack(spacing: .zero) {
                        getInputIcon(tripPlannerController.from.type ?? "")
                        Text(tripPlannerController.from.name ?? "From")
                            .foregroundColor(
                                tripPlannerController.from.name?.isEmpty == false
                                    ? .label : .placeholderText
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 44.0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "From, \(tripPlannerController.from.name ?? "not selected")"
                )

                Button {
                    switchStops()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.label)
                        .frame(width: 44.0, height: 44.0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch stops")
            }
            Divider().padding(.leading, 40.0)
            Button {
                lastField = "to"
                showStopList = true
            } label: {
                HStack(spacing: .zero) {
                    getInputIcon(tripPlannerController.to.type ?? "")
                    Text(tripPlannerController.to.name ?? "To")
                        .foregroundColor(
                            tripPlannerController.to.name?.isEmpty == false
                                ? .label : .placeholderText
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44.0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("To, \(tripPlannerController.to.name ?? "not selected")")
        }
        .modifier(ListStackModifier())
    }

    func switchStops() {
        let temp = tripPlannerController.from
        tripPlannerController.from = tripPlannerController.to
        tripPlannerController.to = temp
        tripPlannerController.fetchTrip()
    }

    func getInputIcon(_ iconType: String) -> some View {
        switch iconType {
        case "bus":
            return CircleIcon("bus.fill", .white, .systemRed)
        case "regio_bus":
            return CircleIcon("bus.fill", .white, .systemYellow)
        case "train":
            return CircleIcon("tram.fill", .white, .systemBlue)
        case "location":
            return CircleIcon("location.fill", .white, .systemBlue)
        default:
            return CircleIcon("circle.inset.filled", .white, .systemFill)
        }
    }
}

#Preview {
    ZStack {
        Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
        VStack {
            TripPlannerSearchInputs(
                lastField: .constant("to"),
                showStopList: .constant(false)
            )
        }
    }
}
