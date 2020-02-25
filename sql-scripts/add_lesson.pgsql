DROP PROCEDURE IF EXISTS add_lesson;

CREATE OR REPLACE PROCEDURE add_lesson(
    client_id INTEGER, instructor INTEGER, start TIMESTAMP
)
LANGUAGE PLPGSQL AS $$
DECLARE
    isInterviewed BOOLEAN;
BEGIN
    isInterviewed := ((SELECT interviews.start FROM interviews WHERE client = client_id) < NOW());

    IF ((SELECT COUNT(*) FROM clients WHERE client = client_id) = 0) THEN 
        RAISE NOTICE 'The client doesnt exits';

    ELSIF ((SELECT COUNT(*) FROM employees WHERE emp = instructor) = 0) THEN 
        RAISE NOTICE 'The employee doesnt exits';

    ELSIF CAST(SELECT tech_check FROM cars WHERE car = (SELECT car FROM clients WHERE client = client_id) AS DATE) = CAST(start AS DATE) THEN
        RAISE NOTICE 'The car isnt available at this date';

    IF CAST(SELECT start FROM lessons WHERE car = (SELECT car FROM clients WHERE client = client_id) AS DATE) = CAST(start AS DATE) THEN
        RAISE NOTICE 'The car isnt available at this date';

    ELSIF ((SELECT title from employees WHERE emp = instructor) != 'instructor') THEN
        RAISE NOTICE 'Employee must be an instructor';

    ELSIF start < NOW() THEN
        RAISE NOTICE 'Date must be after current date';

    ELSIF isInterviewed THEN
        INSERT INTO lessons (client, instructor, start)
        VALUES (client_id, instructor, start);
        RAISE NOTICE 'Client % successfully added to lessons', client_id;
    
    ELSE RAISE NOTICE 'An interview is required to book lessons';
    END IF;

    -- avoid multiple lessons at the same time
END;
$$;

