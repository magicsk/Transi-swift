//
//  DataProvider.swift
//  Transi
//
//  Created by magic_sk on 13/11/2022.
//

import Foundation
import SocketIO

final class DataProvider: ObservableObject {
    let manager = SocketManager(socketURL: URL(string: "https://imhd.sk/")!, config: [.path("/rt/sio2/"), .version(.two), .forceWebsockets(true)])
    
    @Published var tabs = [Tab]()
    init() {
        let socket = manager.defaultSocket
        let tabArgs = [94, "*"] as [Any]
        

        socket.on(clientEvent: .connect) {data, ack in
            print("socket connected")
            socket.emit("tabStart", tabArgs)
            socket.emit("infoStart")
        }

        socket.on("tabs") {data, ack in
            print("tabs")
            var tabsCopy = [Tab]()
            tabsCopy.append(contentsOf: self.tabs)
            if let platforms = data[0] as? [String: Any] {
                for (_, value) in platforms {
                    if let json = value as? [String: Any],
                       let platform = json["nastupiste"] as? Int,
                       let tabsJson = json["tab"] as? [Any] {
                        var tabs = [Tab]()
                        for object in tabsJson {
                            if let tabJson = object as? [String : Any] {
                                if let tab = Tab(json: tabJson, platform: platform) {
                                        tabs.append(tab)
                                }
                            }
                        }
                        tabsCopy.removeAll(where: { $0.platform == platform })
                        tabsCopy.append(contentsOf: tabs)
                    }
                }
            }
            DispatchQueue.main.async {
                self.tabs = tabsCopy.sorted(by: { $0.departureTime < $1.departureTime })
            }
        }
        socket.connect()
    }
}
