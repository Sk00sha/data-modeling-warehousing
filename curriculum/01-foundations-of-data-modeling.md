# Chapter 1 — Foundations of Data Modeling

## Learning objectives

- Define what a data model is and why it exists as a discipline separate from "writing SQL"
- Identify entities, attributes, and relationships in a real schema
- Read and draw a basic entity-relationship (ER) diagram
- Understand cardinality (1:1, 1:N, M:N) and how it's implemented with keys

## Why model at all?

A data model is a deliberate, explicit description of what things exist in
a domain, what they're made of, and how they relate — *before* you write a
single `CREATE TABLE`. Skip this step and you get a schema that mirrors
whatever the first feature happened to need, with new columns and tables
bolted on under deadline pressure. Six months later nobody can answer "what
does a row in this table actually represent?" without reading application
code.

Modeling front-loads that thinking. It's cheaper to redraw a box on a
diagram than to migrate a production table.

## Entities, attributes, relationships

Look at `source.orders` in this project's schema:

```sql
create table source.orders (
    order_id        serial primary key,
    customer_id     integer not null references source.customers (customer_id),
    employee_id     integer references source.employees (employee_id),
    order_status    text not null check (...),
    order_date      date not null,
    ...
);
```

- **Entity**: a thing worth tracking independently — `Order`, `Customer`,
  `Product`. Each becomes (usually) a table.
- **Attribute**: a property of an entity — `order_status`, `order_date`.
  Becomes a column.
- **Relationship**: how entities connect — an Order *belongs to* a
  Customer, an Order *is handled by* an Employee. Implemented with a
  foreign key.

Not every noun is an entity. `order_status` is an attribute of Order, not
its own entity — it doesn't have its own independent existence or
attributes of its own. (Contrast with `Product`: it has its own attributes
— `sku`, `unit_cost` — and a lifecycle independent of any one order. That
independence is the test.)

## Cardinality

Three shapes cover almost everything:

- **One-to-many (1:N)**: one `Customer` places many `Orders`. Implemented
  by putting the foreign key on the "many" side — `orders.customer_id`.
  This is the overwhelmingly common case.
- **Many-to-many (M:N)**: an `Order` contains many `Products`, and a
  `Product` appears on many `Orders`. Implemented with an **associative
  (junction/bridge) table** — that's exactly what `source.order_items` is:
  it resolves the M:N between orders and products, and typically carries
  attributes that belong to the *relationship itself* (`quantity`,
  `unit_price`, `discount_pct` — these describe "this product on this
  order," not the product or the order alone).
- **One-to-one (1:1)**: rare in practice — usually either a modeling
  smell (should just be one table) or a deliberate split (e.g. a
  `customer_secure_details` table with restricted access, separate from
  `customers`).

## Reading an ER diagram

Crow's-foot notation is the de facto standard. For a 1:N relationship
between `customers` and `orders`:

```
customers ||--o{ orders : places
```

- `||` on the `customers` side: exactly one customer per order (mandatory,
  one).
- `o{` on the `orders` side: zero-or-many orders per customer (optional,
  many — a customer can exist with zero orders).

For the M:N resolved through `order_items`:

```
orders    ||--o{ order_items : contains
products  ||--o{ order_items : "appears in"
```

You don't need special software for this early on — a whiteboard photo or
an ASCII sketch works. The value is in the thinking, not the tool. (When
you do want a tool: dbdiagram.io, drawSQL, or even Mermaid `erDiagram`
blocks in a markdown file all work fine.)

## Exercise

1. In `infra/postgres/init/01_schema_source.sql`, find every foreign key
   relationship and, on paper or in a `.md` file, list each as
   `EntityA ||--o{ EntityB : verb-phrase`.
2. `source.payments` references `source.orders`. Is this 1:1 or 1:N in the
   current schema? Check the seed script (`02_seed_source_data.sql`) — how
   many payments get inserted per order? Would a real payment system ever
   need this to be 1:N (hint: partial payments, refunds)?
3. Identify one attribute in the schema that you think is misplaced — that
   is, it describes something other than the table it lives in. Justify
   your answer in one sentence.

## Common mistakes

- **Treating every noun as a table.** If it has no independent identity,
  lifecycle, or attributes of its own, it's probably an attribute or an
  enum, not an entity.
- **Confusing a relationship's attributes with an entity's attributes.**
  `discount_pct` in `order_items` is about the order-product pairing, not
  a property of `Product` (a product doesn't have "a discount," an order
  line does).
- **Skipping cardinality.** "Customers have orders" isn't a complete
  relationship until you've said whether it's optional, whether it's
  many, and on which side.

## Further study

- *Database Design for Mere Mortals*, Michael J. Hernandez — the classic
  gentle introduction to exactly this chapter's content, at much greater
  length.
- ISO/IEC/IEEE entity-relationship modeling notation references, if you
  want the formal notation history (Chen notation vs. crow's-foot).

Next: [Chapter 2 — Conceptual, Logical, and Physical Modeling](02-conceptual-logical-physical-modeling.md)
