DROP TABLE IF EXISTS lessons CASCADE;
DROP TABLE IF EXISTS clients CASCADE;
DROP TABLE IF EXISTS interviews CASCADE;
DROP TABLE IF EXISTS employees CASCADE;
DROP TABLE IF EXISTS cars CASCADE;

DROP TYPE IF EXISTS STATUS;
DROP TYPE IF EXISTS TITLE;

--

CREATE TYPE STATUS AS ENUM ('not_ready', 'ready', 'passed', 'flunked');
CREATE TYPE TITLE AS ENUM ('instructor', 'auto_technicians', 'administrative_staff');

CREATE TABLE employees (
    emp SERIAL PRIMARY KEY,
    name VARCHAR(30) NOT NULL,
    title TITLE NOT NULL
);

CREATE TABLE cars (
    car SERIAL PRIMARY KEY,
    tech_check TIMESTAMP NOT NULL
);

CREATE TABLE clients (
    client SERIAL PRIMARY KEY,
    name VARCHAR(30) NOT NULL,
    birth DATE NOT NULL,
    car INTEGER REFERENCES cars(car) NOT NULL,
    instructor INTEGER REFERENCES employees(emp) NOT NULL,
    attempts INTEGER DEFAULT 0,
    status STATUS DEFAULT 'not_ready' NOT NULL,
    pass_date DATE DEFAULT NULL
);

CREATE TABLE lessons (
    lesson SERIAL PRIMARY KEY,
    client INTEGER REFERENCES clients(client) NOT NULL,
    instructor INTEGER REFERENCES employees(emp) NOT NULL,
    start TIMESTAMP NOT NULL
);

CREATE TABLE interviews (
    interview SERIAL PRIMARY KEY,
    employee INTEGER REFERENCES employees(emp) NOT NULL,
    client INTEGER REFERENCES clients(client) NOT NULL UNIQUE,
    start TIMESTAMP NOT NULL
);