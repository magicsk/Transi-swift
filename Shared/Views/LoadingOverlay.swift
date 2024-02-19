//
//  LoadingOverlay.swift
//  Transi
//
//  Created by magic_sk on 22/12/2023.
//

import SwiftUI

struct LoadingOverlay<Content: View, Error: LocalizedError>: View {
    private var retryFunction: () -> Void
    private var cancelFunction: () -> Void
    private var retryButtonVisible: Bool = true
    private var topPadding: CGFloat = 0.0
    private var background = AnyView(Color.clear.background(.ultraThinMaterial).blur(radius: 10))
    private let delayedLoadingAnimation: Bool
    private var errorText: Error
    @Binding private var loading: Bool
    @Binding private var error: Bool
    @State private var loadingAnimation = false
    var content: () -> Content

    init(_ loading: Binding<Bool>, _ delayedLoadingAnimation: Bool = false, error: Binding<Bool> = .constant(false), errorText: Error = DefaultError.basic, @ViewBuilder content: @escaping () -> Content, retry: @escaping () -> Void = {}, cancel: @escaping () -> Void = {}) {
        _loading = loading
        _error = error
        self.errorText = errorText
        self.retryFunction = retry
        self.cancelFunction = cancel
        self.content = content
        self.delayedLoadingAnimation = delayedLoadingAnimation
    }

    var body: some View {
        ZStack {
            content()
            LoadingView()
                .background(background)
                .padding(.top, topPadding)
                .visible(delayedLoadingAnimation ? loadingAnimation : loading)
                .animation(.easeInOut(duration: 0.25), value: delayedLoadingAnimation ? loadingAnimation : loading)
        }
        .onChange(of: loading) { _ in
            if loading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if loading {
                        loadingAnimation = true
                    }
                }
            } else {
                loadingAnimation = false
            }
        }
        .alert(isPresented: $error, error: errorText) { _ in
            Button("Cancel") {
                cancelFunction()
            }
            Button("Retry") {
                retryFunction()
            }
        } message: { error in
            if let message = error.failureReason {
                Text(message)
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

    func overlayBackground<Background>(_ style: Background) -> LoadingOverlay where Background: View {
        var newView = self
        newView.background = AnyView(style)
        return newView
    }
}

// #Preview {
//    LoadingOverlay()
// }
