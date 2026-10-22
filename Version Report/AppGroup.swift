import Foundation

struct AppGroup: Codable, Identifiable {
    var id: String
    var name: String
    var appIDs: [String]

    init(name: String) {
        self.id = UUID().uuidString
        self.name = name
        self.appIDs = []
    }
}

enum SidebarSelection: Hashable {
    case allApps
    case group(String)
}
