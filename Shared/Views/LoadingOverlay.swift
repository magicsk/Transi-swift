//
//  LoadingOverlay.swift
//  Transi
//
//  Created by magic_sk on 22/12/2023.
//

import SwiftUI

struct LoadingOverlay<Content: View>: View {
    private var retryFunction: () -> Void
    private var retryButtonVisible: Bool = true
    private var topPadding: CGFloat = 0.0
    private var background = AnyShapeStyle(.ultraThinMaterial)
    private let delayedLoadingAnimation: Bool
    @Binding private var isLoading: Bool
    @Binding private var isError: Bool
    @Binding private var errorText: String
    @State private var loadingAnimation = false
    var content: () -> Content

    init(_ isLoading: Binding<Bool>, isError: Binding<Bool> = .constant(false), errorText: Binding<String> = .constant("Something went wrong"), retry: @escaping () -> Void = {}, _ delayedLoadingAnimation: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        _isLoading = isLoading
        _isError = isError
        _errorText = errorText
        self.retryFunction = retry
        self.content = content
        self.delayedLoadingAnimation = delayedLoadingAnimation
    }

    var body: some View {
        ZStack {
            content()
            VStack {
                if isError {
                    Text("Error").font(.system(size: 24.0, weight: .semibold))
                    Text(errorText)
                    if retryButtonVisible {
                        Button("Retry") {
                            retryFunction()
                        }
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.bottom, 2.5)
                    Text("Loading...")
                        .foregroundColor(.secondaryLabel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .padding(.top, topPadding)
            .visible(delayedLoadingAnimation ? loadingAnimation : isLoading)
            .animation(.easeInOut(duration: 0.25), value: delayedLoadingAnimation ? loadingAnimation : isLoading)
        }.onChange(of: isLoading) { _ in
            if isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if isLoading {
                        loadingAnimation = true
                    }
                }
            } else {
                loadingAnimation = false
            }
        }
    }
}

extension LoadingOverlay {
    func retryButton(_ isVisible: Bool = true) -> LoadingOverlay {
        var newView = self
        newView.retryButtonVisible = isVisible
        return newView
    }

    func paddingTop(_ length: CGFloat) -> LoadingOverlay {
        var newView = self
        newView.topPadding = length
        return newView
    }

    func overlayBackground<S>(_ style: S) -> LoadingOverlay where S: ShapeStyle {
        var newView = self
        newView.background = AnyShapeStyle(style)
        return newView
    }
}

// #Preview {
//    LoadingOverlay()
// }
