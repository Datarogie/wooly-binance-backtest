# Building the per-hour charts in Lightdash

The Lightdash metadata for the two strategy marts lands in Part 1 (see the
"Explore in Lightdash" section of the [README](../README.md)). With that in
place the two answer charts are a few clicks each. The charts themselves are a
documented manual step rather than committed artifacts, because a real Lightdash
chart is created in the running app's UI: the content-as-code format
(`lightdash download`) exports charts that already exist in an instance, it does
not author them from scratch. Standing up the app and driving its UI is not
something this repo automates, so the steps are written out below instead of
shipped as YAML that was never rendered.

The groundwork is validated: `make lightdash` compiles all five explores with
`SUCCESS=5 ERRORS=0`, so the dimensions and metrics named below are guaranteed
to be present once the project is deployed.

## Prerequisites

1. The dbt project builds (`make all`) and Postgres is up.
2. A Lightdash instance is running and this dbt project is deployed to it. The
   lightest path is the CLI against a local self-hosted app:

   ```bash
   npm install -g @lightdash/cli          # if not already installed
   lightdash login http://localhost:3000  # or your instance URL
   lightdash deploy --create              # first time; reuses profiles.yml for the warehouse
   ```

   `lightdash deploy` reads the warehouse connection from this project's
   `profiles.yml`, so the same env-var defaults that drive dbt drive Lightdash.

## Chart 1: total compounded return by hour (answers Q1)

1. In Lightdash, open **Explore > Tables** and pick
   **Fct strategy performance by hour**.
2. Under **Dimensions**, select **Hour of day (UTC)**.
3. Under **Metrics**, select **Total compounded return**.
4. Run the query. You get 24 rows, one per hour.
5. Open the **Chart** tab and choose **Bar chart**.
   - X axis: **Hour of day (UTC)**.
   - Y axis: **Total compounded return**.
6. Sort the X axis ascending by hour so the bars read 0 to 23 left to right.
7. The tallest bar is **hour 22** at roughly **+42.5%**: the Q1 answer. To make
   it pop, add a reference line at the max or recolour the hour-22 series.
8. **Save** the chart (name it "Total compounded return by hour") and add it to
   a new dashboard, "Per-hour strategy".

## Chart 2: maximum drawdown by hour (answers Q2)

1. Back in **Explore > Tables**, pick **Fct strategy drawdown by hour**.
2. Dimension: **Hour of day (UTC)**. Metric: **Maximum drawdown**.
3. Run the query (24 rows) and switch to a **Bar chart** with the same axes as
   above.
4. Maximum drawdown is negative, so the bars hang below zero. The bar closest to
   zero (the shallowest drawdown) is **hour 10** at roughly **-9.0%**: the Q2
   answer.
5. **Save** ("Maximum drawdown by hour") and add it to the same dashboard.

## Optional: equity-curve line chart

The per-hour marts are pre-aggregated, so they do not hold a daily equity curve.
A line chart of cumulative growth would explore
`int_bitcoin__strategy_equity_curve` (currently ephemeral). To chart it, give
that model a table or view materialization and a `date` dimension plus an equity
metric, then plot equity over `trade_date` filtered to one `hour_of_day`. This
is left out on purpose to keep the integration to the conformed marts only.

## Exporting the charts as code

Once the two charts exist in the instance, they can be committed as
content-as-code:

```bash
lightdash download   # writes lightdash/charts/*.yml and lightdash/dashboards/*.yml
```

Commit the downloaded YAML to version it. It is deliberately not committed here
because it must round-trip through a running instance to be valid, and this repo
does not stand one up.
