# Orders & Shopping List — Tutorial

This is the practical guide to the **purchase tracking workflow** in the MTG Card Scanner app. By the end you'll know how to:

1. Build up a shopping list by adding cards to decks
2. See what you still need across **all** your decks in one place
3. Place a bulk order from a seller (Hareruya, Card Kingdom, eBay, etc.)
4. Track packages from "ordered" → "arrived"
5. Edit or delete an order when something changes

---

## The mental model

Every card copy in a deck has one of three statuses:

```
   Needed   →   Ordered   →   Arrived
 (wishlist)    (in flight)   (in hand)
```

- **Needed** = on your wishlist, not yet purchased
- **Ordered** = purchase placed, package in transit
- **Arrived** = card is physically yours

The two screens you'll use most:

| Screen | Shows | Use it to |
|---|---|---|
| **Shopping List** | Items in `Needed` state across every deck | Plan a new order |
| **Orders** | Past purchases (ordered + arrived) | Track packages, edit orders |

They're complementary: cards flow **from** the Shopping List **into** Orders as you buy them.

```
       ┌───────────────┐         ┌──────────┐
       │ Shopping List │ ──────► │  Orders  │
       │   (Needed)    │  buy    │ (in hand)│
       └───────────────┘         └──────────┘
```

---

## Step 1 — Add cards to a deck

Cards only show up in the Shopping List if they're inside a deck and marked `Needed`. So the first step is always to build out a deck.

From **My Decks → New Deck**, give it a name and pick a format (or leave as Freeform). Then either:

- **Tap +** to search and add cards one at a time
- **Tap the import icon** to paste a decklist in the format `4 Lightning Bolt [M11]`

![Deck detail with empty state](images/01-empty-deck.png)

Once cards are imported, they all start in `Needed` state — visible as a cart icon on the deck header.

![Deck detail with cards needed](images/02-deck-with-needed.png)

---

## Step 2 — Open the Shopping List

From the **Scanner home screen**, tap **🛒 Shopping List**.

![Scanner home with Shopping List button](images/03-home-shopping-button.png)

This screen flattens **every needed card across every deck** into one list. Each row shows:

- **Quantity** — total copies needed across all decks
- **Card name** + mana cost
- **Set & collector number**
- **Per-card USD price** (from Scryfall) + line total
- **Deck attribution chips** — which decks need this card

```
┌─────────────────────────────────────────────────┐
│  Shopping List                                  │
├─────────────────────────────────────────────────┤
│  60 cards needed                  ≈ $487.20    │
│  Across 2 decks · USD prices from Scryfall      │
├─────────────────────────────────────────────────┤
│  60 cards                          [Sort: ▼]    │
├─────────────────────────────────────────────────┤
│  4×  Lightning Bolt  {R}              $2.00    │
│      Magic 2011 · #146       $0.50 ea           │
│      [Modern Burn ×4]                           │
├─────────────────────────────────────────────────┤
│  4×  Counterspell  {U}{U}             $8.00    │
│      Ice Age · #64           $2.00 ea           │
│      [Legacy U/W ×4]                            │
└─────────────────────────────────────────────────┘
```

**Sort menu** lets you switch between *Most needed*, *Name*, and *Price ↓* (line total descending — biggest spend first).

![Shopping list with cards](images/04-shopping-list.png)

---

## Step 3 — Place an order with a seller

Once you know what to buy, get a quote from a seller (Hareruya, Card Kingdom, etc.) and place the order. They'll send you a confirmation that looks like this:

```
Confirmed Mar-25 Card Kingdom order
Total due = 4770 <PAID as of Mar-25>
ETA March 31, 2026

Details:
    <White>
4    Savannah Lions [4ED] = 530ea
4    White Knight [4ED] = 40ea
1    Order of Leitbur <1> [FEM] = 30ea
4    Disenchant [4ED] = 30ea
...
```

Now record it in the app.

### Option A — From the Shopping List

Tap the **shippingbox button** in the top-right of the Shopping List. The bulk-order sheet opens with the paste editor **pre-populated** with every needed card in the parser's expected format:

```
4 Savannah Lions [4ED]
4 White Knight [4ED]
1 Order of Leitbur [FEM]
...
```

You then **add the prices** (`= 530ea`, `= 40ea`, etc.) and fill in the order metadata.

![Bulk order sheet seeded from shopping list](images/05-bulk-order-seeded.png)

### Option B — From inside a deck

Open a deck → tap the **shippingbox-back-arrow** in the toolbar. Same sheet, but matching is restricted to that deck's needed items.

![Deck toolbar with bulk order button](images/06-deck-toolbar.png)

### Filling in the sheet

1. **Store name** — autocomplete from history (TCGPlayer, Card Kingdom, Hareruya, etc.)
2. **Currency** — USD, PHP, JPY, EUR, GBP, CAD, AUD. *Not auto-converted.*
3. **Ordered date** — defaults to today
4. **Has ETA** + **ETA date** — optional, shown on the Orders screen
5. **Total due** — what the seller billed (may include shipping/tax)
6. **Order URL** — confirmation link (tap from Order Detail to reopen later)
7. **Notes** — free-form
8. **Paste seller confirmation** — drop the seller's text in here

![Bulk order sheet header fields](images/07-bulk-order-header.png)

### Parse → Preview

Tap **Parse**. The sheet shows a preview of every line, color-coded:

| Icon | Meaning |
|---|---|
| ✅ Green check | Exact match — N copies will be marked ordered |
| ⚠️ Orange triangle | Card found but in a different printing — applied to first N needed copies |
| ⚠️ Orange circle | Fewer needed copies than requested |
| ❓ Gray question | Card not in any deck — add it to a deck first |
| 📦 Gray box | All copies already ordered/arrived |
| ❌ Red X | Could not parse this line |

Each row has an "Apply this line" toggle so you can selectively skip lines.

![Bulk order preview with mixed statuses](images/08-bulk-order-preview.png)

### Apply

Tap **Apply**. The app:

- Creates an `Order` record with the store, date, ETA, currency, total
- Marks every matched item as `Ordered`
- Saves the per-card price + currency on each item
- Links every item to the new Order

The sheet closes and you're back where you started. The cards are no longer in the Shopping List (because they're no longer `Needed`).

---

## Step 4 — Track the order

From the Scanner home, tap **📦 Orders**.

![Orders screen with one order](images/09-orders-list.png)

Each row shows:

- **Store name**
- **Ordered date** + **arrived count** (e.g. `0/24 arrived`)
- **Total due** in the order's currency
- **ETA badge** (orange clock) or **"Arrived"** badge (green seal) if everything came in
- **Swipe left** for delete

Tap an order to drill into it.

### Order detail

```
┌─────────────────────────────────────────────────┐
│  ◀  Card Kingdom               ✏️                │
├─────────────────────────────────────────────────┤
│  ORDER INFO                                     │
│  Store           Card Kingdom                   │
│  Ordered         Mar 25, 2026                   │
│  ETA             Mar 31, 2026                   │
│  Currency        PHP                            │
│  Total Due       PHP 4770                       │
│  Order Link      ↗                              │
├─────────────────────────────────────────────────┤
│  ITEMS                          24 copies       │
│  4× Savannah Lions  [4ED]      0/4              │
│  4× White Knight    [4ED]      0/4              │
│  1× Order of Leitbur [FEM]     0/1              │
│  ...                                            │
├─────────────────────────────────────────────────┤
│  ✓  Mark All Arrived                            │
│  🗑  Delete Order (reset items to Needed)       │
└─────────────────────────────────────────────────┘
```

![Order detail](images/10-order-detail.png)

From here you can:

- **Tap the order URL** to reopen the seller's confirmation in your browser
- **Edit (pencil icon)** — change the store name, date, currency, total, ETA, notes. Changes cascade to every linked item.
- **Mark All Arrived** — when the package shows up, one tap flips every item to `Arrived` and stamps `arrivedAt`.
- **Delete Order** — removes the order *and* resets every linked item back to `Needed` in its deck. The cards themselves are not deleted. Useful when you need to re-do a paste.

---

## Step 5 — Mark items as arrived

When the package shows up:

1. Open **Orders → [the order]**
2. Tap **✓ Mark All Arrived**
3. Done

The order row in the list now shows the green "Arrived" badge, and the cards inside the deck show as `Arrived` (green check) instead of `Ordered` (orange box).

![Order marked as arrived](images/11-arrived.png)

---

## Common scenarios

### "I need to re-do an order — I made a mistake"

1. Open Orders → tap the broken order
2. Tap **🗑 Delete Order (reset items to Needed)**
3. Confirm — the items go back to `Needed` in their decks
4. Re-paste from the Shopping List

### "The seller billed me in PHP but the cards are JPY-priced"

In the bulk order sheet, set **Currency = PHP**, then enter prices in PHP (`= 530ea` means 530 PHP per card). The app stores the amount + currency together. Scryfall USD prices in the Shopping List are unrelated — they're just rough estimates.

### "Some lines have my own notes after the price"

The parser tolerates trailing text after the price:

```
4 Contagion [ALL] = 150ea, Card Kingdom — confirmed via email
2 Serrated Arrows [HML] = 40ea, eBay seller, used Buy It Now
```

Both of these parse correctly. Anything after the price is dropped silently.

### "I have multiple variants of the same card (Order of Leitbur 1, 2, 3, 4)"

Use the `<N>` syntax in the paste:

```
1 Order of Leitbur <1> [FEM] = 30ea
1 Order of Leitbur <2> [FEM] = 30ea
2 Order of Leitbur <3> [FEM] = 30ea
```

The matcher routes each line to the right deck variant by collector-number index (`<1>` → first sorted, `<2>` → second, etc.).

### "The Card Kingdom paste flagged a card as 'Card not in deck'"

This means the card name doesn't exist in any deck. Most likely cause: typo in the seller's confirmation or you forgot to add it to a deck. Add it to a deck (any deck — `Needed` state) and re-parse.

If you see **"All copies already ordered or arrived"** instead, that's a different issue: the card *is* in a deck, but every copy is already in `Ordered` or `Arrived` state, so there's nothing for this paste line to do. Usually means you applied this paste once already.

### "I want to see only the orders for one deck"

Open the deck → tap the **shippingbox icon** in the toolbar. The Orders screen opens filtered to just that deck's orders, with the title `Orders · [Deck Name]`.

![Deck-filtered orders](images/12-deck-filtered-orders.png)

---

## Tooltips

Look for the small **ⓘ** icons throughout the app — tap one to get a one-line explanation of any term that's confusing. They appear next to:

- Status labels in the deck header
- The legality banner
- Format picker
- Currency picker
- ETA / Total Due / Order URL fields
- Mana cost displays
- Set + collector number rows

---

## Reference: parser format

The bulk-order paste editor accepts lines in this shape:

```
<qty> <card name> [<SET>] <variant?> = <price>[ea] <trailing notes?>
```

| Element | Required? | Example |
|---|---|---|
| Quantity | Yes | `4` or `4x` |
| Card name | Yes | `Lightning Bolt` |
| Set code | Recommended | `[M11]`, `[4ED]`, `[FEM]` |
| Variant | Only for art variants | `<1>`, `<2>`, `<a>`, `<b>` |
| Price | Optional | `= 0.50` or `= 450ea` |
| Trailing notes | Optional | `, Card Kingdom — confirmed` |

Lines that start with `Total`, `Confirmed`, `ETA`, `Details`, `Shipping`, `Subtotal`, `Tax`, `//`, or are wrapped in `<...>` (like `<White>`) are skipped automatically.

### Example: a real Card Kingdom paste

```
Confirmed Mar-25 Card Kingdom order
Total due = 4770 <PAID as of Mar-25>
ETA March 31, 2026

Details:
    <White>
4    Savannah Lions [4ED] = 530ea
4    White Knight [4ED] = 40ea
1    Order of Leitbur <1> [FEM] = 30ea
1    Order of Leitbur <2> [FEM] = 30ea
2    Order of Leitbur <3> [FEM] = 30ea
4    Order of the White Shield [ICE] = 70ea
4    Disenchant [4ED] = 30ea
1    Zuran Orb [ICE] = 460ea
2    Serrated Arrows [HML] = 40ea
15   Plains <A> [ICE] = 50ea
```

Every line above parses correctly. Headers are skipped, color sections are skipped, prices are extracted, variants are routed to the right deck copies.

---

## Adding screenshots to this tutorial

Drop PNG files in `docs/images/` matching the names referenced in this doc (e.g. `01-empty-deck.png`, `04-shopping-list.png`). They'll render inline when this markdown is viewed.

Suggested screenshots to capture in order:

1. `01-empty-deck.png` — A deck with no cards, showing the empty state
2. `02-deck-with-needed.png` — A deck after import, showing rows with cart icons
3. `03-home-shopping-button.png` — Scanner home with all four pill buttons visible
4. `04-shopping-list.png` — Shopping list with several cards, showing deck attribution chips
5. `05-bulk-order-seeded.png` — Bulk order sheet with paste editor pre-populated
6. `06-deck-toolbar.png` — Deck detail view's top-right toolbar with all action buttons
7. `07-bulk-order-header.png` — Bulk order sheet showing the header form fields
8. `08-bulk-order-preview.png` — Preview screen with mixed match statuses
9. `09-orders-list.png` — Orders screen showing one or more orders
10. `10-order-detail.png` — Order detail with items list and bulk actions
11. `11-arrived.png` — Order after marking all arrived (green "Arrived" badge)
12. `12-deck-filtered-orders.png` — Orders screen opened from inside a deck
