//
//  ChangelogView.swift
//  Transi
//
//  Created by magic_sk on 03/10/2026.
//

import SwiftUI

struct Changelog: Identifiable {
    struct Category {
        let title: String
        var items: [String] = []

        var icon: String {
            let title = title.lowercased()
            if title.contains("feature") { return "sparkles" }
            if title.contains("fix") { return "ladybug" }
            if title.contains("improvement") { return "bolt" }
            return "ellipsis.circle"
        }
    }

    let version: String
    let categories: [Category]
    var id: String { version }

    /// Parses GitHub release notes: `## Heading` lines start a category, other lines become its items.
    init(version: String, markdown: String) {
        var categories: [Category] = []
        for line in markdown.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                categories.append(Category(title: line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
            } else if !line.isEmpty, !categories.isEmpty {
                let item = line.hasPrefix("- ") ? line.dropFirst(2) : Substring(line)
                categories[categories.count - 1].items.append(item.prefix(1).uppercased() + item.dropFirst())
            }
        }
        self.version = version
        self.categories = categories.filter { !$0.items.isEmpty }
    }
}

extension Changelog {
    private struct GitHubRelease: Decodable {
        let tagName: String // required so a 404 error body fails decoding
        let body: String?
    }

    /// Calls `completion` on the main thread with the running version's release notes until `ChangelogView` has been shown.
    static func fetchIfUpdated(completion: @escaping (Changelog) -> Void) {
        let defaults = UserDefaults.standard
        let lastVersion = defaults.string(forKey: Stored.changelogVersion)
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              lastVersion != version else { return }

        // Cached stops mean an earlier version already ran; skip the changelog on a fresh install.
        if lastVersion == nil, defaults.string(forKey: Stored.stopsVersion) == nil {
            defaults.set(version, forKey: Stored.changelogVersion)
            return
        }

        let url = URL(string: "https://api.github.com/repos/magicsk/Transi-swift/releases/tags/v\(version)")!
        fetchData(request: URLRequest(url: url), type: GitHubRelease.self) { result in
            // ponytail: offline or not-yet-published release retries on the next launch
            guard case .success(let release) = result else { return }
            let changelog = Changelog(version: version, markdown: release.body ?? "")
            if changelog.categories.isEmpty {
                defaults.set(version, forKey: Stored.changelogVersion)
            } else {
                completion(changelog)
            }
        }
    }
}

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss
    let changelog: Changelog

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                VStack(spacing: 8) {
                    Text("What's New in Transi")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Version \(changelog.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 56)

                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(changelog.categories.enumerated()), id: \.offset) { _, category in
                        categoryRow(category)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .continueBar { dismiss() }
        // Marked seen only once actually presented, so a blocked presentation retries next launch.
        .onAppear { UserDefaults.standard.set(changelog.version, forKey: Stored.changelogVersion) }
    }

    private func categoryRow(_ category: Changelog.Category) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: category.icon)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(category.title)
                    .font(.headline)
                ForEach(Array(category.items.enumerated()), id: \.offset) { _, item in
                    Text((try? AttributedString(markdown: item)) ?? AttributedString(item))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    @ViewBuilder
    func continueBar(action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .padding(.horizontal, 32)
        .padding(.vertical, 16)

        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom) { button.buttonStyle(.glassProminent) }
                .scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            safeAreaInset(edge: .bottom) { button.buttonStyle(.borderedProminent).background(.bar) }
        }
    }
}

#Preview {
    ChangelogView(changelog: Changelog(version: "0.10.0", markdown: """
        ## Features
        - add new bus artwork

        ## Bugfixes
        - fix recent trip persistence, paging order and date controls
        """))
}
