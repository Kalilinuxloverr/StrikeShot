# StrikeShot Push-Server

Warnt registrierte Geräte, wenn ein Gewitter in ihren Radius zieht — auch bei
geschlossener App. Ohne diesen Server warnt StrikeShot nur, solange die App läuft
oder das System sie im Hintergrund aktualisiert.

Zwei Endpunkte, kein Account-System:

| Route | Zweck |
|---|---|
| `POST /api/register` | App meldet APNs-Token, Position und Radius an |
| `DELETE /api/register?deviceToken=…` | Abmelden |
| `GET /api/cron` | Läuft alle 10 Minuten, tastet den Blitz-Feed ab und pusht |

## Einrichten

```sh
cd Server
npm install
vercel link          # Projekt anlegen/verknüpfen
```

### 1. APNs-Key bei Apple holen

Im Apple Developer Portal unter *Certificates, Identifiers & Profiles → Keys*
einen Key mit **Apple Push Notifications service (APNs)** anlegen und die `.p8`
herunterladen. Sie lässt sich nur einmal laden — sicher ablegen, **nicht** ins Repo.

### 2. Umgebungsvariablen setzen

```sh
vercel env add APNS_KEY_ID          # die 10-stellige Key-ID
vercel env add APNS_TEAM_ID         # die 10-stellige Team-ID
vercel env add APNS_TOPIC           # dev.leonfrohlich.strikeshot
vercel env add APNS_PRIVATE_KEY     # kompletter Inhalt der .p8, Zeilenumbrüche als \n
vercel env add CRON_SECRET          # beliebige lange Zufallszeichenkette
```

Für TestFlight- und Debug-Builds zusätzlich `APNS_HOST=https://api.sandbox.push.apple.com`.

### 3. Speicher bereitstellen

Der Server merkt sich Geräte in Redis über die REST-Schnittstelle. Im Vercel-
Dashboard unter *Storage* eine Redis-Instanz aus dem Marketplace hinzufügen — sie
setzt `KV_REST_API_URL` und `KV_REST_API_TOKEN` automatisch.

Ohne Redis läuft alles, hält Registrierungen aber nur im Arbeitsspeicher: für ein
einzelnes Testgerät in Ordnung, für echten Betrieb nicht.

### 4. Deployen

```sh
vercel deploy --prod
```

Die Deployment-URL danach in der App unter *Einstellungen → Erweitert →
Push-Server-URL* eintragen (nur die Basis-URL, ohne `/api/register`).

## Testen

```sh
npm test                       # Decoder- und Distanzlogik, ohne Netz
curl -X POST "$URL/api/register" -H 'content-type: application/json' \
  -d '{"deviceToken":"<64+ hex>","latitude":48.2,"longitude":16.37,"radiusKm":50}'
curl -H "authorization: Bearer $CRON_SECRET" "$URL/api/cron"
```

## Grenzen

- Der Cron-Lauf tastet den Feed 20 Sekunden lang ab, statt dauerhaft zu lauschen.
  Ein Blitz zwischen zwei Läufen wird nicht bemerkt. Für Sekunden-Genauigkeit
  bräuchte es einen dauerhaft verbundenen Worker statt einer Cron-Funktion.
- Die Zuordnung läuft über den zuletzt gemeldeten Standort, nicht über den aktuellen.
- Blitzortung.org-Daten sind ausschließlich für nicht-kommerzielle Nutzung frei.
