//
//  TripPlannerSearchInputs.swift
//  Transi
//
//  Created by magic_sk on 04/02/2024.
//

import SwiftUI

struct TripPlannerSearchInputs: View {
    @Binding private var from: Stop
    @Binding private var to: Stop
    @Binding private var lastField: String
    @Binding private var showStopList: Bool

    init(from: Binding<Stop>, to: Binding<Stop>, lastField: Binding<String>, showStopList: Binding<Bool>) {
        _from = from
        _to = to
        _lastField = lastField
        _showStopList = showStopList
    }

    var body: some View {
        VStack {
            HStack(spacing: .zero) {
                getInputIcon(from.type ?? "")
                TextField(text: $from.name.toUnwrapped(defaultValue: "")) {
                    Text("From").foregroundColor(.placeholderText)
                }
            }
            .disabled(true)
            .onTapGestureOnBackground {
                lastField = "from"
                showStopList = true
            }
            .onPress {
                lastField = "from"
                showStopList = true
            }
            .padding(.bottom, 5.0)
            Divider().padding(.leading, 40.0).padding(.bottom, 15.0)
            HStack(spacing: .zero) {
                getInputIcon(to.type ?? "")
                TextField(text: $to.name.toUnwrapped(defaultValue: "")) {
                    Text("To").foregroundColor(.placeholderText)
                }
            }
            .disabled(true)
            .onTapGestureOnBackground {
                lastField = "to"
                showStopList = true
            }
            .onPress {
                lastField = "to"
                showStopList = true
            }
        }.modifier(ListStackModifier())
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
        VStack{
            TripPlannerSearchInputs(
                from: .constant(.empty),
                to: .constant(.example),
                lastField: .constant("to"),
                showStopList: .constant(false)
            )
        }
    }
}
