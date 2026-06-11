.PHONY: up down load deps build answers all lint format test lightdash

# Point dbt at the project-local profiles.yml (same dir sqlfluff already uses).
export DBT_PROFILES_DIR := $(CURDIR)

up:
	docker compose up -d --wait

down:
	docker compose down

load:
	bash scripts/load_data.sh

deps:
	uv run dbt deps

build: deps
	uv run dbt build

answers:
	bash scripts/print_answers.sh

# Full pipeline from a cold start: database, data, models + tests, answers.
all: up load build answers

test: deps
	uv run dbt test

lint:
	@if [ -z "$$(find models macros analyses -name '*.sql' 2>/dev/null)" ]; then \
		echo "no sql to lint yet; skipping"; \
	else \
		uv run sqlfluff lint models macros analyses; \
	fi

format:
	@if [ -z "$$(find models macros analyses -name '*.sql' 2>/dev/null)" ]; then \
		echo "no sql to format yet; skipping"; \
	else \
		uv run sqlfluff fix models macros analyses; \
	fi

# Validate the Lightdash metadata (dimensions + metrics in the marts' schema.yml)
# against the Lightdash schema, offline. Compiles the explores from the dbt
# manifest; --skip-warehouse-catalog uses the YAML column types so it needs no
# SSL warehouse round-trip. Needs the Lightdash CLI (npm i -g @lightdash/cli) and
# puts the project's dbt on PATH so the CLI's bare `dbt` call resolves to it.
lightdash:
	PATH="$(CURDIR)/.venv/bin:$$PATH" lightdash compile \
		--project-dir $(CURDIR) --profiles-dir $(CURDIR) --skip-warehouse-catalog
