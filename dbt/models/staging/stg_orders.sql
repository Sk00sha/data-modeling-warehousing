with source as (
    select * from {{ source('ecommerce', 'orders') }}
)

select
    order_id,
    customer_id,
    employee_id,
    order_status,
    channel,
    order_date,
    ship_date,
    (ship_date - order_date) as days_to_ship,
    created_at,
    updated_at
from source
