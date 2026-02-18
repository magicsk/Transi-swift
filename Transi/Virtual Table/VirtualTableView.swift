//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SocketIO
import SwiftUI

struct VirtualTableView: View {
    @Environment(\.openURL) var openURL
    @StateObject var virtualTableController = GlobalController.virtualTable
    @State private var showStopList = false
    @State private var showInfoTexts = false
    @AppStorage(Stored.displayClockOnTable) var displayClock = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VirtualTableList()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    StatusIndicator(status: virtualTableController.socketStatus)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        virtualTableController.markInfoTextsRead()
                        showInfoTexts = true
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(
                                virtualTableController.unreadInfoCount > 0 ? .orange : .gray
                            )
                    }
                }
                if displayClock {
                    ToolbarItem(placement: .topBarTrailing) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(clockStringFromDate(context.date))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 5.0)
                        .onTapGesture {
                            virtualTableController.disconnect(reconnect: true)
                        }
                    }
                }
            }
            .sheet(isPresented: $showInfoTexts) {
                NavigationStack {
                    Group {
                        if virtualTableController.infoTexts.isEmpty {
                            VStack {
                                Spacer()
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                    .padding(.bottom, 8)
                                Text("There are no service information available now.")
                                    .foregroundColor(.secondaryLabel)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .padding()
                        } else {
                            List {
                                ForEach(virtualTableController.infoTexts, id: \.self) { text in
                                    Label {
                                        Text(text)
                                    } icon: {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Service Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showInfoTexts = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct StatusIndicator: View {
    let status: SocketIOStatus
    @State private var animating = false

    var body: some View {
        VStack(spacing: 3) {
            Text(status.description)
                .font(.system(size: 9))
                .foregroundColor(.gray)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gray.opacity(0.25))
                    if status == .connecting {
                        Capsule()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: animating ? geo.size.width * 0.7 : 0)
                    }
                }
            }
            .frame(height: 1.5)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: status) { newStatus in
            if newStatus == .connecting {
                animating = false
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animating = true
                }
            } else {
                withAnimation(.default) {
                    animating = false
                }
            }
        }
        .onAppear {
            if status == .connecting {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
        }
    }
}
