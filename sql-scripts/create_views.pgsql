CREATE OR REPLACE VIEW archive AS 
SELECT * 
FROM clients 
WHERE status = 'passed';

--

CREATE OR REPLACE VIEW failed_first_attempt AS 
SELECT * 
FROM clients 
WHERE attempts > 1 OR (attempts = 1 AND status != 'passed');

--

CREATE OR REPLACE VIEW admin_staff_work AS
SELECT * FROM employees e
LEFT JOIN interviews i
    ON e.emp = i.employee
WHERE e.title = 'administrative_staff';

-- 

CREATE OR REPLACE VIEW notify_tech_check AS
SELECT * FROM cars WHERE DATE_PART('day', cars.tech_check - NOW()) <= 7
ORDER BY tech_check ASC;