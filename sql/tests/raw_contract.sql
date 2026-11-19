-- проверяем повторы и выбор среза, тестовые строки в конце откатываем
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    first_run BIGINT;
    failed_run BIGINT;
    next_run BIGINT;
    empty_run BIGINT;
    selected_run BIGINT;
    rows_count BIGINT;
BEGIN
    INSERT INTO raw.collection_runs (source, snapshot_date, queries, started_at)
    VALUES ('__raw_contract_test__', '2026-11-19', ARRAY['data'], '2026-11-19 08:00:00+03')
    RETURNING id INTO first_run;

    INSERT INTO raw.vacancies (run_id, source_vacancy_id, payload, observed_at)
    VALUES (first_run, 'vacancy-1', '{"title":"Data engineer"}', '2026-11-19 08:01:00+03');

    IF EXISTS (SELECT 1 FROM raw.accepted_runs WHERE id = first_run)
       OR EXISTS (SELECT 1 FROM raw.accepted_vacancies WHERE run_id = first_run) THEN
        RAISE EXCEPTION 'Running collection is visible to downstream models';
    END IF;

    BEGIN
        INSERT INTO raw.vacancies (run_id, source_vacancy_id, payload, observed_at)
        VALUES (first_run, 'vacancy-1', '{}', NOW());
        RAISE EXCEPTION 'Duplicate vacancy was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        UPDATE raw.collection_runs SET status = 'complete' WHERE id = first_run;
        RAISE EXCEPTION 'Complete collection without finish time was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO raw.collection_log (run_id, query, started_at)
    VALUES (first_run, 'data', '2026-11-19 08:00:00+03');

    BEGIN
        INSERT INTO raw.collection_log (run_id, query, started_at)
        VALUES (first_run, 'data', '2026-11-19 08:00:00+03');
        RAISE EXCEPTION 'Duplicate query was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        UPDATE raw.collection_log SET fetched = -1 WHERE run_id = first_run;
        RAISE EXCEPTION 'Negative row count was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    UPDATE raw.collection_log
    SET status = 'complete', fetched = 1, finished_at = '2026-11-19 08:02:00+03'
    WHERE run_id = first_run;

    UPDATE raw.collection_runs
    SET status = 'complete', finished_at = '2026-11-19 12:00:00+03'
    WHERE id = first_run;

    INSERT INTO raw.collection_runs (source, snapshot_date, queries, status, started_at, finished_at)
    VALUES ('__raw_contract_test__', '2026-11-19', ARRAY['data'], 'failed',
            '2026-11-19 09:00:00+03', '2026-11-19 09:02:00+03')
    RETURNING id INTO failed_run;

    INSERT INTO raw.vacancies (run_id, source_vacancy_id, payload, observed_at)
    VALUES (failed_run, 'partial-vacancy', '{}', '2026-11-19 09:01:00+03');

    SELECT id INTO selected_run FROM raw.accepted_runs WHERE source = '__raw_contract_test__';
    SELECT count(*) INTO rows_count FROM raw.accepted_vacancies WHERE source = '__raw_contract_test__';
    IF selected_run IS DISTINCT FROM first_run OR rows_count <> 1 THEN
        RAISE EXCEPTION 'Failed retry changed accepted snapshot';
    END IF;

    INSERT INTO raw.collection_runs (source, snapshot_date, queries, status, started_at, finished_at)
    VALUES ('__raw_contract_test__', '2026-11-19', ARRAY['data'], 'complete',
            '2026-11-19 10:00:00+03', '2026-11-19 10:02:00+03')
    RETURNING id INTO next_run;

    INSERT INTO raw.vacancies (run_id, source_vacancy_id, payload, observed_at)
    VALUES (next_run, 'vacancy-1', '{"title":"Updated title"}', '2026-11-19 10:01:00+03');

    SELECT id INTO selected_run FROM raw.accepted_runs WHERE source = '__raw_contract_test__';
    SELECT count(*) INTO rows_count FROM raw.accepted_vacancies WHERE source = '__raw_contract_test__';
    IF selected_run IS DISTINCT FROM next_run OR rows_count <> 1 THEN
        RAISE EXCEPTION 'Successful retry did not replace the accepted snapshot';
    END IF;

    INSERT INTO raw.collection_runs (source, snapshot_date, queries, status, started_at, finished_at)
    VALUES ('__raw_contract_test__', '2026-11-19', ARRAY['data'], 'complete',
            '2026-11-19 10:00:00+03', '2026-11-19 10:03:00+03')
    RETURNING id INTO empty_run;

    SELECT id INTO selected_run FROM raw.accepted_runs WHERE source = '__raw_contract_test__';
    SELECT count(*) INTO rows_count FROM raw.accepted_vacancies WHERE source = '__raw_contract_test__';
    IF selected_run IS DISTINCT FROM empty_run OR rows_count <> 0 THEN
        RAISE EXCEPTION 'Empty successful snapshot or equal start time handled incorrectly';
    END IF;

    RAISE NOTICE 'Raw contract checks passed';
END;
$$;

ROLLBACK;
