CREATE OR REPLACE FUNCTION update_client_status(
    is_ready BOOLEAN, client_id INTEGER
) RETURNS VOID AS $$
DECLARE
    lessons INTEGER;
BEGIN
    IF is_ready THEN
        lessons := (SELECT COUNT(*) FROM lessons WHERE client = client_id AND start < NOW());

        IF lessons >= 10 THEN
            UPDATE clients
            SET status = 'ready'
            WHERE client = client;

        ELSE RAISE NOTICE 'A minimum of 10 participated is required, only % acquired.', lessons;
        END IF;
    ELSE
        RAISE NOTICE 'Client status set to: not ready.';
    END IF;
END;
$$ LANGUAGE PLPGSQL;