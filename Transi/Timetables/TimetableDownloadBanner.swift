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
            let percent = timetableDb.downloadProgress.map { " \(Int($0 * 100))%" } ?? ""
            bannerView(
                "\(timetableDb.downloadDetail ?? "Downloading timetable database")\(percent)",
                icon: "arrow.down.circle",
                progress: timetableDb.downloadProgress
            )
        case .decompressing:
            bannerView(timetableDb.downloadDetail ?? "Installing database...", icon: "archivebox")
        case let .error(message):
            bannerView(message, icon: "exclamationmark.triangle", isError: true)
        default:
            EmptyView()
        }
    }

    private func bannerView(_ text: String, icon: String, isError: Bool = false, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if isError {
                    Image(systemName: icon)
                        .foregroundColor(.orange)
                } else if let progress {
                    ProgressView(value: progress)
                        .frame(width: 40)
                } else {
                    ProgressView()
                }
                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(.secondaryLabel)
            }
            if !isError {
                if #available(iOS 26.0, *) {
                    EmptyView()
                } else {
                    Text("Keep Transi open until this finishes.")
                        .font(.caption)
                        .foregroundColor(.secondaryLabel)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.secondarySystemBackground)
        .cornerRadius(10)
        .padding(.horizontal, 24)
    }
}
