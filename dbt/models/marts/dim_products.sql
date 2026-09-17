{# Type-1 dimension: only the current attributes matter, no history kept. #}

select
    md5(product_id::text) as product_key,
    product_id,
    sku,
    product_name,
    category,
    subcategory,
    unit_cost,
    unit_price,
    unit_margin,
    is_active
from {{ ref('stg_products') }}
