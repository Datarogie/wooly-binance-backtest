# Thin wrappers around each step of the pipeline. `run.sh` is the graded
# single entrypoint (Phase 8); these targets exist for development and mirror it.
# Some targets depend on later phases (Docker harness, dbt project) and will be
# wired up as those land.

.PHONY: all up down load build test answers lint fmt deps

# Full pipeline (Phase 8 will back this with run.sh).
all: up load build answers

# Database harness (Phase 2).
up:
	docker compose up -d

down:
	docker compose down

load:
	bash scripts/load_data.sh

# dbt (Phase 3+).
deps:
	uv run dbt deps

build:
	uv run dbt build

test:
	uv run dbt test

answers:
	uv run dbt build --select answer_strategy_questions

# Linting works from Phase 1 onward. The dbt templater compiles the whole
# project, which does not exist until Phase 3, so skip cleanly until there is
# actually SQL to lint.
lint:
	@if [ -z "$$(find models macros analyses -name '*.sql' 2>/dev/null)" ]; then \
		echo "no SQL files to lint yet (pre-Phase 3); skipping"; \
	else \
		uv run sqlfluff lint models macros analyses; \
	fi

fmt:
	@if [ -z "$$(find models macros analyses -name '*.sql' 2>/dev/null)" ]; then \
		echo "no SQL files to format yet (pre-Phase 3); skipping"; \
	else \
		uv run sqlfluff fix models macros analyses; \
	fi
