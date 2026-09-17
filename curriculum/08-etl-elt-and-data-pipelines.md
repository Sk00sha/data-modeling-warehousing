# Chapter 8 — ETL/ELT and Data Pipelines

## Learning objectives

- Explain the difference between ETL and ELT and why ELT became dominant
- Design a layered transformation pipeline (staging → intermediate → marts)
- Distinguish full-refresh vs. incremental loading, and when each applies
- Understand idempotency and why it's non-negotiable for pipeline code

## ETL vs. ELT

- **ETL** (Extract, Transform, Load): transform the data *before* loading
  it into the warehouse, typically in a separate processing layer/tool
  outside the database.
- **ELT** (Extract, Load, Transform): load raw data into the warehouse
  first, then transform it *inside* the warehouse using the warehouse's
  own compute (SQL).

ELT won out over the last decade mainly because modern cloud warehouses
got cheap and powerful enough at SQL-based compute that there's rarely a
reason to build a separate transformation engine — and because keeping
raw, untransformed data around (rather than discarding it after an ETL
transform step) turned out to be valuable: you can always re-derive a
new transformation later without re-extracting from the source.

This project is ELT: `source.*` is loaded (seeded) as-is with no
transformation, and every transformation from that point on
(`dbt/models/staging/`, `intermediate/`, `marts/`) is plain SQL running
inside Postgres, orchestrated by dbt. dbt itself is squarely an ELT tool —
it does the "T," assuming "E" and "L" already happened.

## The layered pipeline, in practice

You've seen the three layers since chapter 4; here's what each one is
actually *for*, mechanically:

**Staging** (`dbt/models/staging/stg_orders.sql`):
```sql
with source as (
    select * from {{ source('ecommerce', 'orders') }}
)
select
    order_id,
    customer_id,
    employee_id,
    order_status,
    channel,
    order_date,
    ship_date,
    (ship_date - order_date) as days_to_ship,
    created_at,
    updated_at
from source
```
One source table in, one view out. Renamed/typed/lightly derived
(`days_to_ship`), but **no joins**. This is the layer that absorbs source
system quirks — if the source renamed a column tomorrow, you'd fix it in
exactly this one file, and every downstream model is unaffected.

**Intermediate** (`dbt/models/intermediate/int_orders_enriched.sql`):
joins `stg_orders` with `stg_employees` and an aggregated `stg_payments`,
producing a reusable "order + who owns it + how much was paid" building
block. Not meant to be queried by end users directly — it exists so
`fact_orders` (and any future order-level model) doesn't repeat that join
logic.

**Marts** (`dbt/models/marts/fact_orders.sql`): the final, consumption-ready
dimensional model, built from staging + intermediate.

Run `dbt run --select stg_orders+` (from inside the `dbt` container or
locally with dbt installed) to see exactly which downstream models depend
on `stg_orders` — that `+` is dbt's "and everything downstream" selector,
and it's tracing this exact dependency chain.

## Full refresh vs. incremental

Every model in this project is either a `view` (staging/intermediate —
recomputed from the underlying tables on every query, no storage) or a
`table` materialized as a **full refresh** (marts — `dbt run` drops and
rebuilds the entire table from scratch every time).

Full refresh is simple and always correct, but doesn't scale — rebuilding
`fact_orders` from scratch is fine at 6,000 rows and increasingly
expensive at 6 billion. The alternative is **incremental materialization**:
only process new/changed source rows since the last run, and merge them
into the existing table rather than rebuilding it.

dbt's incremental materialization looks like this (not implemented in this
project's `fact_orders` — see the exercise):

```sql
{{ config(materialized='incremental', unique_key='order_item_id') }}

select ...
from {{ ref('stg_order_items') }} oi
join {{ ref('int_orders_enriched') }} o on o.order_id = oi.order_id
...
{% if is_incremental() %}
where o.updated_at > (select max(updated_at) from {{ this }})
{% endif %}
```

The `{% if is_incremental() %}` block only applies on subsequent runs
(not the first build) and filters to rows that changed since the last
run — dbt then merges (upserts) those rows into the existing table by
`unique_key` instead of rebuilding everything.

This project keeps `fact_orders` as a full-refresh table deliberately,
for two reasons worth understanding rather than skipping past: (1) at this
data volume, incremental logic adds real complexity for zero practical
benefit — premature optimization; (2) reasoning correctly about
incremental logic (especially the effective-dated SCD2 join from chapter
7 — what happens to an already-loaded fact row if the dimension it joined
to gets a new version later?) is genuinely one of the harder problems in
production warehousing, and deserves to be tackled as a deliberate
exercise, not inherited silently.

## Change Data Capture (CDC), briefly

The `updated_at > last_run` pattern above assumes the source reliably
updates a timestamp on every change and that you can query it directly.
At larger scale/lower latency requirements, teams instead use **CDC**:
tooling (Debezium, or a cloud warehouse's native connectors) that reads a
source database's write-ahead log/binlog directly and streams every
insert/update/delete as an event, without querying the source table at
all. This avoids missing changes between polling windows and avoids
putting query load on the source system, at the cost of more
infrastructure. Not implemented in this project — mentioned so you
recognize the term and know when to reach for it (typically: sub-hour
latency requirements, or a source system too large/sensitive to poll
directly).

## Idempotency

A pipeline step is **idempotent** if running it twice (with the same
input) produces the same result as running it once — no duplicated rows,
no corrupted state. This matters because pipelines *will* be re-run: a
job retries after a transient failure, someone reruns a backfill, a
scheduler double-fires.

`dbt run` on a full-refresh table is trivially idempotent — it's a full
`DROP`/`CREATE` every time. Incremental models must be made idempotent
deliberately, via `unique_key` (dbt uses it to `merge`/upsert rather than
blindly `insert`, so re-running the same incremental batch overwrites
rather than duplicates). This project's `stg_order_items.sql` computing
`net_amount` as a pure function of `quantity`, `unit_price`, and
`discount_pct` (rather than, say, incrementing a running total) is
idempotent by construction — rerun it a hundred times, same answer every
time. Contrast with a hypothetical (bad) pipeline step that does
`update product_stock set qty = qty - 1` — running that twice for the same
event silently double-decrements stock. If you can't describe a
transformation as a pure function of its inputs, be suspicious of it.

## Exercise

1. Convert `dbt/models/marts/fact_orders.sql` to an incremental model,
   keyed on `order_item_id`, filtering on `o.updated_at` from
   `int_orders_enriched`. Test it: run a full build, then update a few
   source orders' `updated_at`, then run `dbt run` again and confirm only
   those rows were reprocessed (check dbt's logged row counts).
2. Now break your own incremental model on purpose: change a
   `dim_customers` attribute (triggering a new SCD2 row, chapter 7) for a
   customer with existing historical orders, without touching those
   orders' `updated_at`. Does your incremental `fact_orders` still resolve
   `customer_key` correctly for *future* orders from that customer? What
   about past orders already loaded before the change — should they be
   affected, and does your incremental filter accidentally skip
   reprocessing them? Write down what you find; there's no single "right"
   answer here, only a tradeoff you now understand instead of inherited
   blind.
3. In two sentences, explain why `stg_orders.sql` having zero joins is a
   deliberate design constraint, not just a simplicity preference.

## Common mistakes

- **Reaching for incremental materialization before it's needed.** It
  adds real complexity (see exercise 2) — don't pay that cost until full
  refresh actually becomes too slow.
- **Non-idempotent transformations.** Any transformation that depends on
  its own previous output (running totals, `+= 1` style updates) will
  produce wrong answers the moment it's ever re-run, which it will be.
- **Putting business logic in the staging layer.** Staging's entire value
  is being a boring, mechanical, source-shaped pass-through — joins and
  derived business metrics belong in intermediate/marts.

## Further study

- dbt Labs documentation on incremental models, materializations, and the
  `is_incremental()` macro.
- Martin Kleppmann, *Designing Data-Intensive Applications*, chapter 11
  (stream processing) — the deepest treatment of CDC and idempotent
  processing available in a single book.

Next: [Chapter 9 — Data Quality, Testing, and Lifecycle Governance](09-data-quality-testing-and-governance.md)
