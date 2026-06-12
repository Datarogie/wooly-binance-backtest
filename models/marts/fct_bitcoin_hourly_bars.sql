{{ config(materialized='view') }}

select * from {{ ref('int_bitcoin__hourly_bars') }}
