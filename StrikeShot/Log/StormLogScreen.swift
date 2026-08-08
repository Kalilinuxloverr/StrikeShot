import SwiftData
import SwiftUI
import UIKit

/// Diary tab: every storm session ever recorded.
struct StormLogScreen: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        // No container means SwiftData is unusable on this device. `@Query` traps
        // on a missing container, so the list must not be built in that case.
        if let container = services.log.container {
            SessionListView(storageError: services.log.lastError)
                .modelContainer(container)
        } else {
            StorageUnavailableView(message: services.log.lastError)
        }
    }
}

/// Shown when SwiftData cannot provide storage at all.
struct StorageUnavailableView: View {
    @Environment(\.stormTheme) private var theme
    let message: String?

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label {
                    Text(String(localized: "log.unavailable.title", defaultValue: "Tagebuch nicht verfügbar"))
                } icon: {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(theme.danger)
                }
            } description: {
                Text(message ?? String(
                    localized: "log.unavailable.body",
                    defaultValue: "Der Speicher lässt sich auf diesem Gerät nicht öffnen. Aufnehmen, Karte und Warnungen funktionieren weiterhin."
                ))
            }
            .background(theme.background)
            .navigationTitle(String(localized: "tab.log", defaultValue: "Tagebuch"))
        }
    }
}

private struct SessionListView: View {
    @Environment(\.stormTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StormSession.start, order: .reverse) private var sessions: [StormSession]
    @State private var deleteError: String?

    let storageError: String?

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(String(localized: "log.title", defaultValue: "Sturm-Tagebuch"))
            .navigationDestination(for: StormSession.self) { session in
                SessionDetailScreen(session: session)
            }
        }
        .alert(
            String(localized: "log.delete.errorTitle", defaultValue: "Löschen fehlgeschlagen"),
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button(String(localized: "common.ok", defaultValue: "OK"), role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var sessionList: some View {
        List {
            if let storageError {
                Text(storageError)
                    .font(.footnote)
                    .foregroundStyle(theme.danger)
                    .listRowBackground(theme.surface)
            }
            ForEach(sessions) { session in
                NavigationLink(value: session) {
                    SessionRow(session: session)
                }
                .listRowBackground(theme.surface)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "log.empty.title", defaultValue: "Noch keine Stürme"),
                systemImage: "cloud.bolt"
            )
            .foregroundStyle(theme.primaryText)
        } description: {
            Text(String(
                localized: "log.empty.detail",
                defaultValue: "Starte eine Aufnahme-Session, sobald ein Gewitter aufzieht. Jede Session landet hier – mit Blitzen, Fotos und Kennzahlen."
            ))
            .foregroundStyle(theme.secondaryText)
        }
    }

    private func delete(at offsets: IndexSet) {
        // ponytail: only the records are removed; media files stay on disk.
        // Add file cleanup when storage use becomes a concern.
        for index in offsets where sessions.indices.contains(index) {
            modelContext.delete(sessions[index])
        }
        do {
            try modelContext.save()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct SessionRow: View {
    @Environment(\.stormTheme) private var theme
    let session: StormSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text(session.peakIntensity.localizedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
            }
            Text(session.displayName)
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            HStack(spacing: 12) {
                Label("\(session.maxStrikeCount)", systemImage: "bolt.fill")
                Label(session.duration.formattedSessionDuration, systemImage: "clock")
                if let nearest = session.nearestStrikeMeters {
                    Label(nearest.formattedDistance, systemImage: "scope")
                }
            }
            .font(.caption)
            .foregroundStyle(theme.secondaryText)
            thumbnailRow
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var thumbnailRow: some View {
        let thumbs = session.sortedCaptures.prefix(5)
        if !thumbs.isEmpty {
            HStack(spacing: 6) {
                ForEach(thumbs) { record in
                    if let data = record.thumbnail, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}
