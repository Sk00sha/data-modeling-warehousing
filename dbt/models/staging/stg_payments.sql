with source as (
    select * from {{ source('ecommerce', 'payments') }}
)

select
    payment_id,
    order_id,
    payment_method,
    amount,
    paid_at
from source
