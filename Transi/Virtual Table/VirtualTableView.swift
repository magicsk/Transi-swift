//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI
import SwiftUIX

struct VirtualTableView: View {
    @StateObject var virtualTableController = GlobalController.virtualTable
    @State private var showStopList = false
    @State private var stop: Stop = .empty
    @AppStorage(Stored.displaySocketStatus) var displaySocketStatus = false
    @AppStorage(Stored.displayClockOnTable) var displayClock = true

    private let updateTabBarApperance: () -> Void

    init(_ updateTabBarApperance: @escaping () -> Void) {
        self.updateTabBarApperance = updateTabBarApperance
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VirtualTableList()
                VStack {
                    Spacer()
                    CocoaTextField("Search", text: $stop.name)
                        .alignmentGuide(VerticalAlignment.center, computeValue: { d in d[.bottom] })
                        .disabled(true)
                        .padding(.vertical, 10.0)
                        .padding(.horizontal, 16.0)
                        .background(.ultraThinMaterial)
                        .cornerRadius(14.0, style: .circular)
                        .padding(.horizontal, 24.0)
                        .offset(y: -16.0)
                        .onPress {
                            print("tapped")
                            self.showStopList = true
                        }
                        .sheet(isPresented: $showStopList) {
                            StopListView(stop: self.$stop, isPresented: self.$showStopList)
                        }.onChange(of: stop) { stop in
                            virtualTableController.changeStop(stop.id)
                        }
                }
            }
            .navigationTitle(Text(virtualTableController.currentStop.name ?? "Loading..."))
            .navigationBarItems(
                leading: Text(displaySocketStatus ? virtualTableController.socketStatus : ""),
                trailing: displayClock ? AnyView(TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clockStringFromDate(context.date))
                }) : AnyView(EmptyView())
            )
        }
        .onAppear {
            updateTabBarApperance()
        }
    }
}

// struct VirtualTableView_Previews: PreviewProvider {
//    static var previews: some View {
//        VirtualTableView()
//    }
// }
