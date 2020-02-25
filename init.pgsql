
CREATE DATABASE miniproject1;

\c miniproject1

CREATE SCHEMA driving_school;
SET SEARCH_PATH TO driving_school;

\i sql-scripts/create_tables.pgsql
\i sql-scripts/create_views.pgsql

-- \i sql-scripts/add_client.pgsql
-- \i sql-scripts/add_lesson.pgsql
\i sql-scripts/get_success_rate.pgsql
\i sql-scripts/get_work_load.pgsql
\i sql-scripts/update_client_status_ready.pgsql
\i sql-scripts/update_client_status_passed.pgsql
\i sql-scripts/update_tech_check.pgsql

-- \i sql-scripts/create_roles.pgsql

\i sql-scripts/populate_tables.pgsql