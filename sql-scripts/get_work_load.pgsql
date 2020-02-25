CREATE OR REPLACE FUNCTION get_work_load(emp_id INTEGER, start_date DATE, end_date DATE)
RETURNS INTEGER AS $$
BEGIN
    RETURN (SELECT COUNT(*) 
            FROM employees e 
            JOIN lessons l 
                ON e.emp = l.instructor 
            WHERE e.emp = emp_id 
            AND l.start >= start_date 
            AND l.start <= end_date);
END;
$$ LANGUAGE PLPGSQL;