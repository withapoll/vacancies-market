-- миграция 002: отделяем попытку сбора от принятого дневного среза
-- старый сборщик ещё не написан, таблицы должны быть пустыми

BEGIN;

LOCK TABLE raw.vacancies, raw.collection_log IN ACCESS EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM raw.vacancies)
       OR EXISTS (SELECT 1 FROM raw.collection_log) THEN
        RAISE EXCEPTION 'Migration 002 requires empty raw tables; existing data needs a separate migration';
    END IF;
END;
$$;

CREATE TABLE raw.collection_runs (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source         TEXT        NOT NULL,
    snapshot_date  DATE        NOT NULL,
    queries        TEXT[]      NOT NULL,
    status         TEXT        NOT NULL DEFAULT 'running',
    message        TEXT,
    started_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at    TIMESTAMPTZ,
    CONSTRAINT chk_run_queries CHECK (cardinality(queries) > 0),
    CONSTRAINT chk_run_status CHECK (status IN ('running', 'complete', 'failed')),
    CONSTRAINT chk_run_finished CHECK (
        (status = 'running' AND finished_at IS NULL)
        OR (status IN ('complete', 'failed') AND finished_at IS NOT NULL)
    ),
    CONSTRAINT chk_run_time CHECK (finished_at >= started_at)
);

ALTER TABLE raw.vacancies
    DROP CONSTRAINT uq_raw_vacancies,
    DROP COLUMN source,
    DROP COLUMN snapshot_date,
    ADD COLUMN run_id BIGINT NOT NULL REFERENCES raw.collection_runs (id),
    ADD COLUMN observed_at TIMESTAMPTZ NOT NULL,
    ADD CONSTRAINT uq_raw_vacancies UNIQUE (run_id, source_vacancy_id);

ALTER TABLE raw.collection_log
    DROP CONSTRAINT chk_collection_status,
    DROP COLUMN source,
    DROP COLUMN snapshot_date,
    ADD COLUMN run_id BIGINT NOT NULL REFERENCES raw.collection_runs (id),
    ALTER COLUMN status SET DEFAULT 'running',
    ALTER COLUMN finished_at DROP DEFAULT,
    ALTER COLUMN finished_at DROP NOT NULL,
    ADD CONSTRAINT uq_collection_query UNIQUE (run_id, query),
    ADD CONSTRAINT chk_collection_status CHECK (status IN ('running', 'complete', 'failed')),
    ADD CONSTRAINT chk_collection_counts CHECK (
        fetched >= 0 AND pages_failed >= 0 AND (total_reported IS NULL OR total_reported >= 0)
    ),
    ADD CONSTRAINT chk_collection_finished CHECK (
        (status = 'running' AND finished_at IS NULL)
        OR (status IN ('complete', 'failed') AND finished_at IS NOT NULL)
    ),
    ADD CONSTRAINT chk_collection_time CHECK (finished_at >= started_at);

CREATE VIEW raw.accepted_runs AS
SELECT DISTINCT ON (source, snapshot_date)
    id, source, snapshot_date, queries, status, started_at, finished_at
FROM raw.collection_runs
WHERE status = 'complete'
ORDER BY source, snapshot_date, started_at DESC, id DESC;

CREATE VIEW raw.accepted_vacancies AS
SELECT
    v.id,
    r.id AS run_id,
    r.source,
    v.source_vacancy_id,
    r.snapshot_date,
    v.payload,
    v.observed_at,
    v.loaded_at
FROM raw.vacancies AS v
JOIN raw.accepted_runs AS r ON r.id = v.run_id;

COMMIT;
