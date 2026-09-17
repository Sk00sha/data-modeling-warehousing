with source as (
    select * from {{ source('ecommerce', 'customers') }}
)

select
    customer_id,
    first_name,
    last_name,
    first_name || ' ' || last_name as full_name,
    lower(email) as email,
    city,
    country,
    segment,
    created_at,
    updated_at
from source
