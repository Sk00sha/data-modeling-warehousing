# Chapter 5 — Dimensional Modeling: Star and Snowflake Schemas

## Learning objectives

- Define fact and dimension, and tell them apart on sight
- Explain the four-step Kimball design process and apply it
- Draw and build a star schema; understand when a snowflake schema is used instead
- Understand conformed dimensions and the bus matrix

## Facts and dimensions

A **fact** is a measurement or event: something that *happened*, usually
numeric and additive — an order line being sold, a page being viewed, a
payment being made. A **dimension** is context that describes the fact:
*who*, *what*, *where*, *when*. Facts are typically many rows and narrow;
dimensions are typically fewer rows and wide (lots of descriptive
columns).

In this project: `marts.fact_orders` is the fact table (one row per order
line item — a sale event). `marts.dim_customers`, `marts.dim_products`,
`marts.dim_employees`, and `marts.dim_date` are the dimensions describing
*who* bought, *what* was bought, *who* sold it, and *when*.

```sql
select * from marts.fact_orders limit 5;
select * from marts.dim_products limit 5;
```

Look at the shape difference: the fact table is almost all foreign keys
and numbers; the dimension tables are almost all descriptive text.

## The star schema

A star schema is one fact table at the center, directly joined to a set
of dimension tables — no dimension joins to another dimension. Drawn out,
the fact table is the hub and dimensions are spokes, hence "star":

```
              dim_date
                 |
dim_customers -- fact_orders -- dim_products
                 |
             dim_employees
```

Query it:

```sql
select
    d.year,
    d.month_name,
    p.category,
    sum(f.net_amount) as revenue
from marts.fact_orders f
join marts.dim_date d on d.date_key = f.order_date_key
join marts.dim_products p on p.product_key = f.product_key
group by 1, 2, 3
order by 1, 2;
```

One join per dimension you need, no more — that's the entire performance
argument for denormalizing this way. Compare the same query against fully
normalized `source.*` and count the joins.

## The Kimball four-step design process

Every dimensional model — this course's `fact_orders` included — comes
from answering four questions in this order:

1. **Select the business process.** Not "customers" or "products" — a
   *process*, something that happens: placing an order. (Not "build a
   customer dimension" — that's a step inside modeling the order
   process.)
2. **Declare the grain.** The single, precise sentence describing what one
   row in the fact table represents. For `fact_orders`: *"one row per
   order line item."* Get this wrong or vague, and every downstream
   decision about what dimensions/measures belong gets wrong too — this
   is the single most important sentence in dimensional modeling, covered
   in full in chapter 6.
3. **Identify the dimensions.** Given the grain, what context does each
   fact row need? At the order-line grain: which customer, which product,
   which employee, which date, which order (channel, status).
4. **Identify the facts (measures).** What's actually being measured at
   this grain? `quantity`, `net_amount`, `cost_amount`, `margin_amount` —
   see chapter 6 for which of these are safely additive.

Do this exercise from scratch, on paper, for a hypothetical "customer
support ticket" business process before moving on — it's the only way this
sticks.

## Snowflake schema

A snowflake schema normalizes a dimension into multiple related tables —
e.g., splitting `dim_products` into `dim_products` (name, sku, price) and
a separate `dim_categories` (category, department) that `dim_products`
foreign-keys to.

```
dim_categories -- dim_products -- fact_orders
```

This project deliberately uses a **star**, not a snowflake:
`marts.dim_products.category` and `.subcategory` are flat columns, not
broken into their own table. Why star over snowflake, in general:

- **Fewer joins** — the entire point of denormalizing in the first place.
  Snowflaking partially un-does that benefit for the dimension you
  snowflake.
- **Simpler for BI tools and analysts** — a flat dimension table is
  trivially easy to filter/group by; a snowflaked one requires knowing
  which sub-table to join.
- **Storage savings from snowflaking are usually irrelevant** at
  dimension-table scale (thousands to low millions of rows) — the
  normalization benefit that mattered for large fact-scale data doesn't
  apply to comparatively tiny dimension tables.

When snowflaking *is* worth it: a dimension attribute that's shared,
independently maintained, and large/complex enough to be its own
first-class dimension — e.g., a `dim_geography` (country → region →
territory hierarchy) that's reused by multiple fact tables and maintained
by a separate reference-data process. The test: would this sub-table earn
its own dimension if it stood alone? If yes, consider snowflaking (or
better, promoting it to its own conformed dimension — see below). If it's
just "fewer repeated string values," star it and move on; storage is
cheap, joins are not free.

## Conformed dimensions and the bus matrix

As you model a second business process (say, `fact_returns`), you'll need
a customer dimension again. A **conformed dimension** is the same
dimension table (or at least the same keys and definitions) reused across
multiple fact tables — so "customer" means exactly one thing across every
report in the company, and you can join `fact_orders` and `fact_returns`
to the *same* `dim_customers` and compare them meaningfully.

The **bus matrix** is Kimball's planning tool for this: business processes
as rows, conformed dimensions as columns, checkmarks where they intersect.

| Business Process | dim_customers | dim_products | dim_employees | dim_date |
|---|---|---|---|---|
| Orders (this project) | ✓ | ✓ | ✓ | ✓ |
| Returns (hypothetical) | ✓ | ✓ | | ✓ |
| Support tickets (hypothetical) | ✓ | | ✓ | ✓ |

This is the artifact that lets an organization build its warehouse
incrementally (one fact table at a time, Kimball's bottom-up approach from
chapter 4) while still ending up with something coherent instead of a pile
of incompatible one-off marts.

## Exercise

1. Run `make dbt-docs` and open the lineage graph. Confirm visually that
   `fact_orders` is the only model joined to by multiple dimensions, and
   that no dimension joins to another dimension (verifying this is a star,
   not a snowflake).
2. Sketch a bus matrix row for a hypothetical `fact_employee_reviews`
   process, reusing as many existing dimensions from this project as
   plausible.
3. `marts.dim_products.category`/`subcategory` are flat strings. Redesign
   this as a snowflaked `dim_categories` table (write the `CREATE TABLE`)
   and then write the query from the star-schema section above using the
   snowflaked version. Count the extra join. Decide, and justify in one
   sentence, whether you'd actually ship this change.

## Common mistakes

- **Starting with dimensions instead of the business process.** "Let's
  build a customer dimension" isn't a starting point — it's a fact table's
  dependency, discovered in step 3 of the four-step process, not step 1.
- **Un-conformed dimensions.** Two teams building their own `dim_customer`
  with slightly different definitions of "active customer" is how
  warehouses end up with reports that disagree with each other.
- **Snowflaking reflexively** out of normalization habit from chapter 3 —
  dimension tables are a deliberately different design regime; don't
  import OLTP instincts wholesale.

## Further study

- *The Data Warehouse Toolkit* (3rd ed.), chapters 1–3 — this chapter is
  a compressed version of exactly that material.
- Kimball Group's published "bus matrix" articles/whitepapers (search
  "Kimball dimensional bus matrix") for real-world examples across
  industries.

Next: [Chapter 6 — Fact Table Design: Grain, Types, and Additivity](06-fact-table-design.md)
