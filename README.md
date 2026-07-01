# arrow_ops

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Datenmigration Italienische Stadt-Suffixe

Fuer bestehende Daten kann das Skript
`scripts/sql/normalize_italian_city_suffixes.sql`
italienische Stadtfelder auf das Format `Stadtname (XX)` normieren,
wobei `XX` aus `c_state_b` oder `c_state_d` (Format `XX-...`) stammt.

Ausfuehrung:

```bash
sqlite3 /Pfad/zur/arrow_ops.db < scripts/sql/normalize_italian_city_suffixes.sql
```

## Datenmigration USA Verwaltungseinheit und Stadt-Suffixe

Fuer bestehende US-Daten kann das Skript
`scripts/sql/normalize_us_state_city_suffixes.sql`
die Verwaltungseinheit auf `ST-StateName` und die Stadt auf `City, ST`
normalisieren.

Ausfuehrung:

```bash
sqlite3 /Pfad/zur/arrow_ops.db < scripts/sql/normalize_us_state_city_suffixes.sql
```

## Migrations-Check USD zu EUR Kursfeld

Nach dem Update auf die Datenbankmigration mit `o_fx_to_eur` kann das Skript
`scripts/sql/check_usd_fx_to_eur.sql`
fuer einen schnellen Release-Check verwendet werden.

Es prueft:

1. Ob die Spalte `o_fx_to_eur` existiert.
2. Wie viele USD-Auftraege insgesamt vorliegen.
3. Wie viele USD-Auftraege bereits einen gueltigen Kurs > 0 haben.
4. Welche USD-Auftraege noch ohne gueltigen Kurs sind.

Ausfuehrung:

```bash
sqlite3 -header -column /Pfad/zur/arrow_ops.db < scripts/sql/check_usd_fx_to_eur.sql
```

## Artikelbilder und iCloud

Der Katalog speichert in `ic_image_path` einen relativen Pfad (z. B. `item_images/item_123_...jpg`).
Beim Speichern wird ein ausgewaehltes lokales Bild in den App-Speicher kopiert, damit der Pfad auf allen Geraeten stabil bleibt.

Fuer iOS, iPadOS und macOS ist ein nativer Method-Channel `arrow_ops/icloud` hinterlegt.
Der Channel liefert den Pfad zum iCloud-Container (`Documents`) und wird verwendet, um verwaltete Bilddateien dort abzulegen.

Voraussetzungen fuer echten iCloud-Abgleich:

1. In Xcode bei iOS und macOS die Capability `iCloud` aktivieren.
2. `iCloud Documents` aktivieren.
3. Einen `iCloud Container` anlegen und beiden Targets zuweisen.
4. Sicherstellen, dass Bundle Identifier, Team und Container zusammenpassen.

Container-ID zentral konfigurieren (Flutter):

```bash
flutter run --dart-define=ICLOUD_CONTAINER_ID=iCloud.com.example.arrowops
```

Die Konfiguration wird in `lib/core/sync/icloud_sync_config.dart` gelesen.

Hinweis:
Nur die Dateisynchronisierung fuer Bilder ist damit vorbereitet.
Ein vollstaendiger Datensatzabgleich (z. B. fuer `item_catalogue`) braucht zusaetzlich eine Record-Synchronisierung, etwa ueber CloudKit.
