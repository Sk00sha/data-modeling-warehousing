{# Custom generic (schema) test used in the data-quality chapter.
   Usage in a schema.yml:
     - not_negative
   Fails for any row where the column value is < 0. #}
{% test not_negative(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} < 0

{% endtest %}
