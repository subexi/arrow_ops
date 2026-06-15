# PDF Address Check: Australia + EN

This checklist helps verify the expected PDF address formatting for `Invoice` and `Packing List` when:

- `Country = Australia`
- `Language = EN`

## Expected Rules

1. House number is printed before street in buyer and delivery addresses.
2. City line order is: `City` `State abbreviation` `Postcode`.
3. Country is printed as full text: `Australia` (not `AU`).

## Test Input Example

Use customer/delivery data similar to:

- Name: `John Doe`
- Company: `Arrow Test Pty`
- Street: `George Street`
- House number: `42`
- City: `Sydney`
- State: `New South Wales`
- Postcode: `2000`
- Country: `AU`

## Expected Output Lines in PDF

For buyer/delivery blocks, the relevant address lines should appear as:

- `42 George Street`
- `Sydney NSW 2000`
- `Australia`

## Second Test Case (Melbourne)

Use an additional customer/delivery data set:

- Name: `Jane Smith`
- Company: `Arrow Melbourne Pty`
- Street: `Collins Street`
- House number: `101`
- City: `Melbourne`
- State: `Victoria`
- Postcode: `3000`
- Country: `AUS`

Expected output lines in PDF:

- `101 Collins Street`
- `Melbourne VIC 3000`
- `Australia`

## Third Test Case (Queensland)

Use an additional customer/delivery data set:

- Name: `Alex Brown`
- Company: `Arrow Brisbane Pty`
- Street: `Queen Street`
- House number: `88`
- City: `Brisbane`
- State: `Queensland`
- Postcode: `4000`
- Country: `AU`

Expected output lines in PDF:

- `88 Queen Street`
- `Brisbane QLD 4000`
- `Australia`

## State Abbreviation Mapping

The formatter normalizes common Australian state names to these abbreviations:

- `New South Wales` -> `NSW`
- `Victoria` -> `VIC`
- `Queensland` -> `QLD`
- `South Australia` -> `SA`
- `Western Australia` -> `WA`
- `Tasmania` -> `TAS`
- `Northern Territory` -> `NT`
- `Australian Capital Territory` -> `ACT`

## Quick Validation Steps

1. Open `Rechnungen / Lieferscheine` page.
2. Select an order with Australian address data.
3. Set document language to `EN`.
4. Build preview for both `Rechnung` and `Lieferschein`.
5. Confirm the three output line rules above in buyer and delivery sections.
