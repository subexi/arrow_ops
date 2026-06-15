# PDF Check: EN + Net + Non-EU

This checklist verifies the special PDF behavior for `Invoice` and `Packing List` when:

- Language is `EN`
- Price basis is `net`
- Delivery country is outside the EU

## Expected Behavior

1. Line item `Description` is shown in English.
2. Totals row `VAT (...)` is hidden.
3. Totals row `Goods gross` is hidden.
4. `GiroCode` block is hidden.

## Suggested Test Data

Use an order with:

- `language = EN`
- `price_basis = net`
- Non-EU delivery country, for example `AU`, `USA`, `GB`, `CH`
- At least one order line where EN and DE descriptions differ clearly.

Example line descriptions:

- DE: `Selbstsichernde Mutter M6`
- EN: `Self-locking nut M6`

## Validation Steps

1. Open page `Rechnungen / Lieferscheine`.
1. Select the target order.
1. Generate preview as `Rechnung`.
1. Verify in line table: `Description` matches EN text (`Self-locking nut M6` in this example).
1. Verify in totals: no `VAT (...)` row and no `Goods gross` row.
1. Verify in meta/QR area: no `GiroCode` block.
1. Repeat the same check for `Lieferschein`.

## Negative Check (Control)

To confirm the rule is condition-based, test one counter-example:

- Same order but with `language = DE` OR
- Same order but with EU delivery country

Expected for control case:

- Standard behavior returns (normal rows/blocks according to existing rules).

## Concrete AU Example (Reference)

Use this concrete setup for a fast visual check:

- Document language: `EN`
- Price basis: `net`
- Delivery country: `AU` (Australia)
- Example line DE text: `Selbstsichernde Mutter M6`
- Example line EN text: `Self-locking nut M6`

Expected in PDF (`Invoice` and `Packing List` preview context):

1. In line table, `Description` shows `Self-locking nut M6`.
2. In totals block, row `VAT (...)` is not present.
3. In totals block, row `Goods gross` is not present.
4. In meta/QR block, `GiroCode` is not present.

Quick pass/fail heuristic:

- PASS: EN description visible + VAT/Goods gross/GiroCode all absent.
- FAIL: At least one of these rows/blocks is still visible or DE text appears as description.
