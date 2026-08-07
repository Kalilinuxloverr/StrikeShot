import CoreGraphics
import MapKit
import SwiftUI
import UIKit

/// One session in full: map, key numbers, capture grid, composite export.
struct SessionDetailScreen: View {
    @Environment(\.stormTheme) private var theme
    let session: StormSession

    @State private var composite: UIImage?
    @State private var isStacking = false
    @State private var compositeError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mapCard
                metricsCard
                capturesSection
                compositeSection
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Map

    @ViewBuilder private var mapCard: some View {
        if let point = session.point {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: point.coordinate,
                latitudinalMeters: 20_000,
                longitudinalMeters: 20_000
            ))) {
                Marker(session.displayName, systemImage: "bolt.fill", coordinate: point.coordinate)
                    .tint(theme.accent)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Metrics

    private var metricsCard: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            metricRow(
                String(localized: "detail.metric.start", defaultValue: "Start"),
                session.start.formatted(date: .abbreviated, time: .shortened)
            )
            metricRow(
                String(localized: "detail.metric.duration", defaultValue: "Dauer"),
                session.duration.formattedSessionDuration
            )
            metricRow(
                String(localized: "detail.metric.strikes", defaultValue: "Blitze"),
                "\(session.maxStrikeCount)"
            )
            metricRow(
                String(localized: "detail.metric.nearest", defaultValue: "Nächster Einschlag"),
                session.nearestStrikeMeters?.formattedDistance ?? "–"
            )
            metricRow(
                String(localized: "detail.metric.intensity", defaultValue: "Spitzen-Intensität"),
                session.peakIntensity.localizedName
            )
            metricRow(
                String(localized: "detail.metric.captures", defaultValue: "Aufnahmen"),
                "\(session.captures.count)"
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Captures

    @ViewBuilder private var capturesSection: some View {
        let captures = session.sortedCaptures
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "detail.captures.title", defaultValue: "Aufnahmen"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            if captures.isEmpty {
                Text(String(localized: "detail.captures.empty", defaultValue: "Keine Aufnahmen in dieser Session."))
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
            } else {
                let bestID = session.bestCapture?.id
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(captures) { record in
                        CaptureTile(record: record, isBest: record.id == bestID)
                    }
                }
            }
        }
    }

    // MARK: - Composite

    @ViewBuilder private var compositeSection: some View {
        if !session.captures.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: createComposite) {
                    Label(
                        String(localized: "detail.composite.create", defaultValue: "Composite erstellen"),
                        systemImage: "square.3.layers.3d.down.right"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .background(theme.accent.opacity(isStacking ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(theme.background)
                .disabled(isStacking)

                if isStacking {
                    ProgressView(String(localized: "detail.composite.working", defaultValue: "Bilder werden gestapelt …"))
                        .tint(theme.accent)
                        .foregroundStyle(theme.secondaryText)
                }
                if let compositeError {
                    Text(compositeError)
                        .font(.footnote)
                        .foregroundStyle(theme.danger)
                }
                if let composite {
                    Image(uiImage: composite)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    ShareLink(
                        item: Image(uiImage: composite),
                        preview: SharePreview(
                            String(localized: "detail.composite.shareTitle", defaultValue: "StrikeShot Composite"),
                            image: Image(uiImage: composite)
                        )
                    ) {
                        Label(
                            String(localized: "detail.composite.share", defaultValue: "Composite teilen"),
                            systemImage: "square.and.arrow.up"
                        )
                        .foregroundStyle(theme.accent)
                    }
                }
            }
        }
    }

    private func createComposite() {
        // Full-res files where readable (photos); video captures fall back to their thumbnail.
        let sources = session.sortedCaptures.map { (url: $0.fileURL, data: $0.thumbnail) }
        isStacking = true
        compositeError = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                let images = sources.compactMap { source -> CGImage? in
                    if let url = source.url, url.isFileURL,
                       let image = BestShotRanker.loadImage(at: url, maxDimension: 2_048) {
                        return image
                    }
                    return source.data.flatMap { BestShotRanker.loadImage(data: $0, maxDimension: 2_048) }
                }
                return CompositeStacker.stack(images: images)
            }.value
            isStacking = false
            if let result {
                composite = UIImage(cgImage: result)
            } else {
                compositeError = String(
                    localized: "detail.composite.failed",
                    defaultValue: "Composite fehlgeschlagen – keine lesbaren Bilder in dieser Session."
                )
            }
        }
    }
}

private struct CaptureTile: View {
    @Environment(\.stormTheme) private var theme
    let record: CaptureRecord
    let isBest: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnail
            if let symbol = record.mode.badgeSymbol {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(theme.primaryText)
                    .padding(4)
                    .background(theme.surface.opacity(0.8), in: Circle())
                    .padding(4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isBest {
                Label(
                    String(localized: "detail.bestShot", defaultValue: "Bester Shot"),
                    systemImage: "star.fill"
                )
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(theme.accent, in: Capsule())
                .foregroundStyle(theme.background)
                .padding(4)
            }
        }
        .overlay {
            if isBest {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.accentGlow, lineWidth: 2)
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let data = record.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    theme.surfaceRaised
                    Image(systemName: "bolt.slash")
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension CaptureMode {
    var badgeSymbol: String? {
        switch self {
        case .photo: nil
        case .video: "video.fill"
        case .slowMotion: "slowmo"
        }
    }
}
