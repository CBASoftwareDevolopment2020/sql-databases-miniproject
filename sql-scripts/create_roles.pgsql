-- Revoke privileges from 'public' role
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE miniproject1 FROM PUBLIC;

CREATE ROLE admin LOGIN PASSWORD 'admin' SUPERUSER;
CREATE ROLE client;
CREATE ROLE instructor;
CREATE ROLE auto_technicians;
CREATE ROLE administrative_staff;
