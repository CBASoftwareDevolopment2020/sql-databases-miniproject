CREATE OR REPLACE FUNCTION update_client_status_passed(
    client_id INTEGER, passed BOOLEAN
) RETURNS VOID AS $$
DECLARE
    isReady BOOLEAN;
BEGIN

    IF passed THEN
        isReady := ((SELECT status FROM clients WHERE client = client_id) = 'ready');

        IF isReady THEN
            UPDATE clients
            SET status = 'passed', pass_date = NOW(), attempts = attempts + 1
            WHERE client = client_id;

        ELSE RAISE NOTICE 'The client must be ready before passing.';
        END IF;

    ELSE
        UPDATE clients
        SET status = 'not_ready', attempts = attempts + 1
        WHERE client = client_id;

    END IF;
END;
$$ LANGUAGE PLPGSQL;