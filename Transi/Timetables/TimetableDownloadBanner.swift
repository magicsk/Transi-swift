//
//  TimetableDownloadBanner.swift
//  Transi
//
//  Created by magic_sk on 26/02/2026.
//

import SwiftUI

struct TimetableDownloadBanner: View {
    @ObservedObject var timetableDb = GlobalController.timetableDatabase

    var body: some View {
        switch timetableDb.downloadState {
        case .checking:
            bannerView("Checking for updates...", icon: "arrow.triangle.2.circlepath")
        case .downloading:
            bannerView("Downloading timetable database...", icon: "arrow.down.circle")
        case .decompressing:
            bannerView("Decompressing database...", icon: "archivebox")
        case let .error(message):
            bannerView(message, icon: "exclamationmark.triangle", isError: true)
        default:
            EmptyView()
        }
    }

    private func bannerView(_ text: String, icon: String, isError: Bool = false) -> some View {
        HStack(spacing: 10) {
            if isError {
                Image(systemName: icon)
                    .foregroundColor(.orange)
            } else {
                ProgressView()
            }
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .padding(.horizontal, 24)
    }
}
