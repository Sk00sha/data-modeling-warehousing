{#
    Singular (source-to-target reconciliation) test.

    For every non-cancelled order, the line items rolled up in fact_orders
    should sum to the amount captured in payments. This is the kind of
    test that catches silent join fan-out or a bad measure formula — the
    per-column tests in _marts__models.yml wouldn't catch it, because each
    row still looks individually valid.

    A non-empty result means a discrepancy: dbt fails the test.
#}

with fact_totals as (
    select
        f.order_id,
        sum(f.net_amount) as net_amount_total
    from {{ ref('fact_orders') }} f
    group by f.order_id
),

payment_totals as (
    select order_id, amount
    from {{ ref('stg_payments') }}
),

orders as (
    select order_id, order_status
    from {{ ref('stg_orders') }}
)

select
    o.order_id,
    ft.net_amount_total,
    pt.amount as amount_paid
from orders o
join fact_totals ft on ft.order_id = o.order_id
join payment_totals pt on pt.order_id = o.order_id
where o.order_status <> 'cancelled'
  and abs(ft.net_amount_total - pt.amount) > 0.01
