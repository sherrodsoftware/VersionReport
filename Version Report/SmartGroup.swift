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
    case vendor = "vendor"
    case hasUnreadUpdate = "hasUnreadUpdate"
    case updateCycle = "updateCycle"
    case installedVersion = "installedVersion"
    case lastChecked = "lastChecked"
    case lastUpdated = "lastUpdated"

    var displayName: String {
        switch self {
        case .sourceType: return "Source"
        case .vendor: return "Vendor"
        case .updateCycle: return "Update Cycle"
        case .installedVersion: return "Installed Version"
        case .hasUnreadUpdate: return "Update Status"
        case .lastChecked: return "Last Checked"
        case .lastUpdated: return "Last Updated"
        }
    }
}

enum SmartGroupOperator: String, Codable, CaseIterable {
    case equals = "equals"
    case notEquals = "notEquals"
    case contains = "contains"
    case isNotSet = "isNotSet"
    case isOverdue = "isOverdue"
    case isOnSchedule = "isOnSchedule"
    case isUnknown = "isUnknown"
    case installedIsOutdated = "installedIsOutdated"
    case installedIsCurrent = "installedIsCurrent"
    case isInstalled = "isInstalled"
    case isNotInstalled = "isNotInstalled"
    case isTrue = "isTrue"
    case isFalse = "isFalse"
    case lessThanDaysAgo = "lessThanDaysAgo"
    case moreThanDaysAgo = "moreThanDaysAgo"
    case never = "never"

    var displayName: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .isNotSet: return "is not set"
        case .isOverdue: return "is overdue"
        case .isOnSchedule: return "is on schedule"
        case .isUnknown: return "is unknown"
        case .installedIsOutdated: return "is out of date"
        case .installedIsCurrent: return "is current"
        case .isInstalled: return "is installed"
        case .isNotInstalled: return "is not installed"
        case .isTrue: return "has unread update"
        case .isFalse: return "is up to date"
        case .lessThanDaysAgo: return "within the last (days)"
        case .moreThanDaysAgo: return "more than (days) ago"
        case .never: return "has never been checked"
        }
    }
}

struct SmartGroupCriterion: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var field: SmartGroupField
    var op: SmartGroupOperator
    var value: String

    static func defaultCriterion() -> SmartGroupCriterion {
        SmartGroupCriterion(field: .sourceType, op: .equals, value: "Homebrew Cask")
    }
}

struct SmartGroup: Codable, Identifiable, Equatable {
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

            case .vendor:
                let needle = criterion.value.trimmingCharacters(in: .whitespacesAndNewlines)
                switch criterion.op {
                case .isNotSet:
                    return app.vendor == nil
                case .equals:
                    guard let vendor = app.vendor else { return false }
                    return vendor.localizedCaseInsensitiveCompare(needle) == .orderedSame
                case .notEquals:
                    guard let vendor = app.vendor else { return true }
                    return vendor.localizedCaseInsensitiveCompare(needle) != .orderedSame
                case .contains:
                    guard let vendor = app.vendor, !needle.isEmpty else { return false }
                    return vendor.localizedCaseInsensitiveContains(needle)
                default:
                    return false
                }

            case .updateCycle:
                switch criterion.op {
                case .isOverdue:    return app.isOverdue
                case .isOnSchedule: return app.updateCycle.map { !$0.isOverdue } ?? false
                case .isUnknown:    return app.updateCycle == nil
                default:            return false
                }

            case .installedVersion:
                switch criterion.op {
                case .installedIsOutdated: return app.installStatus == .outdated
                case .installedIsCurrent:  return app.installStatus == .upToDate
                case .isInstalled:         return app.installed != nil
                case .isNotInstalled:      return app.installed == nil
                default:                   return false
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
