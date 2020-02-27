CREATE OR REPLACE FUNCTION get_success_rate()
RETURNS FLOAT AS $$
DECLARE
    passed FLOAT;
    total_attempts FLOAT;
BEGIN
    total_attempts := (SELECT SUM(attempts) FROM clients);

    IF total_attempts > 0 THEN
        passed := (SELECT COUNT(*) FROM archive);
        RETURN CAST(passed / total_attempts * 100 AS FLOAT);

    ELSE RETURN 0;
    END IF;
END;
$$ LANGUAGE PLPGSQL;