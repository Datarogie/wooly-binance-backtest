{#
  Route models into clean schemas (staging / intermediate / marts) instead of
  dbt's default of prefixing the custom schema onto the target schema. When a
  model sets `+schema`, that name is used verbatim; otherwise the target's
  default schema applies. Trusting the custom name keeps the warehouse readable.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
