select
    md5(employee_id::text) as employee_key,
    employee_id,
    full_name,
    role,
    region
from {{ ref('stg_employees') }}
