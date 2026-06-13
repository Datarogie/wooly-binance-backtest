with source as (
    select * from {{ source('binance', 'bitcoin_prices') }}
),

deduplicated as (
    -- source ships exact duplicate rows (same second repeated); drop the copies.
    -- distinct keeps any second carrying genuinely different prints.
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
        open::numeric as open,
        high::numeric as high,
        low::numeric as low,
        close::numeric as close,
        volume::numeric as volume,
        number_of_trades

    from deduplicated
)

select * from final
