# Chapter 4 — Data Warehouse Architecture & Core Concepts

## Learning objectives

- Explain OLTP vs. OLAP and why the same schema design serves both badly
- Describe the layered warehouse architecture (source → staging → warehouse → marts)
- Compare the Inmon and Kimball philosophies and know which this course teaches
- Define: data warehouse, data mart, data lake, lakehouse

## OLTP vs. OLAP

|  | OLTP (source systems) | OLAP (warehouse) |
|---|---|---|
| Purpose | Run the business (place an order) | Understand the business (how much did we sell last quarter, by region?) |
| Query shape | Few rows, by primary key | Many rows, aggregated, scanned |
| Schema | Normalized (chapter 3) | Denormalized, dimensional (chapter 5) |
| Writes | Frequent, small, concurrent | Batch or streaming loads, rarely row-by-row updates |
| Example | `source.orders` in this project | `marts.fact_orders` in this project |

`source.*` and `marts.*` in this repo's dbt project are a working example
of exactly this split: same underlying business facts, two completely
different physical shapes, optimized for two completely different access
patterns. Run both of these and *feel* the difference:

```sql
-- OLTP-shaped question: fast by design, touches one order
select * from source.orders where order_id = 42;

-- OLAP-shaped question: touches every row, must aggregate
select
    date_trunc('month', o.order_date) as month,
    sum(oi.quantity * oi.unit_price * (1 - oi.discount_pct/100.0)) as revenue
from source.orders o
join source.order_items oi on oi.order_id = o.order_id
group by 1
order by 1;
```

The second query, run against the normalized source schema, needs a join
for every single row. Run the equivalent against `marts.fact_orders` (built
in chapter 5) and there's no join needed for the aggregation at all — the
revenue is a column on the fact table already.

## Why not just query the OLTP database for analytics?

You can, at small scale, and plenty of startups do exactly that for a
while. It breaks down for concrete reasons:

- **Contention**: a heavy analytical scan competing for the same rows and
  I/O as live transactional traffic can slow down or lock out paying
  customers' checkouts.
- **Schema mismatch**: the questions analysts ask ("revenue by region by
  month") don't map cleanly onto a normalized schema without repeated,
  expensive joins — see above.
- **History**: OLTP systems often only keep *current* state (an `UPDATE`
  overwrites the old value). Analytics frequently needs to know what was
  true *at the time* — chapter 7 is entirely about this problem.
- **Multiple sources**: a real business has more than one source system
  (the e-commerce platform, the support ticketing tool, the marketing
  platform) — a warehouse is the one place that combines them.

## The layered architecture

```
Source systems  →  Staging  →  Warehouse (integrated, historized)  →  Marts (consumption)
```

This project's dbt layering mirrors this directly:

- **Source** (`source.*` in Postgres) — the OLTP system(s). Read-only from
  the warehouse's perspective.
- **Staging** (`dbt/models/staging/`) — one view per source table,
  renamed and typed, with zero joins and zero business logic. Its only
  job is to be a stable, clean interface to a source that might otherwise
  change underneath you.
- **Intermediate** (`dbt/models/intermediate/`) — reusable joined/derived
  building blocks (`int_orders_enriched`). Not meant to be queried
  directly by end users; it's plumbing for the marts layer.
- **Marts** (`dbt/models/marts/`) — the dimensional model. This is what
  BI tools and analysts actually query.

Run `make dbt-docs` and look at the DAG — you're looking at this exact
architecture rendered as a graph.

## Inmon vs. Kimball

Two influential — and historically opposed — philosophies for how to
build the warehouse layer:

- **Bill Inmon**: build a normalized, enterprise-wide warehouse first
  (the "single source of truth," often still fairly 3NF-like), then derive
  denormalized data marts from it per department. Top-down: model the
  whole enterprise, then specialize.
- **Ralph Kimball**: build dimensional marts directly, organized around
  business processes, and make them "conformed" (sharing common dimension
  definitions) so they compose into a de facto enterprise warehouse over
  time. Bottom-up: model one business process well, then another, and let
  the enterprise view emerge.

This course teaches **Kimball's dimensional modeling** (chapters 5–7)
because it's the more widely practiced approach today, maps directly onto
how modern cloud warehouses and BI tools expect data to be shaped, and is
easier to learn incrementally — you build one fact table around one
business process (orders, in this project) rather than needing to model
an entire enterprise before shipping anything useful. Chapter 10 covers
**Data Vault**, a third approach popular for the raw-integration layer in
larger organizations, and how it relates to (rather than replaces) Kimball
marts on top.

## Warehouse, mart, lake, lakehouse — definitions

- **Data warehouse**: a system optimized for structured, historized,
  query-heavy analytics — typically a relational (or relational-like)
  engine, schema-on-write.
- **Data mart**: a subset of the warehouse scoped to one business area or
  team (sales mart, finance mart). Can be a physical subset or just a
  set of views.
- **Data lake**: a storage layer (often object storage — S3, GCS, ADLS)
  holding raw, semi-structured, or unstructured data at low cost,
  schema-on-read. No enforced structure until you query it.
- **Lakehouse**: storage-layer tooling (Delta Lake, Iceberg, Hudi) that
  adds warehouse-like guarantees — ACID transactions, schema enforcement,
  time travel — on top of lake storage, aiming to combine lake economics
  with warehouse reliability. Covered in more depth in chapter 10.

In this project, Postgres plays both the "source system" and the
"warehouse" role (via separate schemas) purely for simplicity — in a real
company these would almost always be physically separate systems.

## Exercise

1. Time both queries from the "OLTP vs OLAP" section above with `EXPLAIN
   ANALYZE` against this project's seeded data. Note the difference in
   query plan shape (index scan vs. sequential scan / aggregate nodes).
2. Draw (ASCII is fine) the layered architecture diagram for this
   project, labeling each box with the actual schema/directory it
   corresponds to.
3. In two sentences, explain to a hypothetical stakeholder why the
   e-commerce app's database shouldn't be the thing PowerBI/Tableau
   connects to for the company's board deck.

## Common mistakes

- **Treating "data warehouse" as a specific product.** It's an
  architectural pattern, not a product name — Snowflake, BigQuery,
  Redshift, and a well-organized Postgres schema (like this project) can
  all serve the warehouse role.
- **Skipping staging "because it's just a view anyway."** The staging
  layer's value isn't complexity, it's *isolation* — when a source system
  renames a column, you fix it in exactly one place.
- **Assuming Kimball and Inmon are mutually exclusive in practice.** Most
  real organizations blend ideas from both; treat them as two ends of a
  spectrum, not a binary choice.

## Further study

- *The Data Warehouse Toolkit* (3rd ed.), Ralph Kimball & Margy Ross —
  the definitive Kimball reference; you'll be returning to it constantly
  through chapter 7.
- *Building the Data Warehouse*, W.H. Inmon — the original top-down case,
  worth reading even if you end up practicing Kimball.
- dbt Labs' "Guide to dbt" documentation on project structure
  (staging/intermediate/marts), which this project's layout follows.

Next: [Chapter 5 — Dimensional Modeling: Star and Snowflake Schemas](05-dimensional-modeling-star-snowflake.md)
