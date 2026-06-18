with source as (
    select * from {{ source('binance', 'bitcoin_prices') }}
),

deduplicated as (
    select distinct
        open_time,
        open,
        high,
        low,
        close,
        volume,
        number_of_trades

    from source
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['open_time']) }} as pk_bitcoin_price_key,
        open_time as event_at,
        open::numeric(18, 8) as open,
        high::numeric(18, 8) as high,
        low::numeric(18, 8) as low,
        close::numeric(18, 8) as close,
        volume::numeric(28, 8) as volume,
        number_of_trades

    from deduplicated
)

select * from final
