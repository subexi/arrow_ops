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
