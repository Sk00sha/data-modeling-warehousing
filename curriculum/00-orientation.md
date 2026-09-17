# Chapter 0 — Orientation

## Who this is for

You can write SQL and you've used a relational database, but you've never
had to *design* one from scratch, and terms like "star schema," "SCD Type
2," or "grain" are either unfamiliar or fuzzy. By the end of chapter 10
you'll be able to take a messy OLTP schema and turn it into a tested,
documented dimensional model — and explain why you made every design
decision along the way.

## How the course is structured

10 chapters, roughly three arcs:

1. **Foundations (1–3)** — what a data model even is, the three levels of
   modeling, and the relational theory (normalization) that OLTP systems
   are built on. You need this before dimensional modeling makes sense,
   because dimensional modeling is best understood as a deliberate,
   informed *departure* from 3NF, not ignorance of it.
2. **Warehousing & dimensional modeling (4–7)** — OLTP vs. OLAP, star vs.
   snowflake schemas, fact table design, and Slowly Changing Dimensions.
   This is the practical core of the course.
3. **Pipelines, quality, and the modern landscape (8–10)** — how data
   actually gets from source systems into the warehouse, how you keep it
   trustworthy over time, and how the concepts you've learned map onto
   cloud warehouses, lakehouses, and Data Vault.

Every chapter has:

- **Concepts**, explained with the sample e-commerce schema this repo
  ships with.
- **In the infra**, pointing at the exact file/model that demonstrates
  the concept.
- **Exercises**, mostly SQL or dbt, that you run yourself.
- **Common mistakes**, the ones people actually make.
- **Further study**, named books/resources — look them up, no links are
  guessed here.

## Set up the environment now

From the repo root:

```bash
cp .env.example .env
make up          # starts Postgres + pgAdmin, seeds the source schema
make dbt-build    # dbt seed && dbt snapshot && dbt run && dbt test
```

Verify it worked:

```bash
make psql
```
```sql
select count(*) from source.orders;        -- 3000
select count(*) from marts.fact_orders;    -- 6000
\dt source.*
\dt marts.*
```

If both counts come back and `\dt` lists tables in both schemas, you're
ready for chapter 1.

## A note on the sample dataset

Every chapter uses the same small e-commerce business: `source.customers`,
`source.products`, `source.employees`, `source.orders`,
`source.order_items`, `source.payments`, and
`source.customer_address_history`. It's intentionally small (a few
thousand rows) so query results are easy to eyeball, and intentionally a
little messy (see chapter 9) so data-quality exercises have something real
to find. Skim `infra/postgres/init/01_schema_source.sql` now — you'll be
staring at it a lot over the next few chapters.
