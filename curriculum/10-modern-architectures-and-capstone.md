# Chapter 10 — Modern Architectures, Data Vault, and Capstone

## Learning objectives

- Map this course's concepts onto real cloud warehouse platforms
- Understand the lakehouse pattern and how it differs from a traditional warehouse
- Understand Data Vault 2.0 at a conceptual level and how it relates to Kimball marts
- Know what streaming/real-time changes and doesn't change about everything you've learned
- Plan and execute a capstone extension of this project

## How this maps to real platforms

Everything you've built runs on Postgres, but nothing you've learned is
Postgres-specific. The concepts transfer directly:

| This course | Snowflake | BigQuery | Redshift | Databricks (lakehouse) |
|---|---|---|---|---|
| `source` schema | a database/schema | a dataset | a schema | a raw/bronze table set |
| staging views | views or dynamic tables | views | views | bronze/silver Delta tables |
| dbt marts | tables/materialized views | tables | tables | gold Delta tables |
| dbt itself | dbt-snowflake adapter | dbt-bigquery adapter | dbt-redshift adapter | dbt-databricks adapter |

dbt's adapter architecture is precisely designed so that everything in
`dbt/models/`, `dbt/snapshots/`, and `dbt/tests/` in this project would
need **zero SQL changes** to run against Snowflake or BigQuery instead of
Postgres — only `profiles.yml`'s connection details change. (In practice
you'd likely pick up platform-specific materializations, like BigQuery
partition/cluster configs, as optimizations — but the modeling logic
itself is portable.) That portability is exactly why this course teaches
the concepts on Postgres rather than requiring a specific cloud account:
star schemas, SCDs, and dimensional grain are universal; the compute
engine underneath is a swappable implementation detail.

## Data lake and lakehouse, in more depth

Chapter 4 defined these briefly. The practical difference that matters
day to day:

- A **warehouse** (this project) enforces schema on write — you declare
  column types up front, and the engine rejects data that doesn't fit.
- A **lake** stores files (Parquet, CSV, JSON) in object storage with no
  enforced schema — flexible and cheap, but nothing stops two files in
  the "same" dataset from having incompatible schemas, and query engines
  have to infer structure at read time.
- A **lakehouse** (Delta Lake, Apache Iceberg, Apache Hudi) adds a
  transaction log and schema enforcement on top of lake storage, so you
  get warehouse-like guarantees (ACID transactions, schema evolution
  rules, time travel to previous table versions) while keeping data in
  open file formats that any engine can read, rather than locked inside
  a proprietary warehouse's storage format.

The dimensional modeling techniques from chapters 5–7 apply identically
in a lakehouse — a Delta table storing `fact_orders` still has a grain,
still has additive/semi-additive measures, and Delta's native support for
`MERGE` statements is exactly what you'd use to implement chapter 7's SCD2
logic by hand in that environment (conceptually the same operation dbt's
`snapshot` generates for you here).

## Data Vault 2.0

Chapter 4 mentioned Data Vault as a third modeling approach. It splits
entities into three table types instead of the source-system-shaped
tables this project uses directly as its raw layer:

- **Hubs**: just the business key and metadata (load date, source) — one
  hub per core business entity (`hub_customer`, `hub_product`).
- **Links**: record relationships/transactions between hubs (`link_order`
  connecting `hub_customer` and `hub_product` via an order event) —
  conceptually similar to this project's `source.order_items` as an
  associative table, but modeled as a first-class, append-only,
  never-updated construct.
- **Satellites**: descriptive attributes attached to a hub or link, with
  full history built in from day one (`sat_customer_address`) — every
  satellite is inherently what chapter 7 calls SCD2, by design, not as an
  afterthought.

Data Vault's appeal: hubs/links never get destructively updated, so it's
extremely resilient to source system changes and naturally
auditable/historized — valuable in large, highly regulated organizations
with many source systems and long-lived integration requirements. The
cost: significantly more tables and joins than a Kimball star for the
same business question, so Data Vault is rarely what BI tools query
directly.

The common real-world pattern: **Data Vault (or something Vault-like) as
the raw integration layer, with Kimball dimensional marts built on top of
it for consumption** — which is really just this project's staging →
marts layering, with Data Vault as a more rigorous, more historized
alternative to a plain `staging` schema when the source-integration
problem is large enough to justify it. For this project's scale, plain
staging views are the right call (chapter 9's judgment principle:
don't pay for structure you don't need yet); recognize Data Vault as the
answer when you're integrating dozens of source systems with long
retention and audit requirements, not by default.

## Streaming and real-time

Everything in this project is **batch**: `dbt run` processes a snapshot
of the source tables as they exist right now, on demand. Streaming
architectures (Kafka, or a warehouse's native streaming ingestion) reduce
latency from "next scheduled run" to "seconds after the event happens."

What changes: ingestion mechanics, and often the fact table becomes a
continuously-appending stream rather than a batch-loaded table.

What **doesn't** change: grain still has to be declared (chapter 6),
measures are still additive/semi-additive/non-additive by the same rules,
dimensions still need SCD strategies (chapter 7) — a streaming pipeline
joining events to a customer dimension has exactly the same "which
version of this dimension was true at event time" problem as
`fact_orders`' effective-dated join, just with tighter latency
requirements on how fast that dimension needs to be updated. Don't let
"streaming" sound like a different discipline — it's the same
dimensional modeling discipline under different ingestion mechanics and
latency constraints.

## Capstone: extend this project

Pick at least two of the following and implement them against this
project's infra. Each one deliberately exercises a chapter you've already
completed — treat this as an open-book final, not a new topic.

1. **New business process (chapters 4–6)**: model
   `source.customer_address_history` changes as a `fact_customer_moves`
   factless-or-lightly-measured fact table. Declare its grain explicitly
   before writing a line of SQL.
2. **Accumulating snapshot (chapter 6)**: build `fact_order_lifecycle`,
   one row per order, with `placed_date_key`, `shipped_date_key`, and a
   `days_to_ship` measure, updated in place as orders progress through
   status.
3. **Incremental + SCD2 interaction (chapters 7–8)**: convert
   `fact_orders` to incremental (you may have already done this in
   chapter 8's exercise) and specifically handle the interaction with
   `dim_customers`' SCD2 history — decide and document your answer to
   "what happens to already-loaded fact rows when a dimension gets a new
   version," rather than leaving it implicit.
4. **Data contract (chapter 9)**: add `contract: {enforced: true}` to
   `fact_orders`, explicitly declare its column types, and verify the
   build fails if you rename a column in `stg_order_items` without
   updating the contract.
5. **Snowflake it (chapter 5)**: pick one dimension, snowflake it for
   real (extra table, extra join), measure the query performance and
   ergonomics difference against the star version, and write up which one
   you'd actually ship and why.
6. **New source system**: add a second, independent source table (e.g., a
   `support_tickets` table you design and seed yourself) and integrate it
   into a conformed `dim_customers` — practicing chapter 5's bus matrix
   concept for real, with a second business process that shares a
   dimension with `fact_orders`.

There's no single right answer to any of these — the goal is applying
every prior chapter's judgment calls (grain, additivity, SCD type, test
coverage, star vs. snowflake) to a new problem, not matching a reference
solution.

## Where to go from here

- Pick a real cloud warehouse (most offer a free tier — Snowflake,
  BigQuery sandbox, or a small managed Postgres) and port this project to
  it, changing only `profiles.yml`.
- Read *The Data Warehouse Toolkit* cover to cover — this course covered
  its core ideas; the book has dozens of industry-specific worked
  examples (retail, healthcare, financial services, telecom) that go far
  deeper than one e-commerce dataset can.
- Look into orchestration (Airflow, Dagster, or a cloud warehouse's native
  scheduler) for running this pipeline on a schedule rather than by hand
  — a natural next step once the modeling itself is solid, deliberately
  out of scope for this course so it could stay focused on modeling
  rather than infrastructure.

## Further study

- *The Data Warehouse Toolkit* (3rd ed.), Ralph Kimball & Margy Ross —
  read the whole thing now that you have the vocabulary for it.
- *Building a Scalable Data Warehouse with Data Vault 2.0*, Dan
  Linstedt & Michael Olschimke — the primary Data Vault reference.
- Databricks' and Delta Lake's own documentation on the lakehouse
  architecture, and the Apache Iceberg documentation for the
  vendor-neutral open-table-format perspective.
- Martin Kleppmann, *Designing Data-Intensive Applications* — the best
  single book for understanding streaming, CDC, and batch/streaming
  unification at a systems level.

---

You've now covered the full arc: what a data model is, how to read and
build one at the conceptual/logical/physical levels, why and how to
normalize an OLTP system, why and how to deliberately denormalize for
analytics, how to design fact and dimension tables correctly, how to
handle change over time, how data actually moves through a pipeline, and
how to know whether you can trust it once it arrives. That's the whole
discipline. Go build something real with it.
