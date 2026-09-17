{#
    Transaction fact table. Grain: one row per order line item
    (order_item_id) — see curriculum chapter 06 for why grain has to be
    declared explicitly before a single column is added.

    Degenerate dimensions (order_id, order_status, channel) are kept on the
    fact itself rather than in a dimension table, since they carry no
    further attributes of their own.

    dim_customers is a type-2 dimension, so the join to it is effective-
    dated: an order picks up whichever customer version was current on its
    order_date, not necessarily the latest one. Orders older than the
    earliest snapshotted version (e.g. anything before the first
    `dbt snapshot` run) fall back to that earliest known version, since no
    history exists before that point.
#}

with order_items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select * from {{ ref('int_orders_enriched') }}
),

products as (
    select * from {{ ref('dim_products') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

employees as (
    select * from {{ ref('dim_employees') }}
)

select
    oi.order_item_id,
    oi.order_id,
    o.order_status,
    o.channel,
    to_char(o.order_date, 'YYYYMMDD')::int as order_date_key,
    c.customer_key,
    p.product_key,
    e.employee_key,
    oi.quantity,
    oi.unit_price,
    oi.discount_pct,
    oi.net_amount,
    round(oi.quantity * p.unit_cost, 2) as cost_amount,
    round(oi.net_amount - (oi.quantity * p.unit_cost), 2) as margin_amount,
    o.days_to_ship,
    o.amount_paid
from order_items oi
inner join orders o on o.order_id = oi.order_id
left join products p on p.product_id = oi.product_id
left join employees e on e.employee_id = o.employee_id
left join lateral (
    select cust.*
    from customers cust
    where cust.customer_id = o.customer_id
    order by
        case
            when o.order_date >= cust.valid_from::date
                and (cust.valid_to is null or o.order_date < cust.valid_to::date)
            then 0
            else 1
        end,
        cust.valid_from
    limit 1
) c on true
