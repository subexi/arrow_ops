# PDF Address Preview Check - Switzerland (CH)

## Ziel

Validieren, dass fuer Swiss-Adressen in Rechnung und Lieferschein:

- die Verwaltungseinheit als Kanton im Kundenstamm gespeichert wird (z. B. `ZH-Zurich`)
- die Ortszeile im PDF das Kantonskuerzel hinter dem Ort zeigt (z. B. `8000 Zurich ZH`)

## Voraussetzungen

- Kundenseite wurde mindestens einmal geoeffnet, damit das Nachziehen bestehender CH-Eintraege ausgefuehrt wird.
- PDF-Vorschau fuer Rechnung und Lieferschein ist verfuegbar.

## Beispiel-Testdaten

### Fall 1: Zurich

- Land: `Switzerland`
- PLZ: `8000`
- Ort: `Zurich`
- Erwartete Verwaltungseinheit im Kundenstamm: `ZH-Zurich`
- Erwartete Ortszeile im PDF: `8000 Zurich ZH`

### Fall 2: Geneva

- Land: `Switzerland`
- PLZ: `1201`
- Ort: `Geneva`
- Erwartete Verwaltungseinheit im Kundenstamm: `GE-Geneve`
- Erwartete Ortszeile im PDF: `1201 Geneva GE`

### Fall 3: Basel

- Land: `Switzerland`
- PLZ: `4051`
- Ort: `Basel`
- Erwartete Verwaltungseinheit im Kundenstamm: `BS-Basel-Stadt`
- Erwartete Ortszeile im PDF: `4051 Basel BS`

## Testablauf

1. Neuen Kunden mit CH-Rechnungsadresse anlegen oder bestehenden Kunden bearbeiten.
2. `Land` auf `Switzerland` setzen.
3. PLZ und Ort eintragen und speichern.
4. Kunden erneut oeffnen und Feld `Verwaltungseinheit` pruefen.
5. Auftrag fuer den Kunden anlegen.
6. Rechnungsvorschau oeffnen und Ortszeile in der Adresse pruefen.
7. Lieferscheinvorschau oeffnen und Ortszeile in der Adresse pruefen.

## Erwartetes Ergebnis

- Verwaltungseinheit ist als `CC-Kantonsname` gespeichert (`CC` = 2-stelliges Kantonskuerzel).
- Rechnung und Lieferschein zeigen in der Ortszeile `PLZ Ort CC`.
- Vorhandene CH-Kunden werden nach dem Laden der Kundenseite aktualisiert.
