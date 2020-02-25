CREATE OR REPLACE FUNCTION get_success_rate()
RETURNS DECIMAL(5, 2) AS $$
DECLARE
    passed DECIMAL(5, 2);
    total_attempts DECIMAL(5, 2);
BEGIN
    total_attempts := (SELECT SUM(attempts) FROM clients);

    IF total_attempts > 0 THEN
        passed := (SELECT COUNT(*) FROM archive);
        RETURN CAST(passed / total_attempts * 100 AS DECIMAL(5, 2));

    ELSE RETURN 0;
    END IF;
END;
$$ LANGUAGE PLPGSQL;