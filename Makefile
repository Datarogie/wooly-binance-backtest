.PHONY: up down load deps build answers all lint format test charts

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

charts:
	uv run python scripts/make_charts.py
