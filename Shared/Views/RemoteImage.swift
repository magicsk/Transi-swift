//
//  RemoteImage.swift
//  Transi
//
//  Created by magic_sk on 29/02/2024.
//


import SwiftUI
import Combine

class ImageLoader: ObservableObject {
    @Published var image: UIImage?

    init(url: URL) {
        loadImage(from: url)
    }

    private func loadImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async {
                self.image = UIImage(data: data)
            }
        }.resume()
    }
}

struct RemoteImageView: View {
    @ObservedObject var imageLoader: ImageLoader

    init(url: URL) {
        imageLoader = ImageLoader(url: url)
    }

    var body: some View {
        Image(uiImage: imageLoader.image ?? UIImage())
            .resizable()
            .scaledToFit()
    }
}
