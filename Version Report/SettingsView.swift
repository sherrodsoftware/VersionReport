//
//  SettingsView.swift
//  Version Report
//
//  Created by John Sherrod on 6/26/26.
//


import SwiftUI

struct SettingsView: View {

    @AppStorage("checkFrequency") private var checkFrequencyRaw = CheckFrequency.onLaunch.rawValue
    @State private var teamsWebhookURL = ""
    @State private var statusMessage = ""

    private var checkFrequency: Binding<CheckFrequency> {
        Binding(
            get: { CheckFrequency(rawValue: checkFrequencyRaw) ?? .onLaunch },
            set: { checkFrequencyRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("General")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Automatic Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How often Version Report should check for new app versions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Check for updates", selection: checkFrequency) {
                        ForEach(CheckFrequency.allCases, id: \.self) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .padding(.top, 6)
            }

            Divider()

            Text("Notifications")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Microsoft Teams") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send a message to a Microsoft Teams channel when Version Report detects a new app version.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Webhook URL", text: $teamsWebhookURL)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save") {
                            saveWebhookURL()
                        }

                        Button("Test Notification") {
                            sendTestNotification()
                        }

                        Button("Clear") {
                            clearWebhookURL()
                        }

                        Spacer()
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            teamsWebhookURL = KeychainHelper.shared.loadTeamsWebhookURL() ?? ""
        }
    }

    private func saveWebhookURL() {
        let trimmedURL = teamsWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty else {
            KeychainHelper.shared.deleteTeamsWebhookURL()
            teamsWebhookURL = ""
            statusMessage = "Teams webhook URL cleared."
            return
        }

        if KeychainHelper.shared.saveTeamsWebhookURL(trimmedURL) {
            teamsWebhookURL = trimmedURL
            statusMessage = "Teams webhook URL saved."
        } else {
            statusMessage = "Unable to save Teams webhook URL."
        }
    }

    private func clearWebhookURL() {
        KeychainHelper.shared.deleteTeamsWebhookURL()
        teamsWebhookURL = ""
        statusMessage = "Teams webhook URL cleared."
    }

    private func sendTestNotification() {
        let webhookURLString = teamsWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !webhookURLString.isEmpty,
              let webhookURL = URL(string: webhookURLString) else {
            statusMessage = "Enter a valid Teams webhook URL before testing."
            return
        }

        let adaptiveCard: [String: Any] = [
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "type": "AdaptiveCard",
            "version": "1.4",
            "body": [
                [
                    "type": "TextBlock",
                    "text": "Version Report",
                    "weight": "Bolder",
                    "size": "Medium"
                ],
                [
                    "type": "TextBlock",
                    "text": "Test notification. Your Microsoft Teams integration is working.",
                    "wrap": true
                ]
            ]
        ]

        let payload: [String: Any] = [
            "type": "message",
            "attachments": [
                [
                    "contentType": "application/vnd.microsoft.card.adaptive",
                    "contentUrl": NSNull(),
                    "content": adaptiveCard
                ]
            ]
        ]

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            statusMessage = "Unable to create Teams test message."
            return
        }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payloadData

        statusMessage = "Sending Teams test notification..."

        Task {
            do {
                let (responseData, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        statusMessage = "Teams test notification failed: no HTTP response."
                    }
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    let responseText = String(data: responseData, encoding: .utf8) ?? "No response body."
                    await MainActor.run {
                        statusMessage = "Teams test notification failed: HTTP \(httpResponse.statusCode). \(responseText)"
                    }
                    return
                }

                await MainActor.run {
                    statusMessage = "Teams test notification accepted by webhook."
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Teams test notification failed."
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
