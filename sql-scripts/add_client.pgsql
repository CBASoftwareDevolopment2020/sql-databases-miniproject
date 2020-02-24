CREATE OR REPLACE FUNCTION add_client(
    name VARCHAR(30), birth DATE, instructor INTEGER, car INTEGER, interview_start TIMESTAMP
)
RETURNS VOID AS $$
DECLARE
    age INTEGER;
    client_id INTEGER;
    emp_id INTEGER;
BEGIN
    age := EXTRACT(YEAR FROM age(birth));
    RAISE NOTICE 'the age is %', age;

    IF age >= 18 THEN
        INSERT INTO clients (name, birth, instructor, car)
        VALUES (name, birth, instructor, car)
        RETURNING client INTO client_id;

        -- counts pr full hour
        emp_id := (SELECT emp FROM admin_staff_work WHERE start != interview_start LIMIT 1);
        RAISE NOTICE 'emp_id:: %', emp_id;

        IF emp_id THEN
            INSERT INTO interviews (employee, client, start)
            VALUES (emp_id, client_id, interview_start);
        ELSE
            RAISE NOTICE 'There is no avaiable employees at that time';
            -- ROLLBACK;
        END IF;

    ELSE RAISE NOTICE 'Too young to drive';
    END IF;
END;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE VIEW admin_staff_work AS
SELECT * FROM employees e
LEFT JOIN interviews i
    ON e.emp = i.employee
WHERE e.title = 'administrative_staff';
