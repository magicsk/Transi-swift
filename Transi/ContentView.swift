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
        tabBarController.viewControllers = [plannerVC, tableVC, timetablesVC, mapVC, searchVC]

        return tabBarController
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context _: Context) {
        uiViewController.selectedIndex = selectedIndex
        if #available(iOS 26.0, *) {} else {
            let tabBarAppearance = UITabBarAppearance()
            if uiViewController.selectedIndex == 3 {
                tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            } else {
                tabBarAppearance.configureWithTransparentBackground()
            }
            uiViewController.tabBar.scrollEdgeAppearance = tabBarAppearance
        }

        if let searchVC = uiViewController.viewControllers?[selectedIndex] as? HybridSearchViewController {
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
            guard let newIndex = tabBarController.viewControllers?.firstIndex(of: viewController) else {
                return true
            }

            if newIndex != tabBarController.selectedIndex {
                parent.selectedIndex = newIndex
                return false
            }

            return true
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
}
