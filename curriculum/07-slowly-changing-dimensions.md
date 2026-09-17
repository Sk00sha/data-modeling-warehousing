# Chapter 7 — Slowly Changing Dimensions

## Learning objectives

- Explain the problem SCDs solve and why it matters for correctness, not just completeness
- Implement SCD Type 1, Type 2, and Type 3 by hand in SQL
- Use dbt's `snapshot` feature to automate Type 2
- Correctly join a transaction fact table to an effective-dated (Type 2) dimension

## The problem

Dimension attributes change. A customer moves city, a product's category
gets reclassified, an employee changes region. An OLTP system usually just
`UPDATE`s the row — the old value is gone, overwritten, because OLTP only
needs *current* truth (chapter 4).

A warehouse frequently needs the opposite: "what was the customer's region
*at the time* they placed this order?" — because that's the region the
marketing campaign that drove the sale actually targeted, regardless of
where the customer lives today. If your dimension only ever stores current
state, every historical fact silently gets re-attributed to the customer's
*current* attributes whenever you join — a subtle, serious correctness
bug, not just a completeness gap. This is a direct continuation of chapter
3's point about `order_items.unit_price`: a value changing over time is a
signal you need history, not just current state.

`source.customer_address_history` in this project exists to give you real
before/after data:

```sql
select customer_id, city, country, segment, valid_from, valid_to
from source.customer_address_history
where customer_id = (select min(customer_id) from source.customer_address_history)
order by valid_from;
```

You'll see the same customer with two rows — an earlier version and a
current one — with `valid_to` marking when the earlier version stopped
being true.

## SCD Type 0 — retain original

Never update the attribute after first load. Rare in practice, but useful
for things like "original acquisition channel" — a fact you deliberately
want frozen at first-seen value forever, regardless of what changes later.

## SCD Type 1 — overwrite

Update in place, keep no history. Simplest, cheapest, and correct when you
genuinely don't care about historical accuracy for that attribute —
correcting a typo in a customer's name is a good Type 1 case: you don't
want old orders to show the *misspelled* name.

`marts.dim_products` in this project is Type 1 — it only stores current
product attributes. Open `dbt/models/marts/dim_products.sql` and note
there's no `valid_from`/`valid_to` anywhere — every rebuild just replaces
the row:

```sql
select product_id, product_name, category, unit_price
from marts.dim_products
limit 5;
```

If a product's price changes, `dbt run` simply overwrites the row. Every
historical `fact_orders` row is unaffected because `unit_price` was
already captured on the fact row at the correct historical value (chapter
6's point about `order_items.unit_price` again — this is the same
principle applied at the dimension level).

## SCD Type 2 — add a new row, track history

Instead of overwriting, insert a new row with a new surrogate key, and
mark the effective date range on both the old and new row (`valid_from`,
`valid_to`, often plus an `is_current` flag). This is the standard,
most-used SCD technique, and it's what `marts.dim_customers` implements in
this project.

### By hand (the exercise)

Before looking at the tooled version, implement Type 2 yourself against
`source.customer_address_history`, which is already shaped like SCD2
history (it has `valid_from`/`valid_to`):

```sql
-- "as of" query: what was true for customer 3 on a given historical date?
select customer_id, city, country, segment
from source.customer_address_history
where customer_id = 3
  and valid_from <= '2024-06-01'
  and (valid_to is null or valid_to > '2024-06-01');
```

Then write the harder direction yourself: given `source.customers`
(current state only, no history) and a hypothetical daily "changes feed,"
write the `INSERT ... SELECT` / `UPDATE` pair that would (a) close out the
old row by setting its `valid_to`, and (b) insert a new row with the new
attribute values and `valid_to = null`. This is exactly the SQL that
tools like dbt's snapshot feature generate for you — write it once by hand
so the tool doesn't feel like magic.

### Tooled: dbt snapshots

`dbt/snapshots/customers_snapshot.sql` does this automatically:

```sql
{% snapshot customers_snapshot %}
{{ config(
    target_schema='snapshots',
    unique_key='customer_id',
    strategy='check',
    check_cols=['city', 'country', 'segment', 'email'],
) }}
select customer_id, first_name, last_name, email, city, country, segment
from {{ source('ecommerce', 'customers') }}
{% endsnapshot %}
```

Every time `dbt snapshot` runs, it compares the listed `check_cols`
against the latest snapshotted version per `customer_id`. If any differ,
it closes the old row (`dbt_valid_to = now`) and inserts a new one
(`dbt_valid_from = now`, `dbt_valid_to = null`) — the exact mechanic you
just wrote by hand, generalized and automated. `marts.dim_customers` is
built directly on top of this snapshot:

```sql
select customer_key, customer_id, city, country, segment, valid_from, valid_to, is_current
from marts.dim_customers
order by customer_id, valid_from
limit 10;
```

Try it live: update a customer's city in the source table, re-run the
snapshot, and watch a new dimension row appear.

```bash
docker compose exec postgres psql -U warehouse -d warehouse \
  -c "update source.customers set city = 'Lisbon' where customer_id = 1;"
make dbt-build   # re-runs seed/snapshot/run/test
```
```sql
select customer_key, city, valid_from, valid_to, is_current
from marts.dim_customers
where customer_id = 1
order by valid_from;
```
You should now see two rows for `customer_id = 1`.

### Joining a fact table to a Type 2 dimension

This is the part people get wrong most often: **you cannot join a
transaction fact table to a Type 2 dimension on the natural key alone** —
that would silently pick up whichever dimension row the join happens to
match (often ambiguously, or the current one), not the one that was true
*when the fact happened*. `dbt/models/marts/fact_orders.sql` joins
effective-dated, on purpose:

```sql
left join lateral (
    select cust.*
    from customers cust
    where cust.customer_id = o.customer_id
    order by
        case
            when o.order_date >= cust.valid_from::date
                and (cust.valid_to is null or o.order_date < cust.valid_to::date)
            then 0
            else 1
        end,
        cust.valid_from
    limit 1
) c on true
```

This picks the customer dimension row whose `[valid_from, valid_to)` range
contains the order's date — falling back to the earliest known version
for orders older than the dimension's own history (a real-world
consequence of snapshot-based SCD2: there's no history before you started
snapshotting). The result: `fact_orders.customer_key` always points at the
dimension row that was *true at the time of the order*, not the
customer's current state.

## SCD Type 3 — add a new column

Keep only the *previous* value in an extra column (`previous_city`,
`current_city`) — bounded, limited history (usually just one prior value),
no new rows. Rarely used alone today; mostly superseded by Type 2, but
occasionally combined with it (see Type 6 below) when a report specifically
needs "previous vs. current" as adjacent columns rather than as separate
rows.

## Beyond 1/2/3 (brief)

- **Type 4**: current values in the main dimension table, full history in
  a separate history table — used when the main dimension needs to stay
  small/fast and history is queried rarely.
- **Type 6** ("hybrid," 1+2+3 combined): a Type 2 row structure that
  *also* carries a "current value" column (Type 1-style) alongside the
  historical value — lets you filter/group by current attributes while
  still preserving the historically-accurate value on the same row.
- **Type 7**: dual keys — both a durable natural-key reference and a
  point-in-time surrogate key on the fact table, letting the same fact
  table support both "as it was" and "as it is now" queries without two
  separate joins.

You won't implement these in this course, but recognizing the names and
the problem each solves is enough to know when to reach for one.

## Exercise

1. Complete the by-hand Type 2 SQL exercise above against
   `source.customer_address_history` before reading the tooled section, if
   you haven't already.
2. Run the "update a customer's city, re-snapshot" exercise above. Then
   write a query against `fact_orders` joined to `dim_customers` that
   proves old orders still show the *old* city, not the new one.
3. `marts.dim_products` is Type 1. Argue for or against converting it to
   Type 2 — what real business question would justify tracking product
   price history via SCD2 rather than relying on `fact_orders.unit_price`
   (which already captures the transaction-time price)?

## Common mistakes

- **Joining a fact to a Type 2 dimension on the natural key only.**
  Covered at length above — it's the single most consequential mistake in
  this chapter.
- **Choosing Type 2 for every attribute reflexively.** Not every change is
  worth tracking — a corrected typo (Type 1) doesn't need a new
  historical row; ask "would a real business question ever need the *old*
  value here?" before defaulting to Type 2.
- **Forgetting the fallback case.** A Type 2 dimension built from a
  snapshot only has history starting from when snapshotting began — facts
  older than that need an explicit fallback (as shown above), or they'll
  silently fail to join.

## Further study

- *The Data Warehouse Toolkit* (3rd ed.), chapter 5 — the canonical
  reference for all SCD types, including 4/6/7 in full depth.
- dbt Labs documentation on the "snapshot" node type and its `check` vs
  `timestamp` strategies.

Next: [Chapter 8 — ETL/ELT and Data Pipelines](08-etl-elt-and-data-pipelines.md)
