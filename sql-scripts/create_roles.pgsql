DROP USER IF EXISTS user_client;
DROP USER IF EXISTS user_instructor;
DROP USER IF EXISTS user_auto_technician;
DROP USER IF EXISTS user_administrative_staff;

DROP ROLE IF EXISTS client;
DROP ROLE IF EXISTS instructor;
DROP ROLE IF EXISTS auto_technician;
DROP ROLE IF EXISTS administrative_staff;

--

-- Revoke privileges from 'public' role
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE miniproject1 FROM PUBLIC;

--

CREATE ROLE client;
CREATE ROLE instructor;
CREATE ROLE auto_technician;
CREATE ROLE administrative_staff;

--

CREATE USER user_client LOGIN PASSWORD '1234';
CREATE USER user_instructor LOGIN PASSWORD '1234';
CREATE USER user_auto_technician LOGIN PASSWORD '1234';
CREATE USER user_administrative_staff LOGIN PASSWORD '1234';

--

GRANT client TO user_client;
GRANT instructor TO user_instructor;
GRANT auto_technician TO user_auto_technician;
GRANT administrative_staff TO user_administrative_staff;

-- 

GRANT EXECUTE ON PROCEDURE add_client TO administrative_staff;
GRANT EXECUTE ON PROCEDURE add_lesson TO administrative_staff;
GRANT EXECUTE ON FUNCTION get_work_load TO administrative_staff;
GRANT EXECUTE ON FUNCTION get_success_rate TO administrative_staff;

GRANT EXECUTE ON PROCEDURE update_tech_check TO auto_technician;
GRANT SELECT ON TABLE cars TO auto_technician;

GRANT EXECUTE ON PROCEDURE add_lesson TO instructor;
GRANT EXECUTE ON PROCEDURE update_client_status_ready TO instructor;
GRANT EXECUTE ON PROCEDURE update_client_status_passed TO instructor;
GRANT EXECUTE ON FUNCTION get_work_load TO instructor;