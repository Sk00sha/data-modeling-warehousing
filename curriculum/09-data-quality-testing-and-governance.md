# Chapter 9 — Data Quality, Testing, and Lifecycle Governance

## Learning objectives

- Name the standard data quality dimensions and apply them to real columns
- Write and interpret dbt schema tests, custom generic tests, and singular tests
- Explain why row-level tests miss certain classes of bugs, and what catches those instead
- Describe a basic data lifecycle/governance model: ownership, lineage, documentation, PII handling

## Why "it ran without an error" isn't enough

A pipeline can execute successfully — no exceptions, every model built —
and still be **wrong**: a join that silently drops rows, a measure that's
double-counted, a source system change that renames a column to `NULL`
everywhere downstream. Chapter 8 got data flowing; this chapter is about
proving it's *correct*, continuously, not just on the day you wrote the
model.

This project has a real, running example: 60 dbt tests, all passing.
Run them:

```bash
make dbt-test
```

Every one of those tests exists because some specific way this data could
be wrong would otherwise go unnoticed. Let's go through the categories.

## The standard data quality dimensions

- **Completeness** — is required data actually present? (`not_null` tests)
- **Uniqueness** — does a key actually identify one row? (`unique` tests)
- **Validity** — does a value fall within an allowed domain?
  (`accepted_values`, `check` constraints, the custom `not_negative` test)
- **Consistency** — do related values across tables agree? (`relationships`
  tests, and the reconciliation test below)
- **Accuracy** — does the data reflect reality? (usually the hardest to
  test automatically — often requires domain-specific reconciliation)
- **Timeliness** — is the data fresh enough to be useful? (not directly
  tested in this project — see "freshness" below)

## Schema tests (generic tests)

Defined declaratively in `.yml` files next to the models. Look at
`dbt/models/staging/_stg__models.yml`:

```yaml
- name: stg_orders
  columns:
    - name: order_id
      data_tests: [unique, not_null]
    - name: customer_id
      data_tests:
        - not_null
        - relationships:
            to: ref('stg_customers')
            field: customer_id
    - name: order_status
      data_tests:
        - accepted_values:
            values: ['pending', 'shipped', 'delivered', 'cancelled', 'returned']
```

Four built-in tests cover most of what you need: `unique`, `not_null`,
`accepted_values` (validity — value must be in an allowed set),
`relationships` (referential integrity — every `customer_id` in `orders`
must exist in `customers`; this is enforced by a foreign key in
`source.*`, but staging/marts views/tables have no such constraint, so the
test re-asserts it at every layer).

## Custom generic tests

Built-in tests don't cover everything. `dbt/macros/not_negative.sql`
defines a reusable custom test:

```sql
{% test not_negative(model, column_name) %}
select * from {{ model }} where {{ column_name }} < 0
{% endtest %}
```

Used exactly like a built-in test — `tests: [not_negative]` — on
`unit_cost`, `unit_price`, `quantity`, `net_amount` throughout the schema
files. A generic test is just a parameterized query that should return
zero rows; if it returns any rows, the test fails and dbt shows you
exactly which rows violated it. This is the pattern to reach for whenever
a built-in test doesn't express the rule you need.

## Singular tests

Some quality problems aren't about one column in isolation — they're
about whether the *whole pipeline*, end to end, agrees with itself.
`dbt/tests/assert_orders_reconcile_with_payments.sql` is a **singular
test** (a one-off SQL file, not a reusable macro) that checks
source-to-target reconciliation:

```sql
-- for every non-cancelled order, do fact_orders' line items
-- sum to what payments actually captured?
select o.order_id, ft.net_amount_total, pt.amount as amount_paid
from ...
where abs(ft.net_amount_total - pt.amount) > 0.01
```

This is the test category that catches the bugs chapter 6 and 8 warned
about — **join fan-out** (a bad join multiplying rows would inflate
`net_amount_total` without breaking any single column's `not_null` or
`unique` test) and **bad measure formulas** — precisely because every
individual row can look perfectly valid (non-null, in range, correctly
typed) while the aggregate is still wrong. Row-level tests and
whole-pipeline reconciliation tests catch genuinely different bug classes;
a mature test suite needs both.

## Source freshness (mentioned, not implemented here)

dbt also supports `freshness` checks on sources — asserting that
`source.orders`, for example, has been updated within some expected
window (`warn_after`/`error_after`), catching a stalled upstream pipeline
before anyone notices stale dashboards. Not configured in this project
(the seed data is static), but in a production setup with a live source
system, this is the standard way to test the **timeliness** dimension.

## Lifecycle: raw → tested → promoted

Put the layers from chapter 4 and 8 together with this chapter's testing,
and you get the actual lifecycle a piece of data goes through in this
project:

```
source (raw, untested)
   ↓
staging (tested: not_null, unique, accepted_values on natural keys)
   ↓
intermediate (implicitly covered — bugs here surface as marts-layer test failures)
   ↓
marts (tested: relationships across the whole star, reconciliation, business-rule validity)
```

Data isn't "trusted" the moment it lands — it earns that status by
passing the tests at each layer. `dbt build` (as opposed to `dbt run`)
runs models *and* tests interleaved in dependency order, and — critically
— **stops downstream models from building on top of a model whose tests
just failed**. That's the mechanical enforcement of "don't promote bad
data forward."

```bash
docker compose run --rm dbt build
```

## Documentation and lineage as part of quality

A model nobody can interpret is a quality risk even if every test passes
— the next person (including future you) will misuse a column whose
meaning isn't documented. Every model and most columns in this project's
`.yml` files carry a `description`. Generate the docs site:

```bash
make dbt-docs
```

Open http://localhost:8080. Two things matter here beyond browsing
column descriptions: the **lineage graph** (exactly reproduces the
architecture diagram from chapter 4, generated from the real dependency
graph rather than hand-drawn and liable to drift out of date), and the
fact that descriptions live in version control next to the models they
describe — so documentation changes go through the same review process
as code changes, instead of living in a separate wiki that quietly goes
stale.

## Governance, briefly

Full data governance is a large topic; three practices worth knowing even
at small scale:

- **Ownership** — every table/model should have a clear owner (a team or
  person), documented, so "who do I ask about this column" has an answer.
- **PII handling** — `source.customers.email` is personal data. In a real
  system, columns like this typically get explicitly tagged/classified,
  access-restricted, and sometimes excluded or hashed in downstream marts
  that don't need row-level identity (e.g., an aggregate "revenue by
  region" report has no reason to expose email addresses at all).
- **Data contracts** — an explicit, enforced agreement about a model's
  schema (column names, types, nullability) that upstream producers agree
  not to break without coordination. dbt supports this via model-level
  `contract: {enforced: true}` config, which fails the build if the
  compiled column list/types don't match what's declared — turning "the
  source team silently renamed a column" from a downstream mystery into a
  loud, immediate build failure.

## Exercise

1. `source.employees.region` has no `check` constraint restricting it to
   `EMEA`/`AMER`/`APAC`/`LATAM` (unlike `orders.order_status` or
   `customers.segment`, which are constrained at the database level).
   Add an `accepted_values` test for it in a schema file, run `dbt test`
   to confirm it passes against the seed data, then insert a row via
   `psql` with `region = 'nowhere'` directly into `source.employees` and
   re-run `dbt test`. Confirm it now fails, and read the failure output —
   note that the *database* accepted this row without complaint (no
   constraint stopped it); only the warehouse-layer test caught it. This
   is exactly why testing at the warehouse layer matters even when a
   source system has some constraints of its own — you can't always rely
   on every upstream source being as strict as this project's.
2. Now break something row-level tests genuinely can't see: temporarily
   edit `dbt/models/marts/fact_orders.sql` so `net_amount` is computed as
   `oi.quantity * oi.unit_price` (dropping the discount) instead of using
   `oi.net_amount`. Run `dbt build`. Every column is still non-null,
   positive, and uniquely keyed — `not_null`/`unique`/`not_negative` all
   still pass. Which test actually fails, and why is it the *only* one
   that can catch this class of bug? (Undo the change afterward.)
3. Write one new singular test for this project that checks something not
   already covered — e.g., that no `dim_customers` row has overlapping
   `[valid_from, valid_to)` ranges for the same `customer_id` (a
   correctness invariant of SCD2 history from chapter 7).

## Common mistakes

- **Testing only for nulls and uniqueness.** Covers completeness and part
  of uniqueness, misses validity, consistency, and whole-pipeline
  correctness almost entirely.
- **Treating "the pipeline ran" as "the data is correct."** They're
  unrelated claims — a pipeline with zero tests can run green forever
  while being silently wrong.
- **Writing tests but never looking at them again.** A test suite decays
  if failures get silenced/ignored rather than investigated — a passing
  test suite is only meaningful if failures are actually acted on.

## Further study

- dbt Labs documentation on tests (generic, singular, source freshness)
  and model contracts.
- *Data Quality Fundamentals*, Barr Moses, Lior Gavish, Molly Vorwerck —
  covers observability and the broader "data downtime" framing this
  chapter's lifecycle section draws from.

Next: [Chapter 10 — Modern Architectures and Capstone](10-modern-architectures-and-capstone.md)
