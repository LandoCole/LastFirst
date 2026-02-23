import Foundation

enum NavigationTab: String, CaseIterable, Identifiable {
    case home
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "books.vertical.fill"
        }
    }
}
