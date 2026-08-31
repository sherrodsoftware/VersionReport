//
//  KeychainHelper.swift
//  Version Report
//
//  Created by John Sherrod on 6/26/26.
//


import Foundation
import Security

final class KeychainHelper {

    static let shared = KeychainHelper()

    private let service = "com.sherrodsoftware.VersionReport"
    private let account = "teamsWebhookURL"

    private init() {}

    func saveTeamsWebhookURL(_ url: String) -> Bool {

        deleteTeamsWebhookURL()

        guard let data = url.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    func loadTeamsWebhookURL() -> String? {

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?

        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func deleteTeamsWebhookURL() {

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
