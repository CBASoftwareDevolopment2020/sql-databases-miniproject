CREATE OR REPLACE PROCEDURE add_lesson(
    client_id INTEGER, instructor_id INTEGER, start_time TIMESTAMP
)
LANGUAGE PLPGSQL AS $$
DECLARE
    isInterviewed BOOLEAN;
BEGIN
    isInterviewed := ((SELECT interviews.start FROM interviews WHERE client = client_id) < NOW());

    IF ((SELECT COUNT(*) FROM clients WHERE client = client_id) = 0) THEN 
        RAISE NOTICE 'The client doesnt exits';

    ELSIF ((SELECT COUNT(*) FROM employees WHERE emp = instructor_id) = 0) THEN 
        RAISE NOTICE 'The employee doesnt exits';

    ELSIF (SELECT count(*) FROM cars WHERE car = (SELECT car FROM clients WHERE client = client_id) AND tech_check = start_time) > 0 THEN
        RAISE NOTICE 'The car isnt available at this date';

    ELSIF (
    SELECT COUNT(*)
    FROM cars c JOIN lessons l
    ON c.car = l.car
    WHERE c.car = (SELECT car 
                    FROM clients 
                    WHERE client = client_id)
    AND l.start = start_time) > 0 THEN
        RAISE NOTICE 'The car isnt available at this date';

    ELSIF (
    SELECT COUNT(*)
    FROM employees e JOIN lessons l
    ON e.emp = l.instructor
    WHERE e.emp = (SELECT instructor
                    FROM clients 
                    WHERE client = client_id)
    AND l.start = start_time) > 0 THEN
        RAISE NOTICE 'The instructor isnt available at this date';

    ELSIF ((SELECT title from employees WHERE emp = instructor_id) != 'instructor') THEN
        RAISE NOTICE 'Employee must be an instructor';

    ELSIF start_time < NOW() THEN
        RAISE NOTICE 'Date must be after current date';

    ELSIF isInterviewed THEN
        INSERT INTO lessons (client, instructor, start, car)
        VALUES (client_id, instructor_id, start_time,(SELECT car FROM clients WHERE client = client_id));
        RAISE NOTICE 'Client % successfully added to lessons', client_id;
    
    ELSE RAISE NOTICE 'An interview is required to book lessons';
    END IF;

END;
$$;
