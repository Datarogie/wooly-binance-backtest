# SQL style guide

Follows the dbt Labs SQL style guide, enforced by sqlfluff (postgres dialect,
dbt templater; see `.sqlfluff`). Run `make lint` to check and `make format` to
auto-fix.

## Formatting

- All lowercase: keywords, functions, and identifiers.
- Four-space indentation, no tabs.
- Trailing commas, leading keywords.
- Lines wrap at 120 characters.
- Explicit column aliases; explicit `asc` / `desc` on every `order by` term.
- Explicit `group by` / `order by` columns, not positional numbers.
- CTEs: no blank line after `(` or before `)`. Add a blank line before `from`
  when the `select` lists multiple columns; omit it for bare `select * from ref(...)` CTEs.

## Model structure

- Every model opens with one or more import CTEs:
  `with source as (select * from {{ ref_or_source }})`. Import CTEs do no work
  beyond optional filtering.
- Every model ends with a `final` CTE that lists all columns explicitly, then
  `select * from final`.
- All columns are explicitly aliased whenever a join is present.
- Derived columns are computed once, as far upstream as their inputs allow, and
  reused downstream rather than recomputed.
- References are always `{{ ref() }}` / `{{ source() }}`; never a hardcoded
  schema or table name.

## Layering

Each layer reads only from the layer below it, never sideways from a peer's
output or down from a layer above.

- **Sources / landing.** Staging reads from `{{ source() }}`, or from a thin
  landing model if raw cleansing is unavoidable. Nothing but staging touches raw.
- **Staging** (`stg_`): one model per source object. Aliasing, casting, and at
  most light filtering (for example dropping corrupt or deleted rows). No
  deduping, no grain changes, no derived calendar fields, no business logic, and
  no unit tests. Kept as close to the source as possible.
- **Intermediate** (`int_`): reads staging or other intermediate models only,
  never a mart. Deduping, grain changes, derivations, and business logic live
  here. If an intermediate needs something from a mart, shift that logic left
  into an intermediate instead.
- **Marts** (`fct_` / `dim_`): read staging, intermediate, or other marts.
  Grain is established here; BI tools read directly from marts.
- **BI / analytics** (optional): if added, wide self-serve models read from marts
  only.
- Final answers live in `analyses/`, an ad-hoc query over the marts, never a core
  model.

## Naming

- Spell names out; no acronyms in the descriptive part of a model or column
  name. The dbt layer prefixes `stg_` / `int_` / `fct_` / `dim_` are kept as
  convention. In prose, spell a term out on first use with the acronym in
  brackets, e.g. "open, high, low, close, and volume (OHLCV)", then prefer the
  spelled-out form.
- The word "tick" is banned as a model or column name: it is ambiguous between a
  trade and a second bar. Use "second bar", "trade", or "coverage"
  (`observed_seconds`) as appropriate. See the glossary for the fixed
  vocabulary. The OHLCV column names `open` / `high` / `low` / `close` are the
  one allowed exception to the no-keyword-identifier rule, since they are the
  canonical names and non-reserved in Postgres.

## Documentation

- Explanation lives in `schema.yml` `description` fields at the model and column
  level, not in inline SQL comments. Every model and every column has a
  description.
- Well-written model SQL is self-documenting and should not need inline comments.
  Put any rationale in the model or column description instead.

## Testing

- A primary-key test (`unique` + `not_null`) on every model that establishes a
  grain (the marts and the hourly-bars table). Staging does not enforce a grain,
  so it carries `not_null` checks but no uniqueness. Ephemeral models carry their
  contracts one layer down, on the tables that read them, since generic tests
  cannot run against a relation that never materializes.
- Value-range and relationship tests use `dbt_utils` and `dbt_expectations`.
- Unit tests are written for every model that holds business logic, before the
  logic is added, asserting output for a fixture input. They cover boundary
  bucketing, the resample, growth-factor and fee math, carry-forward, compounding,
  the last-date read, and the drawdown-against-running-peak calculation.
