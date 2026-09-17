# Data Modeling & Data Warehousing — Curriculum + Hands-On Infra

A self-contained course for learning data modeling and data warehousing end
to end, paired with a real (small) environment to practice on: Postgres as
both the source system and the warehouse, and dbt as the modeling/testing/
lineage layer that carries every chapter's exercises from "raw tables" to
"tested star schema."

```
curriculum/     10 chapters (+ orientation) — the course itself
infra/          docker-compose services: Postgres, pgAdmin, source schema + seed data
dbt/            the dbt project: staging -> intermediate -> marts, snapshots, tests, docs
```

## Quickstart

```bash
cp .env.example .env        # defaults are fine, edit if you want
make up                     # docker compose up -d postgres pgadmin
make dbt-build               # dbt build: seeds + SCD2 snapshot + models + tests, in dependency order
```

That's it: a seeded OLTP schema, a dimensional model built on top of it,
and a green test suite. Then:

- **pgAdmin** — http://localhost:5050 (login from `.env`, server is
  pre-registered as "Warehouse (docker)")
- **dbt docs** — `make dbt-docs`, then open http://localhost:8080 for the
  full lineage graph and column-level documentation
- **psql** — `make psql` for a raw SQL shell

Tear down with `make down` (keeps data) or `make reset` (wipes volumes and
starts clean — use this if you want to re-run the seed script after
editing it).

## What's actually in the box

**`infra/postgres/init/`** — runs once, on first container boot, and
builds a small but realistic e-commerce OLTP schema in the `source`
schema: `customers`, `products`, `employees`, `orders`, `order_items`,
`payments`, plus a `customer_address_history` table that exists purely so
chapter 7 has real "before/after" data to practice Slowly Changing
Dimensions on. ~200 customers, 60 products, 3,000 orders, ~6,000 line
items — enough to make grain and aggregation mistakes actually visible in
query results, small enough to `docker compose up` in seconds.

**`dbt/`** — this is the "lifecycle & quality" layer the course keeps
referring back to:

| Layer | What it does |
|---|---|
| `models/staging/` | 1:1 views over `source.*`, renamed/typed/cleaned. Nothing is joined here. |
| `models/intermediate/` | Reusable joined/aggregated building blocks (e.g. `int_orders_enriched`). |
| `models/marts/` | The actual star schema: `dim_customers`, `dim_products`, `dim_employees`, `dim_date`, `fact_orders`. |
| `snapshots/` | `customers_snapshot` — a real Type-2 SCD, built with dbt's snapshot feature instead of hand-written merge SQL. |
| `seeds/` | `region_country_map.csv` — small reference data loaded via `dbt seed`, not extracted from a source system. |
| schema tests | Every table gets `unique`/`not_null`/`relationships`/`accepted_values` tests; there's also a custom `not_negative` test and a singular reconciliation test (`tests/assert_orders_reconcile_with_payments.sql`) that catches join fan-out or bad measure formulas that per-row tests can't see. |
| `dbt docs` | Auto-generated data dictionary + a DAG showing exactly how raw tables become the star schema. |

This project deliberately has **zero external dbt package dependencies**
(no `dbt_utils`, no internet access needed at build time beyond pulling
the Docker images once) — surrogate keys use `md5()`, the date dimension
uses a recursive CTE. That's a design choice, not an oversight: it keeps
the environment fully offline-reproducible, and chapter 10 discusses when
you *would* reach for `dbt_utils` or a real orchestrator in production.

## How the curriculum uses the infra

Each chapter in `curriculum/` names the exact tables/models to look at and
gives exercises against this same dataset, so you're not re-learning a new
schema every chapter. Rough map:

- Ch 1–3 (foundations, modeling levels, normalization) → `infra/postgres/init/01_schema_source.sql`
- Ch 4–6 (warehouse architecture, star schema, fact design) → `dbt/models/marts/`
- Ch 7 (SCDs) → `source.customer_address_history` (manual SQL) + `snapshots/customers_snapshot.sql` (tooled)
- Ch 8 (ETL/ELT) → `dbt/models/staging/` → `intermediate/` → `marts/` layering
- Ch 9 (data quality, lifecycle, governance) → `dbt/models/**/*.yml` tests, `dbt/tests/`, `dbt docs`
- Ch 10 (modern architectures + capstone) → extend this project yourself

Start at [`curriculum/00-orientation.md`](curriculum/00-orientation.md).

## Requirements

- Docker + Docker Compose v2
- Nothing else — dbt runs inside its own container (`docker compose run --rm dbt ...`)
