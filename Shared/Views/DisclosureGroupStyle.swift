//
//  DisclosureGroupStyle.swift
//  Transi
//
//  Created by magic_sk on 03.10.2025.
//

import SwiftUI

struct HideArrowDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 0) {
                configuration.label
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            configuration.isExpanded.toggle()
                        }
                    }

                if configuration.isExpanded {
                    configuration.content
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation {
                                configuration.isExpanded.toggle()
                            }
                        }
                }
            }
        }
}
