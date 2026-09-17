with source as (
    select * from {{ source('ecommerce', 'products') }}
)

select
    product_id,
    sku,
    product_name,
    category,
    coalesce(subcategory, 'Uncategorized') as subcategory,
    unit_cost,
    unit_price,
    round(unit_price - unit_cost, 2) as unit_margin,
    is_active,
    created_at,
    updated_at
from source
