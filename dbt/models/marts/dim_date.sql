{#
    Classic date dimension, built with a recursive date spine rather than a
    package dependency so this project runs with zero external dbt
    packages. Range: vars.date_spine_start through 90 days past today,
    comfortably covering the seeded order_date range.
#}

with recursive spine as (
    select '{{ var("date_spine_start") }}'::date as date_day
    union all
    select date_day + 1
    from spine
    where date_day + 1 <= current_date + interval '90 days'
)

select
    date_day::date as date_day,
    to_char(date_day, 'YYYYMMDD')::int as date_key,
    extract(year from date_day)::int as year,
    extract(quarter from date_day)::int as quarter,
    extract(month from date_day)::int as month,
    trim(to_char(date_day, 'Month')) as month_name,
    extract(week from date_day)::int as iso_week,
    extract(isodow from date_day)::int as day_of_week,
    trim(to_char(date_day, 'Day')) as day_name,
    (extract(isodow from date_day) in (6, 7)) as is_weekend
from spine
