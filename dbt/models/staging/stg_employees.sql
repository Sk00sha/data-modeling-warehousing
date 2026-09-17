with source as (
    select * from {{ source('ecommerce', 'employees') }}
)

select
    employee_id,
    first_name,
    last_name,
    first_name || ' ' || last_name as full_name,
    role,
    region
from source
