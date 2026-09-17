{#
    Type-2 slowly changing dimension, built with dbt's snapshot feature.

    Every time `dbt snapshot` runs, it compares the tracked columns against
    the latest snapshotted row per customer_id. If they differ, it closes
    out the old row (sets dbt_valid_to) and inserts a new one — giving you
    full history without hand-rolled SCD2 merge SQL. See curriculum
    chapter 07 (Slowly Changing Dimensions) for the manual-SQL version of
    this same idea.
#}
{% snapshot customers_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='customer_id',
        strategy='check',
        check_cols=['city', 'country', 'segment', 'email'],
    )
}}

select
    customer_id,
    first_name,
    last_name,
    email,
    city,
    country,
    segment
from {{ source('ecommerce', 'customers') }}

{% endsnapshot %}
