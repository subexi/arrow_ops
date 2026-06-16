# PayPal Gebuehrenregeln (DE Empfaenger, EUR, Business)

## Grundlage

Die automatische PayPal-Gebuehr wird auf folgender Basis berechnet:

- Basisbetrag = Warenwert brutto + Versandkosten
- Gebuehr = Basisbetrag * Prozentwert + Fixbetrag
- Fixbetrag = 0,36 EUR

## Sender-Marktgruppen

| Marktgruppe | Regel fuer Senderland | Prozentwert |
| --- | --- | --- |
| EWR | EU + Norwegen + Island + Liechtenstein | 2,49 % |
| UK | Vereinigtes Koenigreich | 3,774 % |
| USA/Kanada | USA oder Kanada | 4,453 % |
| Rest der Welt | Alle anderen Senderlaender | 5,49 % |

## Hinweise fuer die Auftragsmaske

- Auto-Berechnung nur bei Zahlart = PayPal.
- Auto-Berechnung nur bei Waehrung = EUR.
- Manuell eingegebene PayPal-Gebuehr bleibt erhalten.
- Neu berechnet wird nur, wenn die PayPal-Gebuehr = 0 ist.
