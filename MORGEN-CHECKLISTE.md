# Guten Morgen — so bringst du StrikeShot aufs iPhone

Alles ist gebaut und liegt auf GitHub. Was du selbst machen musst, ist alles,
wofür man deinen Apple-Account braucht.

## 1. Projekt öffnen (2 Minuten)

Die `.xcodeproj` liegt bewusst nicht im Repo — sie wird generiert:

```sh
cd ~/Claude/Projects/LightningMCCapture
xcodegen generate
open StrikeShot.xcodeproj
```

Nach jedem `git pull`, der neue Swift-Dateien bringt, `xcodegen generate` erneut
laufen lassen.

## 2. Signing setzen (5 Minuten)

In Xcode für **beide** Targets (`StrikeShot` und `StrikeShotWidgets`):

- *Signing & Capabilities* → **Team** auswählen
- Die Bundle-IDs sind `dev.leonfrohlich.strikeshot` und `…strikeshot.widgets`.
  Falls die schon vergeben sind, in `project.yml` das Präfix ändern und neu generieren.

## 3. Aufs Gerät bauen

Die Kamera-Auslösung braucht ein echtes iPhone — der Simulator hat keine Kamera.
Die App merkt das und bietet dort den **Sturm-Simulator** an, damit du die
Auslöselogik trotzdem sehen kannst.

Beim ersten Start fragt sie nach Kamera, Mikrofon, Standort, Fotos und
Mitteilungen. Alle erlauben, sonst fehlen Funktionen.

## 4. Erster Praxistest ohne Gewitter

- *Einstellungen → Sturm-Simulator* einschalten: die Karte bekommt eine
  wandernde Gewitterzelle, Warnungen und Live-Anzeige lassen sich damit prüfen.
- Kamera-Tab, Modus **Foto**, scharfstellen, dann im Dunkeln kurz das Licht
  anschalten — die App sollte auslösen. Empfindlichkeit über den Slider justieren.

**Kalibrierung:** Der Auslöse-Schwellwert ist bewusst als Regler herausgeführt.
Erwarte, dass du ihn beim ersten echten Gewitter nachziehen musst — bei Vollmond
und Straßenlaternen liegt er anders als auf dem dunklen Feld.

## 5. Optional: App-Gruppe für das Widget

Das Home-Screen-Widget zeigt ohne App-Gruppe nur einen Platzhalter (die Live
Activity auf dem Sperrbildschirm funktioniert trotzdem). Wenn du es willst:

- Bei beiden Targets *+ Capability → App Groups* → `group.dev.leonfrohlich.strikeshot`

## 6. Optional: Push-Server

Nur nötig für Warnungen bei **komplett geschlossener** App. Anleitung in
`Server/README.md` — du brauchst dafür einen APNs-Key aus dem Apple Developer
Portal und eine Redis-Instanz bei Vercel.

Ohne Server warnt die App weiterhin, solange sie läuft oder im Hintergrund
aktualisiert wird.

## 7. Sprachen und Icon — schon erledigt

Deutsch und Englisch sind vollständig übersetzt: 174 Texte in
`StrikeShot/Resources/Localizable.xcstrings`, dazu die Berechtigungsdialoge in
`InfoPlist.xcstrings`. Auf Englisch nachsehen:

```sh
xcrun simctl launch booted dev.leonfrohlich.strikeshot -AppleLanguages '(en)'
```

Das App-Icon (Blitz mit Radar-Ringen) liegt in
`StrikeShot/Resources/Assets.xcassets`. Zum Ändern reicht es, eine neue
`icon-1024.png` an dieselbe Stelle zu legen.

## Was bewusst einfach gehalten ist

Im Code mit `// ponytail:` markiert, jeweils mit dem Upgrade-Pfad daneben. Die
wichtigsten:

- Zellen-Tracking rechnet mit geradliniger Verlagerung, kein Kalman-Filter.
- Die Donner-Entfernung erkennt den lauten Peak, kein trainierter Klassifikator —
  eine zuschlagende Autotür kann sie täuschen.
- Der Push-Server tastet den Feed alle 10 Minuten für 20 Sekunden ab.

## Wichtig

StrikeShot ist **kein Warndienst**. Bei Gewitter zählt die 30/30-Regel: weniger
als 30 Sekunden zwischen Blitz und Donner heißt rein ins Gebäude oder Auto, und
30 Minuten nach dem letzten Donner drin bleiben. Die App warnt dich, sie schützt
dich nicht.
