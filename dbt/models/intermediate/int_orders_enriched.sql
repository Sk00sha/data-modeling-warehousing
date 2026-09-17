{#
    Intermediate layer: one row per order, enriched with the employee who
    owns it and the total paid. Nothing here is "dimensional" yet — this is
    the ELT equivalent of a reusable CTE, kept as its own model so both
    fact_orders and any future order-level report can build on it without
    repeating the join/aggregation logic (see curriculum chapter 08).
#}

with orders as (
    select * from {{ ref('stg_orders') }}
),

employees as (
    select * from {{ ref('stg_employees') }}
),

payments as (
    select
        order_id,
        sum(amount) as amount_paid,
        max(paid_at) as last_paid_at
    from {{ ref('stg_payments') }}
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    o.employee_id,
    e.region as employee_region,
    o.order_status,
    o.channel,
    o.order_date,
    o.ship_date,
    o.days_to_ship,
    coalesce(p.amount_paid, 0) as amount_paid,
    p.last_paid_at
from orders o
left join employees e on e.employee_id = o.employee_id
left join payments p on p.order_id = o.order_id
