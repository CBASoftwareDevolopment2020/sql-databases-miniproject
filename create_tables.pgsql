DROP TABLE IF EXISTS lessons;
DROP TABLE IF EXISTS clients;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS cars;

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
    teacher INTEGER REFERENCES employees(emp) NOT NULL,
    status STATUS DEFAULT 'not_ready' NOT NULL,
    pass_date DATE DEFAULT NULL
);

CREATE TABLE lessons (
    lesson SERIAL PRIMARY KEY,
    client INTEGER REFERENCES clients(client) NOT NULL,
    teacher INTEGER REFERENCES employees(emp) NOT NULL,
    start TIMESTAMP NOT NULL
);