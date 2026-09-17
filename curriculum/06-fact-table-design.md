# Chapter 6 — Fact Table Design: Grain, Types, and Additivity

## Learning objectives

- Declare grain precisely and recognize grain violations
- Classify measures as additive, semi-additive, or non-additive
- Distinguish the three fact table types: transaction, periodic snapshot, accumulating snapshot
- Use degenerate dimensions and factless fact tables appropriately

## Grain, precisely

Chapter 5 introduced grain as "the sentence describing one fact row."
This chapter is about taking that seriously enough that it becomes a
mechanical test you can apply to every candidate column.

`marts.fact_orders`' grain: **one row per order line item**
(`order_item_id`). Not "one row per order" — an order with 3 line items
produces 3 fact rows. Check it:

```sql
select order_id, count(*) as line_items
from marts.fact_orders
group by order_id
order by line_items desc
limit 5;
```

You'll see orders with more than one row. That's correct, given the
declared grain — and it's *why* `days_to_ship` and `amount_paid` (which
are order-level, not line-item-level) look like they "repeat" across an
order's rows. That repetition isn't a bug; it's the direct, expected
consequence of the grain being finer than the attribute. It does mean
**you must not blindly `sum()` those columns** — summing `amount_paid`
across an order's 3 line items triples it. This single mistake — summing
a column that's actually constant across the grain — is probably the most
common bug in real-world dimensional models built by beginners.

**The grain test**: before adding any column to a fact table, ask "is this
true, and only true, at the declared grain — and not at some coarser
grain?" `net_amount` passes (it's a line-item-specific dollar amount).
`amount_paid` technically "fits" (it has a value at this grain) but
violates the *spirit* of the grain because it's constant across all of an
order's rows — which is exactly why the additivity rules below exist: to
tell you what you're allowed to do with a column, given how it behaves
across the grain.

## Additive, semi-additive, non-additive

Once data is in a fact table, people will `sum()` it across all sorts of
dimensions (by month, by customer, by product...). Whether that's
*correct* depends on the measure:

- **Fully additive**: safe to sum across *any* dimension. `quantity`,
  `net_amount`, `cost_amount`, `margin_amount` in `fact_orders` are all
  fully additive — summing net_amount across products, customers, or time
  all produce meaningful totals.
- **Semi-additive**: safe to sum across *some* dimensions, not others.
  The classic example is an account balance snapshot: summable across
  accounts (total balance across all accounts, at a point in time), but
  *not* summable across time (summing Monday's balance and Tuesday's
  balance for the same account is meaningless). `days_to_ship` in this
  project is semi-additive in a different sense — it's meaningful to
  *average*, not sum, and only at the order grain (deduplicated), never
  summed across line items.
- **Non-additive**: never safe to sum, period. Ratios and percentages —
  `discount_pct` in `fact_orders` — can't be summed across anything; a 10%
  discount and a 20% discount on two different orders don't sum to a
  meaningful "30%." (You can still average them, weighted correctly, but
  that's a different operation than the aggregate queries chapter 5's
  star schema is optimized for.)

```sql
-- correct: fully additive measure, safe to sum across any grouping
select date_trunc('month', d.date_day) as month, sum(f.net_amount)
from marts.fact_orders f join marts.dim_date d on d.date_key = f.order_date_key
group by 1;

-- WRONG: amount_paid repeats per line item — this triples/quadruples real revenue
select sum(amount_paid) from marts.fact_orders;    -- do not do this

-- correct alternative: dedupe to the order grain first
select sum(amount_paid) from (
    select distinct order_id, amount_paid from marts.fact_orders
) deduped;
```

Run both `amount_paid` queries above against the seeded data and compare
to `select sum(amount) from source.payments` — the naive one will be
noticeably too high.

## The three fact table types

- **Transaction fact table**: one row per event, at the moment it
  happened. `fact_orders` is this type — every row is a discrete sale
  event, and the table only grows (append-only, roughly).
- **Periodic snapshot fact table**: one row per entity per fixed time
  interval (daily, monthly), regardless of whether anything happened —
  e.g., a `fact_inventory_snapshot` with one row per product per day
  recording the stock level, even on days with zero activity. Used when
  the *state at a point in time* matters more than individual events
  (inventory levels, account balances).
- **Accumulating snapshot fact table**: one row per instance of a
  multi-step process (an order's full lifecycle: placed → paid → shipped →
  delivered), with columns for each milestone's date, and the row gets
  *updated in place* as the process progresses — unlike the other two
  types, which are essentially insert-only.

This project only builds a transaction fact table. As a thought exercise:
a `fact_order_lifecycle` accumulating snapshot for this same business
would have one row per order (not per line item — a different grain
entirely) with columns like `placed_date_key`, `shipped_date_key`,
`delivered_date_key`, updated as each milestone happens. Recognizing which
of the three types a reporting requirement calls for is most of the battle
in real fact table design.

## Degenerate dimensions

A **degenerate dimension** is a dimension-like attribute kept directly on
the fact table instead of in its own dimension table, because it has no
further attributes worth modeling separately. `fact_orders.order_id`,
`order_status`, and `channel` are degenerate dimensions — `order_id` is
useful for grouping/drilling into "all line items on this order" and as a
natural key back to the source system, but it doesn't warrant a
`dim_orders` table with its own surrogate key and attribute columns; there
simply isn't a meaningful `dim_orders` here beyond what's already on the
fact row.

```sql
select order_id, order_status, channel, count(*)
from marts.fact_orders
group by 1, 2, 3
order by 1
limit 10;
```

## Factless fact tables

A **factless fact table** records that an event happened, with no
numeric measure at all — just the dimensional context. Common example:
"which students attended which classes" (an attendance fact with no
measure — the *existence* of the row is the fact). This project doesn't
have one, but a natural extension would be a `fact_page_views` for the
e-commerce site's browsing activity: one row per (customer, product,
timestamp) view event, with no measure column — you'd derive "count of
views" by counting rows, not summing a column.

## Exercise

1. Write, in one sentence, the grain of `marts.fact_orders`. Then write
   the grain of a hypothetical `fact_payments` built directly from
   `source.payments`. Are they the same grain? Why would you keep them as
   two separate fact tables rather than merging payments into
   `fact_orders`?
2. Classify every numeric column in `marts.fact_orders`
   (`quantity`, `unit_price`, `discount_pct`, `net_amount`, `cost_amount`,
   `margin_amount`, `days_to_ship`, `amount_paid`) as fully additive,
   semi-additive, or non-additive, and justify each in one line.
3. Design (on paper — column list + grain statement is enough, no need to
   implement) an accumulating snapshot fact table for the order lifecycle
   described above. List its milestone date columns and its grain.

## Common mistakes

- **Vague grain statements.** "One row per order" when it's actually one
  row per order line item is the single most common root cause of wrong
  aggregate numbers in real dimensional models — including the
  `amount_paid` trap demonstrated above.
- **Summing non-additive or semi-additive measures reflexively**, because
  `SUM()` is the first aggregate function everyone reaches for.
- **Building a dimension table for a degenerate dimension "just in
  case."** If there's nothing to hang off it beyond an identifier, it
  doesn't need its own table — that's needless joins for no descriptive
  payoff.

## Further study

- *The Data Warehouse Toolkit* (3rd ed.), chapter 6 (fact table
  techniques) — covers periodic and accumulating snapshots in much
  greater depth, with worked industry examples.
- Kimball Group's "Design Tip" archive (search "Kimball Group design
  tips grain") — short, focused essays on grain declaration specifically.

Next: [Chapter 7 — Slowly Changing Dimensions](07-slowly-changing-dimensions.md)
