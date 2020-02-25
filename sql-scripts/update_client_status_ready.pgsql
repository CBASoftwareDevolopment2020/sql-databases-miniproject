CREATE OR REPLACE PROCEDURE update_client_status_ready(
    is_ready BOOLEAN, client_id INTEGER
) 
LANGUAGE PLPGSQL AS $$
DECLARE
    lessons INTEGER;
BEGIN
    IF is_ready THEN
        lessons := (SELECT COUNT(*) FROM lessons WHERE client = client_id AND start < NOW());

        IF lessons >= 10 THEN
            UPDATE clients
            SET status = 'ready'
            WHERE client = client_id;

        ELSE RAISE NOTICE 'A minimum of 10 participated is required, only % acquired.', lessons;
        END IF;
    ELSE
        UPDATE clients
        SET status = 'not_ready'
        WHERE client = client_id;
        
        RAISE NOTICE 'Client status set to: not ready.';
    END IF;
END;
$$;