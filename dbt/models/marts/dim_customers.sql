{#
    Type-2 SCD dimension. One row per customer per distinct version of their
    attributes, with an effective date range. `is_current` and `dbt_valid_to
    is null` are equivalent ways to find the current row — both are exposed
    because different query patterns favor one or the other.
#}

with snapshot as (
    select * from {{ ref('customers_snapshot') }}
),

region_map as (
    select * from {{ ref('region_country_map') }}
)

select
    md5(s.customer_id::text || '|' || s.dbt_valid_from::text) as customer_key,
    s.customer_id,
    s.first_name,
    s.last_name,
    s.first_name || ' ' || s.last_name as full_name,
    s.email,
    s.city,
    s.country,
    coalesce(r.region, 'Unknown') as region,
    s.segment,
    s.dbt_valid_from as valid_from,
    s.dbt_valid_to as valid_to,
    (s.dbt_valid_to is null) as is_current
from snapshot s
left join region_map r on r.country = s.country
