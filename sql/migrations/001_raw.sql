-- миграция 001: сырой слой
-- отдельная схема raw: здесь лежит то что пришло из источников
-- модели dbt будут строиться в других схемах, и граница «пришло / посчитали» видна по имени

CREATE SCHEMA raw;
CREATE TABLE raw.vacancies (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source            TEXT        NOT NULL,
    source_vacancy_id TEXT        NOT NULL,
    snapshot_date     DATE        NOT NULL,
    payload           JSONB       NOT NULL,
    loaded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_raw_vacancies UNIQUE (source, source_vacancy_id, snapshot_date)
);

-- журнал сбора
CREATE TABLE raw.collection_log (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source         TEXT        NOT NULL,
    snapshot_date  DATE        NOT NULL,
    query          TEXT        NOT NULL,
    total_reported INT,                      
    fetched        INT         NOT NULL DEFAULT 0,
    pages_failed   INT         NOT NULL DEFAULT 0,
    status         TEXT        NOT NULL,
    message        TEXT,
    started_at     TIMESTAMPTZ NOT NULL,
    finished_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_collection_status CHECK (status IN ('complete', 'partial', 'failed'))
);
