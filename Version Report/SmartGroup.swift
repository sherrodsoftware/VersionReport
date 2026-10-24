import Foundation

enum SmartGroupMatch: String, Codable, CaseIterable {
    case all = "all"
    case any = "any"

    var displayName: String {
        switch self {
        case .all: return "all"
        case .any: return "any"
        }
    }
}

enum SmartGroupField: String, Codable, CaseIterable {
    case sourceType = "sourceType"
    case hasUnreadUpdate = "hasUnreadUpdate"
    case lastChecked = "lastChecked"
    case lastUpdated = "lastUpdated"

    var displayName: String {
        switch self {
        case .sourceType: return "Source"
        case .hasUnreadUpdate: return "Update Status"
        case .lastChecked: return "Last Checked"
        case .lastUpdated: return "Last Updated"
        }
    }
}

enum SmartGroupOperator: String, Codable, CaseIterable {
    case equals = "equals"
    case notEquals = "notEquals"
    case isTrue = "isTrue"
    case isFalse = "isFalse"
    case lessThanDaysAgo = "lessThanDaysAgo"
    case moreThanDaysAgo = "moreThanDaysAgo"
    case never = "never"

    var displayName: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .isTrue: return "has unread update"
        case .isFalse: return "is up to date"
        case .lessThanDaysAgo: return "within the last (days)"
        case .moreThanDaysAgo: return "more than (days) ago"
        case .never: return "has never been checked"
        }
    }
}

struct SmartGroupCriterion: Codable, Identifiable {
    var id: String = UUID().uuidString
    var field: SmartGroupField
    var op: SmartGroupOperator
    var value: String

    static func defaultCriterion() -> SmartGroupCriterion {
        SmartGroupCriterion(field: .sourceType, op: .equals, value: "Homebrew Cask")
    }
}

struct SmartGroup: Codable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var match: SmartGroupMatch
    var criteria: [SmartGroupCriterion]

    func evaluate(_ app: MonitoredApp) -> Bool {
        let results = criteria.map { criterion -> Bool in
            switch criterion.field {
            case .sourceType:
                switch criterion.op {
                case .equals:    return app.sourceType == criterion.value
                case .notEquals: return app.sourceType != criterion.value
                default:         return false
                }

            case .hasUnreadUpdate:
                switch criterion.op {
                case .isTrue:  return app.hasUnreadUpdate
                case .isFalse: return !app.hasUnreadUpdate
                default:       return false
                }

            case .lastChecked:
                switch criterion.op {
                case .never:
                    return app.lastChecked == nil
                case .lessThanDaysAgo:
                    guard let days = Double(criterion.value), let date = app.lastChecked else { return false }
                    return Date().timeIntervalSince(date) < days * 86400
                case .moreThanDaysAgo:
                    guard let days = Double(criterion.value), let date = app.lastChecked else { return false }
                    return Date().timeIntervalSince(date) > days * 86400
                default:
                    return false
                }

            case .lastUpdated:
                switch criterion.op {
                case .never:
                    return app.lastUpdated == nil
                case .lessThanDaysAgo:
                    guard let days = Double(criterion.value), let date = app.lastUpdated else { return false }
                    return Date().timeIntervalSince(date) < days * 86400
                case .moreThanDaysAgo:
                    guard let days = Double(criterion.value), let date = app.lastUpdated else { return false }
                    return Date().timeIntervalSince(date) > days * 86400
                default:
                    return false
                }
            }
        }

        return match == .all ? results.allSatisfy { $0 } : results.contains { $0 }
    }
}
