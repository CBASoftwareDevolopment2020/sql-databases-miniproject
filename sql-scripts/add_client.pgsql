CREATE OR REPLACE FUNCTION add_client(
    name VARCHAR(30), birth DATE, teacher INTEGER, car INTEGER
)
RETURNS VOID AS $$
DECLARE
    age INTEGER;
BEGIN
    age := EXTRACT(YEAR FROM age(birth));
    RAISE NOTICE 'the age is %', age;

    IF age >= 18 THEN
        INSERT INTO clients (name, birth, teacher, car)
        VALUES (name, birth, teacher, car);

    ELSE RAISE NOTICE 'Too young to drive';
    END IF;
END;
$$ LANGUAGE PLPGSQL;