# StrikeShot — Design-Spec

Datum: 2026-08-07 · Status: vom User freigegeben (interaktives Grilling, 3 Runden)

## Produkt

iOS-App (iPhone, iOS 17+, SwiftUI, Deutsch + Englisch, kostenlos), die Blitze
**automatisch** fotografiert/filmt und Gewitter live trackt. Alleinstellungsmerkmal:
Die Kamera puffert kontinuierlich (Ring-Buffer) und löst beim erkannten
Helligkeits-Spike selbst aus — inklusive der Frames *vor* dem Blitz.

Entscheidungen aus dem Grilling:

| Frage | Entscheidung |
|---|---|
| Fokus v1 | Kamera UND Karte voll ausgebaut |
| Features | Voll-Ausbau: alle 10 Zusatzfeatures |
| Datenquelle | Blitzortung.org (gratis, nicht-kommerziell), App bleibt kostenlos |
| Design | Storm-Chaser Dark mit Apple-Akzenten, Blitz-Boot-Animation, Live-Theme (Blitzaktivität + Tageszeit) |
| Alarme | Push-Server gewünscht → Server-Code wird mitgeliefert, App push-fähig; lokale Notifications als sofort funktionierender Fallback (APNs-Key kann nur der User anlegen) |
| Name | StrikeShot |

## Architektur

Ein App-Target + Widget-Extension (Live Activity/Widget) + Unit-Test-Target.
Projekt via XcodeGen (`project.yml`). Module als Ordner, keine Frameworks.

### CaptureEngine (Capture/)
- `CameraController`: AVCaptureSession; Modi Foto / Video / SloMo (240 fps wo Hardware kann).
- `FrameRingBuffer`: hält die letzten ~3 s CMSampleBuffers (Pre-Roll).
- `LumaSpikeDetector`: mittlere Luminanz pro Frame (downsampled), rollierende
  Baseline (EMA); Spike über Schwellwert → Trigger. Empfindlichkeit einstellbar.
- Trigger-Verhalten: Foto = hellster Frame aus dem Buffer als HEIC in die
  Fotomediathek; Video/SloMo = AVAssetWriter schreibt Pre-Roll + Nachlauf als Clip.
- `CameraAssistant`: Belichtungsprofile Tag/Nacht, Fokus unendlich, ISO/Shutter-Lock.
- `ThunderRanger`: nach Blitz-Trigger lauscht das Mikro auf den Donner-Peak;
  Distanz = Δt × 343 m/s.
- `StormSimulator`: synthetische Blitz-Frames für Tests ohne Gewitter/Kamera.

### LightningFeed (Feed/)
- `BlitzortungClient`: WebSocket zu den öffentlichen Blitzortung-Endpoints,
  inkl. deren LZW-artiger Dekompression. Endpoint-Liste konfigurierbar,
  automatischer Failover, Fallback auf Simulator-Feed.
- `StormCellTracker`: Grid-Clustering der Strikes zu Zellen, Bewegungsvektor
  aus Zeitfenstern → Zugrichtung + ETA auf User-Position.
- `MapScreen`: MapKit, Strikes altersgefärbt, einstellbarer Radius-Kreis,
  Zellen mit Richtungspfeil.

### StormLog (Log/)
- SwiftData: `StormSession` (Start/Ende, Ort, Strike-Zahl, nächster Einschlag),
  `CaptureItem` (Asset-Referenz, Zeit, Score, Distanz).
- Session-Replay auf der Karte, Statistik (Blitze gesehen, Stürme, Heatmap
  der Spots), Achievements (lokal, ohne Game Center).

### Nachbearbeitung (Post/)
- `BestShotRanker`: Score aus Helligkeits-Spitze + Kantenenergie (CoreImage).
- `CompositeStacker`: Lighten-Blend mehrerer Captures zu einem Multi-Blitz-Bild.

### Alarme (Alerts/)
- `AlertEngine`: Annäherungs-Alarm (Zelle nähert sich Radius, mit ETA),
  Safety-Warnung < 3 km („Geh rein", 30/30-Regel). Lokale Notifications.
- Live Activity: Blitze im Radius, Distanz nächster Einschlag, Trend.
- Push: Registrierung + Token-Upload an Server vorbereitet; Server-Code in
  `Server/` (Vercel-Function, pollt Blitzortung, sendet APNs an Regionen).

### Theme (Theme/)
- `ThemeEngine`: Basispalette Storm-Dark; Akzentintensität skaliert mit
  Blitzaktivität im Radius; Farbtemperatur folgt der Tageszeit.
- Boot-Animation: gezeichneter Blitz (Shape-Trim + Glow), kurz, abbrechbar.

## Fehlerbehandlung
- Kein Netz / Feed down → Banner + letzter bekannter Stand + Simulator-Option.
- Kamera-/Mikro-/Location-Permission verweigert → erklärende Empty-States.
- Fotomediathek-Fehler → Capture bleibt im App-Container, Retry.

## Tests
- Unit: Spike-Detektor (synthetische Luma-Reihen), Zellen-Tracker (synthetische
  Strike-Wolken), Blitzortung-Decoder (aufgezeichnete Payloads), Stacker/Ranker.
- Manuell (User, morgens): echtes Gerät, Sturm-Simulator, ggf. echtes Gewitter.

## Bewusste Grenzen (ponytail)
- Donner-Distanz: simple Pegel-Peak-Erkennung, kein ML-Audio-Klassifikator.
- Zellen-Tracking: Grid-Clustering, kein Kalman-Filter.
- Push-Server: minimaler Poll+Fanout, kein Account-System — Geräte registrieren
  Region+Radius, Server matcht grob.
- Achievements lokal, keine Community/Backend-Features.
