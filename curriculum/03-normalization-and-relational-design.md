# Chapter 3 — Normalization and Relational Design

## Learning objectives

- Explain functional dependency in your own words
- Recognize violations of 1NF, 2NF, and 3NF, and fix them
- Explain *why* OLTP systems normalize and what it costs
- Know when denormalization is the right call — setting up chapter 4

## Functional dependency, informally

A column `B` is *functionally dependent* on column `A` if, for any given
value of `A`, there's exactly one possible value of `B`. Write it `A → B`.

In `source.orders`: `order_id → order_date` (each order has exactly one
order date). In `source.order_items`: `order_item_id → quantity`, but also
notice `product_id → unit_price`... wait, does it? Look at the actual
table:

```sql
create table source.order_items (
    order_item_id   serial primary key,
    order_id        integer not null references source.orders (order_id),
    product_id      integer not null references source.products (product_id),
    quantity        integer not null,
    unit_price      numeric(10, 2) not null,
    discount_pct    numeric(5, 2) not null default 0
);
```

`unit_price` is stored *on the order line*, not just looked up from
`source.products.unit_price`. That's deliberate, not an oversight — it's
the correct design, and explaining why is most of this chapter.

## 1NF — atomic values, no repeating groups

A table is in First Normal Form if every column holds a single, atomic
value (no comma-separated lists, no arrays-as-strings) and there are no
repeating groups of columns (`product_1_id, product_2_id, product_3_id`).

Every table in `01_schema_source.sql` is already in 1NF. A 1NF violation
would look like a hypothetical `orders.product_ids text` column holding
`'12,45,91'` — which is exactly the shape of problem `source.order_items`
exists to solve (chapter 1's M:N resolution table).

## 2NF — no partial dependency on a composite key

2NF only matters when a table has a **composite primary key**. A partial
dependency is when a non-key column depends on only *part* of the
composite key, not the whole thing.

None of this project's tables have composite primary keys (everything
uses a surrogate `serial`), so there's nothing to violate — but it's worth
seeing the classic failure mode. Imagine `order_items` had been designed
with `(order_id, product_id)` as a composite primary key, and someone
added a `product_name` column to it "for convenience":

```
order_items (order_id, product_id, quantity, product_name)
                └──────── PK ────────┘
```

`product_name` depends only on `product_id` (part of the key), not on the
combination of `order_id` and `product_id`. That's a 2NF violation:
`product_name` belongs in `products`, not here. (Note: `unit_price` in
the *real* schema is not a 2NF violation, even though it "duplicates" a
product attribute — see below.)

## 3NF — no transitive dependency

A table is in 3NF if every non-key column depends on the key, the whole
key, and nothing but the key. A transitive dependency is `A → B → C` where
`C` is stored redundantly instead of being derived through `B`.

Classic example: if `source.orders` stored `customer_city` directly
(instead of just `customer_id`), that would be a transitive dependency —
`order_id → customer_id → customer_city`. `customer_city` should live in
`customers`, reachable via a join, not duplicated on every order.

## So why does `order_items.unit_price` "duplicate" `products.unit_price`?

This is the single most important distinction in this chapter: **not
every case of "the same value appears in two tables" is a normalization
violation.** `order_items.unit_price` is the price *at the moment this
order was placed*. `products.unit_price` is the *current* price. These
are different facts that happen to often hold the same value — they are
not functionally dependent on each other. If they were the same fact,
raising a product's price next month would silently rewrite the amount
every historical order was billed for, which is wrong.

This is a preview of a theme that runs through the rest of this course:
**a value changing over time is a strong signal that you need to capture
history, not just current state** — the entire subject of chapter 7 (Slowly
Changing Dimensions).

## Why OLTP systems normalize

`source.*` in this project is normalized (3NF, roughly) because it's
modeling a transactional system: many small, concurrent writes (place an
order, update a customer's address), where the priorities are:

- **No update anomalies** — update a customer's city once, in one place,
  and every order automatically reflects it (through the join) without
  needing 3,000 row updates.
- **No insert anomalies** — you can add a new product without needing an
  order to hang it off of.
- **No delete anomalies** — deleting an order shouldn't accidentally
  delete a customer.
- **Compact storage, less redundancy.**

The cost: reading a complete picture of "this order, this customer, these
products" requires joining 4–5 tables. For OLTP — where a single request
usually touches one or two entities — that's a fine trade. For analytics
— where a single query might scan and aggregate millions of transactions
— repeatedly re-joining 5 normalized tables gets expensive, and that cost
is exactly what dimensional modeling (chapter 5) exists to eliminate.
Normalize for write-heavy, denormalize (deliberately, selectively) for
read-heavy — that's the thesis of the next four chapters.

## Exercise

1. Run this query and identify which normal form would be violated if the
   result were materialized as a permanent table instead of computed on
   the fly:
   ```sql
   select o.order_id, o.order_date, c.full_name, c.city
   from source.orders o
   join source.customers c on c.customer_id = o.customer_id;
   ```
   (Answer: none, as a *query result* — normalization rules apply to
   stored tables, not query output. This is the exact distinction chapter
   4 builds on.)
2. `source.customers` has both `city` and `country`. Is `country`
   functionally dependent on `city`? Is this a normalization concern? (Hint:
   think about whether "Springfield" uniquely determines a country.)
3. Find the one column in the schema that's a deliberate, justified
   exception to strict normalization (hint: it's covered above). Explain
   in one paragraph why duplicating it is correct rather than a bug.

## Common mistakes

- **Normalizing analytical/reporting tables the same way as transactional
  ones.** 3NF is a means to an end (safe, efficient writes), not a moral
  rule that applies everywhere.
- **Confusing "duplicated value" with "normalization violation."**
  Functional dependency is about *meaning*, not surface-level value
  equality. Two columns can hold the same value today and still be
  correctly independent facts.
- **Over-normalizing early.** Splitting `subcategory` into its own table
  with a foreign key, when it's just a free-text label with no other
  attributes, adds a join for no benefit. Normalize where it prevents real
  anomalies, not reflexively.

## Further study

- *Database System Concepts*, Silberschatz/Korth/Sudarshan — the standard
  academic reference for formal normal forms (up through BCNF and beyond,
  if you want the full rigor this chapter simplified).
- C.J. Date's writing on relational theory, if you want the original
  rigor behind functional dependency.

Next: [Chapter 4 — Data Warehouse Architecture & Core Concepts](04-dw-architecture-and-concepts.md)
