# Chapter 2 — Conceptual, Logical, and Physical Modeling

## Learning objectives

- Distinguish the three classic levels of data modeling and what belongs
  at each
- Choose between natural and surrogate keys, and explain the tradeoff
- Translate a conceptual model into a logical model into a physical
  DDL script

## The three levels

Most modeling literature (and most job postings that say "data modeler")
refer to three levels of abstraction. They're not three separate
deliverables you produce in sequence and throw away — they're three
*lenses* on the same design, each answering a different question.

| Level | Question it answers | Example |
|---|---|---|
| **Conceptual** | What are the business things and how do they relate? | "A Customer places Orders. An Order contains Products." |
| **Logical** | What are the exact attributes, types (in business terms), and keys — independent of any specific database engine? | "Order has order_id (identifier), order_date (date), status (one of a fixed set of values)" |
| **Physical** | How is this actually implemented in a specific engine, with real types, indexes, partitioning, constraints? | `order_date date not null`, `create index idx_orders_order_date on source.orders (order_date)` |

A conceptual model is deliberately vague about implementation — no data
types, no keys named `_id`, sometimes not even attributes, just entities
and relationships. It's a communication tool for non-technical
stakeholders: "does this match how the business actually thinks about
orders?" A logical model adds attributes, types, and keys but still avoids
engine-specific syntax — it should look almost the same whether the target
is Postgres, Snowflake, or SQL Server. The physical model is what you
actually run: `infra/postgres/init/01_schema_source.sql` is a physical
model, complete with Postgres-specific `serial`, `check` constraints, and
index definitions tuned for the query patterns we expect.

## Worked example: `Product`

**Conceptual:**
```
Product — something the business sells
```

**Logical:**
```
Product
  product_id      : identifier
  sku             : text, unique
  product_name    : text
  category        : text
  unit_cost       : decimal
  unit_price      : decimal
  is_active       : boolean
```

**Physical** (`infra/postgres/init/01_schema_source.sql`):
```sql
create table source.products (
    product_id      serial primary key,
    sku             text not null unique,
    product_name    text not null,
    category        text not null,
    subcategory     text,
    unit_cost       numeric(10, 2) not null check (unit_cost >= 0),
    unit_price      numeric(10, 2) not null check (unit_price >= 0),
    is_active       boolean not null default true,
    created_at      timestamp not null default now(),
    updated_at      timestamp not null default now()
);
```

Notice what got added going logical → physical: precision on the decimals
(`numeric(10, 2)`), `not null` decisions, `check` constraints enforcing
business rules (cost/price can't be negative), default values, and audit
columns (`created_at`/`updated_at`) that have nothing to do with the
business concept of a Product and everything to do with running a real
system.

## Natural keys vs. surrogate keys

This decision belongs at the logical/physical boundary and you'll make it
constantly, especially in chapter 5 onward.

- **Natural key**: an attribute (or combination) that already uniquely
  identifies a row *and has business meaning* — `sku`, `email`.
- **Surrogate key**: a system-generated identifier with no business
  meaning — `product_id serial`, a UUID, an auto-increment integer.

This project uses surrogate keys (`serial`) as primary keys everywhere in
`source.*`, but keeps the natural keys as unique constraints (`sku`,
`email`). That's the standard pattern, for good reasons:

- Natural keys can change (a SKU gets renumbered, an email gets
  corrected) — and a primary key that changes forces every foreign key
  referencing it to cascade-update, which is expensive and risky.
- Natural keys can be composite (multiple columns), which makes every
  foreign key wider and every join uglier.
- Surrogate keys are a fixed-width integer or UUID — fast to index, fast
  to join.

The tradeoff: a surrogate key alone tells you nothing by looking at it,
and if you're not careful you can insert duplicate "natural" rows (two
products with the same SKU but different `product_id`s) — which is
exactly why `sku unique` is still enforced even though it's not the
primary key.

You'll meet this decision again, with higher stakes, in chapter 5: every
dimension table in a warehouse gets its own **dimensional surrogate key**,
deliberately decoupled from the source system's key, for reasons that only
make sense once you understand Slowly Changing Dimensions (chapter 7).

## Exercise

1. Write the conceptual, logical, and physical model (in that order) for
   a `Payment` entity — before you look at `infra/postgres/init/01_schema_source.sql`. Then
   compare against `source.payments`. What did the real physical model
   add that you didn't think of at the logical level?
2. `source.customers.email` is `unique` but not the primary key. Explain,
   in terms of the tradeoffs above, why `customer_id` is the primary key
   instead of `email` — even though email is arguably the more natural
   real-world identifier for a person.
3. Pick any table in the schema and list every physical-level detail
   (types, constraints, indexes, defaults) that wouldn't appear in a
   logical model.

## Common mistakes

- **Jumping straight to physical.** Skipping conceptual/logical and
  writing `CREATE TABLE` directly from a user story usually means missing
  relationships that would have been obvious on a whiteboard.
- **Putting engine-specific types in a "logical" model.** If your logical
  model says `varchar(255)`, you've actually written a physical model —
  `varchar(255)` is a physical decision (why 255? why not 256, or `text`?).
- **Treating surrogate keys as a free lunch.** They solve the "keys
  shouldn't change" problem but introduce a new one: nothing stops you
  from inserting two rows that are "the same" by business meaning but
  have different surrogate keys, unless you separately enforce a unique
  constraint on the natural key.

## Further study

- *The Data Model Resource Book* series, Len Silverston — deep coverage
  of conceptual/logical patterns across industries.
- Postgres documentation on `numeric` vs `real`/`double precision` — worth
  reading once, to understand why money columns in this project use
  `numeric(10, 2)` and never a floating-point type.

Next: [Chapter 3 — Normalization and Relational Design](03-normalization-and-relational-design.md)
