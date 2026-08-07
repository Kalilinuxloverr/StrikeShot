import SwiftUI
import UIKit

struct SettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(\.stormTheme) private var theme
    @State private var pushEndpoint = UserDefaults.standard.string(forKey: "pushEndpoint") ?? ""

    var body: some View {
        @Bindable var settings = services.settings

        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text("\(Int(settings.radiusKilometers)) km")
                            .foregroundStyle(theme.accent)
                            .monospacedDigit()
                    } label: {
                        Text(String(localized: "settings.radius", defaultValue: "Radius"))
                    }
                    Slider(value: $settings.radiusKilometers, in: 10...250, step: 5)
                        .tint(theme.accent)
                } header: {
                    Text(String(localized: "settings.section.radius", defaultValue: "Beobachteter Bereich"))
                } footer: {
                    Text(String(
                        localized: "settings.radius.footer",
                        defaultValue: "Bestimmt, welche Blitze auf der Karte gezählt werden und ab wann gewarnt wird."
                    ))
                }

                Section {
                    LabeledContent {
                        Text(sensitivityLabel).foregroundStyle(theme.accent)
                    } label: {
                        Text(String(localized: "settings.sensitivity", defaultValue: "Auslöse-Empfindlichkeit"))
                    }
                    Slider(value: $settings.triggerSensitivity, in: 0...1)
                        .tint(theme.accent)
                    Toggle(isOn: $settings.thunderRangingEnabled) {
                        Text(String(localized: "settings.thunder", defaultValue: "Donner-Entfernung messen"))
                    }
                    Toggle(isOn: $settings.saveToPhotoLibrary) {
                        Text(String(localized: "settings.photoLibrary", defaultValue: "In Fotomediathek sichern"))
                    }
                } header: {
                    Text(String(localized: "settings.section.capture", defaultValue: "Aufnahme"))
                } footer: {
                    Text(String(
                        localized: "settings.sensitivity.footer",
                        defaultValue: "Höhere Empfindlichkeit fängt schwache Blitze, löst aber auch bei Scheinwerfern und Reflexionen aus."
                    ))
                }

                Section {
                    Toggle(isOn: $settings.safetyAlertsEnabled) {
                        Text(String(localized: "settings.safetyAlerts", defaultValue: "Sicherheitswarnungen"))
                    }
                    Toggle(isOn: $settings.approachAlertsEnabled) {
                        Text(String(localized: "settings.approachAlerts", defaultValue: "Warnung bei Annäherung"))
                    }
                    Toggle(isOn: $settings.liveActivityEnabled) {
                        Text(String(localized: "settings.liveActivity", defaultValue: "Live-Anzeige auf dem Sperrbildschirm"))
                    }
                    if services.alerts.authorizationDenied {
                        Button {
                            openNotificationSettings()
                        } label: {
                            Label {
                                Text(String(
                                    localized: "settings.notificationsDenied",
                                    defaultValue: "Mitteilungen sind deaktiviert — in den Systemeinstellungen erlauben"
                                ))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                        }
                        .foregroundStyle(theme.danger)
                    }
                } header: {
                    Text(String(localized: "settings.section.alerts", defaultValue: "Warnungen"))
                }

                Section {
                    Toggle(isOn: $settings.useSimulatedFeed) {
                        Text(String(localized: "settings.simulatedFeed", defaultValue: "Sturm-Simulator"))
                    }
                    .onChange(of: settings.useSimulatedFeed) { _, isOn in
                        services.feed.setSimulated(isOn)
                    }
                    TextField(
                        String(localized: "settings.pushEndpoint", defaultValue: "Push-Server-URL"),
                        text: $pushEndpoint
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(savePushEndpoint)
                } header: {
                    Text(String(localized: "settings.section.advanced", defaultValue: "Erweitert"))
                } footer: {
                    Text(String(
                        localized: "settings.pushEndpoint.footer",
                        defaultValue: "Optional. Ohne eigenen Server warnt StrikeShot nur, solange die App läuft oder im Hintergrund aktualisiert wird."
                    ))
                }

                Section {
                    LabeledContent {
                        Text(appVersion).foregroundStyle(theme.secondaryText)
                    } label: {
                        Text(String(localized: "settings.version", defaultValue: "Version"))
                    }
                    if let url = URL(string: "https://www.blitzortung.org") {
                        Link(destination: url) {
                            Text(String(
                                localized: "settings.dataSource",
                                defaultValue: "Blitzdaten: Blitzortung.org (nicht-kommerziell)"
                            ))
                        }
                    }
                } header: {
                    Text(String(localized: "settings.section.about", defaultValue: "Über"))
                } footer: {
                    Text(String(
                        localized: "settings.safety.footer",
                        defaultValue: "StrikeShot ist kein Warndienst. Verlass dich bei Gewitter nie allein auf die App — such rechtzeitig ein Gebäude oder Auto auf."
                    ))
                    .foregroundStyle(theme.danger)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(String(localized: "tab.settings", defaultValue: "Einstellungen"))
        }
    }

    private var sensitivityLabel: String {
        switch services.settings.triggerSensitivity {
        case ..<0.25: String(localized: "sensitivity.low", defaultValue: "Niedrig")
        case ..<0.6: String(localized: "sensitivity.medium", defaultValue: "Mittel")
        case ..<0.85: String(localized: "sensitivity.high", defaultValue: "Hoch")
        default: String(localized: "sensitivity.max", defaultValue: "Maximal")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func savePushEndpoint() {
        let trimmed = pushEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "pushEndpoint")
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
