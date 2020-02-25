CREATE OR REPLACE PROCEDURE update_tech_check(id INTEGER)
LANGUAGE PLPGSQL AS $$
BEGIN
    UPDATE cars 
    SET tech_check = tech_check + INTERVAL '1 year'
    WHERE car = id;
END;
$$