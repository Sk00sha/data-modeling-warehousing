{# Use the schema set in each model's config (staging/intermediate/marts)
   verbatim instead of dbt's default "<target_schema>_<custom_schema>"
   prefixing. Keeps the warehouse layout readable for a learning project. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
