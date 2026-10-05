//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import Combine
import SwiftUI
import UIKit

struct ContentView: UIViewControllerRepresentable {
    @Binding var selectedIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func changeTab(_ tag: Int) {
        selectedIndex = tag
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = UITabBarController()

        let plannerVC = UIHostingController(rootView: TripPlannerView())
        plannerVC.tabBarItem = UITabBarItem(title: "Planner", image: UIImage(systemName: "tram"), tag: 0)

        let tableVC = UIHostingController(rootView: VirtualTableView())
        tableVC.tabBarItem = UITabBarItem(title: "Table", image: UIImage(systemName: "clock.arrow.2.circlepath"), tag: 1)

        let timetablesVC = UIHostingController(rootView: TimetablesView())
        timetablesVC.tabBarItem = UITabBarItem(title: "Timetables", image: UIImage(systemName: "calendar"), tag: 2)

        let mapVC = UIHostingController(rootView: MapKitView(changeTab).ignoresSafeArea())
        mapVC.tabBarItem = UITabBarItem(title: "Map", image: UIImage(systemName: "map"), tag: 3)

        let searchVC = HybridSearchViewController(coordinator: context.coordinator)
        searchVC.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 4)

        tabBarController.delegate = context.coordinator
        if #available(iOS 26.0, *) {
            // Since the iOS 27 SDK, Search sits apart from the tab bar only as a prominent search tab,
            // no longer as a search tab bar item.
            let tabs = ([plannerVC, tableVC, timetablesVC, mapVC] as [UIViewController]).map { controller in
                let item = controller.tabBarItem!
                return UITab(title: item.title ?? "", image: item.image, identifier: "\(item.tag)") { _ in controller }
            }
            let searchTab = UISearchTab { _ in searchVC }
            tabBarController.tabs = tabs + [searchTab]
            #if compiler(>=6.4) // The iOS 27 SDK (Xcode 27); CI still builds with Xcode 26.
                if #available(iOS 27.0, *) {
                    tabBarController.prominentTabIdentifier = searchTab.identifier
                }
            #endif
        } else {
            tabBarController.viewControllers = [plannerVC, tableVC, timetablesVC, mapVC, searchVC]
        }

        return tabBarController
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context _: Context) {
        // Setting even an unchanged index makes iOS 27 refresh the tab's floating bar inside this update,
        // which invalidates this view again and loops until the watchdog kills the app.
        let selectionChanged = uiViewController.selectedIndex != selectedIndex
        if selectionChanged {
            uiViewController.selectedIndex = selectedIndex
        }
        if #available(iOS 26.0, *) {} else {
            let tabBarAppearance = UITabBarAppearance()
            if uiViewController.selectedIndex == 3 {
                tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            } else {
                tabBarAppearance.configureWithTransparentBackground()
            }
            uiViewController.tabBar.scrollEdgeAppearance = tabBarAppearance
        }

        if selectionChanged, let searchVC = uiViewController.selectedViewController as? HybridSearchViewController {
            DispatchQueue.main.async {
                searchVC.searchController?.searchBar.becomeFirstResponder()
            }
        }
    }

    class Coordinator: NSObject, ObservableObject, UISearchResultsUpdating, UITabBarControllerDelegate {
        @Published var searchText = ""
        var parent: ContentView

        init(_ parent: ContentView) {
            self.parent = parent
        }

        func updateSearchResults(for searchController: UISearchController) {
            searchText = searchController.searchBar.text ?? ""
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            shouldSelect(tabBarController.viewControllers?.firstIndex(of: viewController), in: tabBarController)
        }

        @available(iOS 18.0, *)
        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            shouldSelect(tabBarController.tabs.firstIndex(of: tab), in: tabBarController)
        }

        /// Routes a tap through the binding, so the selection changes in one place.
        private func shouldSelect(_ newIndex: Int?, in tabBarController: UITabBarController) -> Bool {
            guard let newIndex, newIndex != tabBarController.selectedIndex else {
                return true
            }
            parent.selectedIndex = newIndex
            return false
        }
    }
}

class HybridSearchViewController: UINavigationController, UISearchBarDelegate {
    private let coordinator: ContentView.Coordinator
    private let hostingController: UIHostingController<StopListView>!
    var searchController: UISearchController!

    init(coordinator: ContentView.Coordinator) {
        self.coordinator = coordinator
        hostingController = UIHostingController(rootView: StopListView(coordinator: coordinator))

        super.init(rootViewController: hostingController)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = coordinator
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.delegate = self
        searchController.searchBar.placeholder = "Search"

        hostingController.navigationItem.title = "Stops"
        hostingController.navigationItem.searchController = searchController
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hostingController.navigationController?.navigationBar.prefersLargeTitles = true
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        DispatchQueue.main.async {
            searchBar.searchTextField.selectAll(nil)
        }
    }
}
