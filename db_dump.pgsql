--
-- PostgreSQL database dump
--

-- Dumped from database version 12.1
-- Dumped by pg_dump version 12.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: driving_school; Type: SCHEMA; Schema: -; Owner: stephan
--

CREATE SCHEMA driving_school;


ALTER SCHEMA driving_school OWNER TO stephan;

--
-- Name: status; Type: TYPE; Schema: driving_school; Owner: stephan
--

CREATE TYPE driving_school.status AS ENUM (
    'not_ready',
    'ready',
    'passed',
    'flunked'
);


ALTER TYPE driving_school.status OWNER TO stephan;

--
-- Name: title; Type: TYPE; Schema: driving_school; Owner: stephan
--

CREATE TYPE driving_school.title AS ENUM (
    'instructor',
    'auto_technicians',
    'administrative_staff'
);


ALTER TYPE driving_school.title OWNER TO stephan;

--
-- Name: add_client(character varying, date, integer, integer, timestamp without time zone); Type: PROCEDURE; Schema: driving_school; Owner: stephan
--

CREATE PROCEDURE driving_school.add_client(name character varying, birth date, instructor integer, car integer, interview_start timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
    age INTEGER;
    client_id INTEGER;
    emp_id INTEGER;
BEGIN
    age := EXTRACT(YEAR FROM age(birth));
    RAISE NOTICE 'the age is %', age;

    IF age >= 18 THEN
        -- counts pr full hour
        emp_id := (SELECT emp FROM admin_staff_work WHERE start != interview_start LIMIT 1);
        RAISE NOTICE 'emp_id:: %', emp_id;

        IF emp_id THEN
            INSERT INTO clients (name, birth, instructor, car)
            VALUES (name, birth, instructor, car)
            RETURNING client INTO client_id;

            INSERT INTO interviews (employee, client, start)
            VALUES (emp_id, client_id, interview_start);
        ELSE
            RAISE NOTICE 'There is no avaiable employees at that time';
        END IF;

    ELSE RAISE NOTICE 'Too young to drive';
    END IF;
END;
$$;


ALTER PROCEDURE driving_school.add_client(name character varying, birth date, instructor integer, car integer, interview_start timestamp without time zone) OWNER TO stephan;

--
-- Name: add_lesson(integer, integer, timestamp without time zone); Type: PROCEDURE; Schema: driving_school; Owner: stephan
--

CREATE PROCEDURE driving_school.add_lesson(client_id integer, instructor_id integer, start_time timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
    isInterviewed BOOLEAN;
BEGIN
    isInterviewed := ((SELECT interviews.start FROM interviews WHERE client = client_id) < NOW());

    IF ((SELECT COUNT(*) FROM clients WHERE client = client_id) = 0) THEN 
        RAISE NOTICE 'The client doesnt exits';

    ELSIF ((SELECT COUNT(*) FROM employees WHERE emp = instructor_id) = 0) THEN 
        RAISE NOTICE 'The employee doesnt exits';

    ELSIF (SELECT count(*) FROM cars WHERE car = (SELECT car FROM clients WHERE client = client_id) AND tech_check = start_time) > 0 THEN
        RAISE NOTICE 'The car isnt available at this date';

    ELSIF (
    SELECT COUNT(*)
    FROM cars c JOIN lessons l
    ON c.car = l.car
    WHERE c.car = (SELECT car 
                    FROM clients 
                    WHERE client = client_id)
    AND l.start = start_time) > 0 THEN
        RAISE NOTICE 'The car isnt available at this date';

    ELSIF (
    SELECT COUNT(*)
    FROM employees e JOIN lessons l
    ON e.emp = l.instructor
    WHERE e.emp = (SELECT instructor
                    FROM clients 
                    WHERE client = client_id)
    AND l.start = start_time) > 0 THEN
        RAISE NOTICE 'The instructor isnt available at this date';

    ELSIF ((SELECT title from employees WHERE emp = instructor_id) != 'instructor') THEN
        RAISE NOTICE 'Employee must be an instructor';

    ELSIF start_time < NOW() THEN
        RAISE NOTICE 'Date must be after current date';

    ELSIF isInterviewed THEN
        INSERT INTO lessons (client, instructor, start, car)
        VALUES (client_id, instructor_id, start_time,(SELECT car FROM clients WHERE client = client_id));
        RAISE NOTICE 'Client % successfully added to lessons', client_id;
    
    ELSE RAISE NOTICE 'An interview is required to book lessons';
    END IF;

END;
$$;


ALTER PROCEDURE driving_school.add_lesson(client_id integer, instructor_id integer, start_time timestamp without time zone) OWNER TO stephan;

--
-- Name: get_success_rate(); Type: FUNCTION; Schema: driving_school; Owner: stephan
--

CREATE FUNCTION driving_school.get_success_rate() RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    passed DECIMAL(5, 2);
    total_attempts DECIMAL(5, 2);
BEGIN
    total_attempts := (SELECT SUM(attempts) FROM clients);

    IF total_attempts > 0 THEN
        passed := (SELECT COUNT(*) FROM archive);
        RETURN CAST(passed / total_attempts * 100 AS DECIMAL(5, 2));

    ELSE RETURN 0;
    END IF;
END;
$$;


ALTER FUNCTION driving_school.get_success_rate() OWNER TO stephan;

--
-- Name: get_work_load(integer, date, date); Type: FUNCTION; Schema: driving_school; Owner: stephan
--

CREATE FUNCTION driving_school.get_work_load(emp_id integer, start_date date, end_date date) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN (SELECT COUNT(*) 
            FROM employees e 
            JOIN lessons l 
                ON e.emp = l.instructor 
            WHERE e.emp = emp_id 
            AND l.start >= start_date 
            AND l.start <= end_date);
END;
$$;


ALTER FUNCTION driving_school.get_work_load(emp_id integer, start_date date, end_date date) OWNER TO stephan;

--
-- Name: update_client_status_passed(integer, boolean); Type: PROCEDURE; Schema: driving_school; Owner: stephan
--

CREATE PROCEDURE driving_school.update_client_status_passed(client_id integer, passed boolean)
    LANGUAGE plpgsql
    AS $$
DECLARE
    isReady BOOLEAN;
BEGIN
    IF passed THEN
        isReady := ((SELECT status FROM clients WHERE client = client_id) = 'ready');

        IF isReady THEN
            UPDATE clients
            SET status = 'passed', pass_date = NOW(), attempts = attempts + 1
            WHERE client = client_id;

        ELSE RAISE NOTICE 'The client must be ready before passing.';
        END IF;

    ELSE
        UPDATE clients
        SET status = 'not_ready', attempts = attempts + 1
        WHERE client = client_id;

    END IF;
END;
$$;


ALTER PROCEDURE driving_school.update_client_status_passed(client_id integer, passed boolean) OWNER TO stephan;

--
-- Name: update_client_status_ready(boolean, integer); Type: PROCEDURE; Schema: driving_school; Owner: stephan
--

CREATE PROCEDURE driving_school.update_client_status_ready(is_ready boolean, client_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    lessons INTEGER;
BEGIN
    IF is_ready THEN
        lessons := (SELECT COUNT(*) FROM lessons WHERE client = client_id AND start < NOW());

        IF lessons >= 10 THEN
            UPDATE clients
            SET status = 'ready'
            WHERE client = client_id;

        ELSE RAISE NOTICE 'A minimum of 10 participated is required, only % acquired.', lessons;
        END IF;
    ELSE
        UPDATE clients
        SET status = 'not_ready'
        WHERE client = client_id;
        
        RAISE NOTICE 'Client status set to: not ready.';
    END IF;
END;
$$;


ALTER PROCEDURE driving_school.update_client_status_ready(is_ready boolean, client_id integer) OWNER TO stephan;

--
-- Name: update_tech_check(integer); Type: PROCEDURE; Schema: driving_school; Owner: stephan
--

CREATE PROCEDURE driving_school.update_tech_check(id integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE cars 
    SET tech_check = tech_check + INTERVAL '1 year'
    WHERE car = id;
END;
$$;


ALTER PROCEDURE driving_school.update_tech_check(id integer) OWNER TO stephan;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: employees; Type: TABLE; Schema: driving_school; Owner: stephan
--

CREATE TABLE driving_school.employees (
    emp integer NOT NULL,
    name character varying(30) NOT NULL,
    title driving_school.title NOT NULL
);


ALTER TABLE driving_school.employees OWNER TO stephan;

--
-- Name: interviews; Type: TABLE; Schema: driving_school; Owner: stephan
--

CREATE TABLE driving_school.interviews (
    interview integer NOT NULL,
    employee integer NOT NULL,
    client integer NOT NULL,
    start timestamp without time zone NOT NULL
);


ALTER TABLE driving_school.interviews OWNER TO stephan;

--
-- Name: admin_staff_work; Type: VIEW; Schema: driving_school; Owner: stephan
--

CREATE VIEW driving_school.admin_staff_work AS
 SELECT e.emp,
    e.name,
    e.title,
    i.interview,
    i.employee,
    i.client,
    i.start
   FROM (driving_school.employees e
     LEFT JOIN driving_school.interviews i ON ((e.emp = i.employee)))
  WHERE (e.title = 'administrative_staff'::driving_school.title);


ALTER TABLE driving_school.admin_staff_work OWNER TO stephan;

--
-- Name: clients; Type: TABLE; Schema: driving_school; Owner: stephan
--

CREATE TABLE driving_school.clients (
    client integer NOT NULL,
    name character varying(30) NOT NULL,
    birth date NOT NULL,
    car integer NOT NULL,
    instructor integer NOT NULL,
    attempts integer DEFAULT 0,
    status driving_school.status DEFAULT 'not_ready'::driving_school.status NOT NULL,
    pass_date date
);


ALTER TABLE driving_school.clients OWNER TO stephan;

--
-- Name: archive; Type: VIEW; Schema: driving_school; Owner: stephan
--

CREATE VIEW driving_school.archive AS
 SELECT clients.client,
    clients.name,
    clients.birth,
    clients.car,
    clients.instructor,
    clients.attempts,
    clients.status,
    clients.pass_date
   FROM driving_school.clients
  WHERE (clients.status = 'passed'::driving_school.status);


ALTER TABLE driving_school.archive OWNER TO stephan;

--
-- Name: cars; Type: TABLE; Schema: driving_school; Owner: stephan
--

CREATE TABLE driving_school.cars (
    car integer NOT NULL,
    tech_check timestamp without time zone NOT NULL
);


ALTER TABLE driving_school.cars OWNER TO stephan;

--
-- Name: cars_car_seq; Type: SEQUENCE; Schema: driving_school; Owner: stephan
--

CREATE SEQUENCE driving_school.cars_car_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE driving_school.cars_car_seq OWNER TO stephan;

--
-- Name: cars_car_seq; Type: SEQUENCE OWNED BY; Schema: driving_school; Owner: stephan
--

ALTER SEQUENCE driving_school.cars_car_seq OWNED BY driving_school.cars.car;


--
-- Name: clients_client_seq; Type: SEQUENCE; Schema: driving_school; Owner: stephan
--

CREATE SEQUENCE driving_school.clients_client_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE driving_school.clients_client_seq OWNER TO stephan;

--
-- Name: clients_client_seq; Type: SEQUENCE OWNED BY; Schema: driving_school; Owner: stephan
--

ALTER SEQUENCE driving_school.clients_client_seq OWNED BY driving_school.clients.client;


--
-- Name: employees_emp_seq; Type: SEQUENCE; Schema: driving_school; Owner: stephan
--

CREATE SEQUENCE driving_school.employees_emp_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE driving_school.employees_emp_seq OWNER TO stephan;

--
-- Name: employees_emp_seq; Type: SEQUENCE OWNED BY; Schema: driving_school; Owner: stephan
--

ALTER SEQUENCE driving_school.employees_emp_seq OWNED BY driving_school.employees.emp;


--
-- Name: failed_first_attempt; Type: VIEW; Schema: driving_school; Owner: stephan
--

CREATE VIEW driving_school.failed_first_attempt AS
 SELECT clients.client,
    clients.name,
    clients.birth,
    clients.car,
    clients.instructor,
    clients.attempts,
    clients.status,
    clients.pass_date
   FROM driving_school.clients
  WHERE ((clients.attempts > 1) OR ((clients.attempts = 1) AND (clients.status <> 'passed'::driving_school.status)));


ALTER TABLE driving_school.failed_first_attempt OWNER TO stephan;

--
-- Name: interviews_interview_seq; Type: SEQUENCE; Schema: driving_school; Owner: stephan
--

CREATE SEQUENCE driving_school.interviews_interview_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE driving_school.interviews_interview_seq OWNER TO stephan;

--
-- Name: interviews_interview_seq; Type: SEQUENCE OWNED BY; Schema: driving_school; Owner: stephan
--

ALTER SEQUENCE driving_school.interviews_interview_seq OWNED BY driving_school.interviews.interview;


--
-- Name: lessons; Type: TABLE; Schema: driving_school; Owner: stephan
--

CREATE TABLE driving_school.lessons (
    lesson integer NOT NULL,
    client integer NOT NULL,
    instructor integer NOT NULL,
    car integer NOT NULL,
    start timestamp without time zone NOT NULL
);


ALTER TABLE driving_school.lessons OWNER TO stephan;

--
-- Name: lessons_lesson_seq; Type: SEQUENCE; Schema: driving_school; Owner: stephan
--

CREATE SEQUENCE driving_school.lessons_lesson_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE driving_school.lessons_lesson_seq OWNER TO stephan;

--
-- Name: lessons_lesson_seq; Type: SEQUENCE OWNED BY; Schema: driving_school; Owner: stephan
--

ALTER SEQUENCE driving_school.lessons_lesson_seq OWNED BY driving_school.lessons.lesson;


--
-- Name: notify_tech_check; Type: VIEW; Schema: driving_school; Owner: stephan
--

CREATE VIEW driving_school.notify_tech_check AS
 SELECT cars.car,
    cars.tech_check
   FROM driving_school.cars
  WHERE (date_part('day'::text, ((cars.tech_check)::timestamp with time zone - now())) <= (7)::double precision)
  ORDER BY cars.tech_check;


ALTER TABLE driving_school.notify_tech_check OWNER TO stephan;

--
-- Name: cars car; Type: DEFAULT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.cars ALTER COLUMN car SET DEFAULT nextval('driving_school.cars_car_seq'::regclass);


--
-- Name: clients client; Type: DEFAULT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.clients ALTER COLUMN client SET DEFAULT nextval('driving_school.clients_client_seq'::regclass);


--
-- Name: employees emp; Type: DEFAULT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.employees ALTER COLUMN emp SET DEFAULT nextval('driving_school.employees_emp_seq'::regclass);


--
-- Name: interviews interview; Type: DEFAULT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.interviews ALTER COLUMN interview SET DEFAULT nextval('driving_school.interviews_interview_seq'::regclass);


--
-- Name: lessons lesson; Type: DEFAULT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.lessons ALTER COLUMN lesson SET DEFAULT nextval('driving_school.lessons_lesson_seq'::regclass);


--
-- Data for Name: cars; Type: TABLE DATA; Schema: driving_school; Owner: stephan
--

COPY driving_school.cars (car, tech_check) FROM stdin;
1	2020-03-01 00:00:00
2	2020-06-29 00:00:00
3	2020-11-29 00:00:00
4	2020-08-30 00:00:00
5	2020-12-19 00:00:00
6	2020-02-10 00:00:00
7	2020-12-22 00:00:00
8	2020-09-29 00:00:00
9	2020-02-15 00:00:00
10	2020-08-20 00:00:00
11	2020-08-13 00:00:00
12	2020-08-07 00:00:00
13	2020-07-16 00:00:00
14	2020-02-12 00:00:00
15	2020-10-20 00:00:00
16	2020-04-26 00:00:00
17	2020-12-14 00:00:00
18	2020-02-08 00:00:00
19	2020-09-24 00:00:00
20	2020-12-30 00:00:00
\.


--
-- Data for Name: clients; Type: TABLE DATA; Schema: driving_school; Owner: stephan
--

COPY driving_school.clients (client, name, birth, car, instructor, attempts, status, pass_date) FROM stdin;
1	Per Christiansen	1976-07-10	14	2	0	not_ready	\N
2	Rasmus Sørensen	1966-10-20	13	19	0	passed	2020-08-23
3	Jacob Jensen	1994-03-22	19	17	0	not_ready	\N
4	Anne Mortensen	1999-10-29	18	11	0	not_ready	\N
5	Kirsten Andersen	1986-09-10	19	1	0	not_ready	\N
6	Jørgen Sørensen	1976-07-03	19	17	0	not_ready	\N
7	Morten Mortensen	1962-08-03	2	17	0	not_ready	\N
8	Niels Mortensen	1968-10-17	3	18	0	not_ready	\N
9	Tina Møller	1974-09-15	1	19	0	not_ready	\N
10	Charlotte Christiansen	1959-12-30	5	1	0	not_ready	\N
11	Lene Christiansen	1980-02-17	14	13	0	not_ready	\N
12	Hanne Christensen	1963-12-13	5	11	2	not_ready	\N
13	Kirsten Thomsen	1964-06-25	14	13	0	not_ready	\N
14	Lene Madsen	1997-10-06	17	12	0	not_ready	\N
15	Lene Poulsen	1980-09-12	2	15	0	not_ready	\N
16	Jens Olsen	1987-02-01	19	3	0	not_ready	\N
17	Rasmus Rasmussen	1988-12-21	20	6	0	not_ready	\N
18	Lars Christensen	1954-11-12	15	19	2	not_ready	\N
19	Susanne Poulsen	1972-05-06	7	17	0	not_ready	\N
20	Hanne Christiansen	1959-07-05	12	10	0	not_ready	\N
21	Stephan Poulsen	1973-11-16	17	19	0	ready	\N
22	Henrik Rasmussen	1986-04-15	6	14	3	ready	\N
23	Bente Olsen	1992-06-30	13	17	2	ready	\N
24	Louise Larsen	1965-05-25	9	20	4	passed	2019-02-02
25	Maria Jensen	1970-05-21	6	20	0	not_ready	\N
26	Lars Møller	1991-10-26	20	2	0	not_ready	\N
27	Niels Rasmussen	1997-04-02	14	18	0	passed	2021-06-12
28	Gitte Rasmussen	1970-04-06	9	3	0	ready	\N
29	Anna Petersen	1952-04-21	20	7	3	passed	2020-12-06
30	Tina Christiansen	1981-02-24	3	20	0	not_ready	\N
31	Charlotte Christiansen	1990-02-23	3	3	0	ready	\N
32	Jens Kristensen	1974-01-14	9	11	0	not_ready	\N
33	Thomas Olsen	1971-03-14	6	1	0	not_ready	\N
34	Morten Olsen	1975-11-24	8	4	0	not_ready	\N
35	Louise Jensen	1951-11-16	20	17	4	not_ready	\N
36	Marianne Olsen	1953-03-23	3	17	0	not_ready	\N
37	Ole Sørensen	1977-04-15	20	1	0	not_ready	\N
38	Daniel Sørensen	1994-07-26	8	5	3	ready	\N
39	Jens Madsen	1984-06-27	16	3	0	not_ready	\N
40	Anna Olsen	1984-08-14	11	18	0	not_ready	\N
41	Nikolaj Pedersen	1964-12-28	13	13	0	not_ready	\N
42	Camilla Madsen	1998-04-28	5	13	0	not_ready	\N
43	Hans Petersen	1976-08-16	6	5	0	not_ready	\N
44	Michael Lindholm	1969-10-15	20	14	0	not_ready	\N
45	Christian Pedersen	1963-11-20	11	8	0	not_ready	\N
46	Daniel Jensen	1989-10-25	5	16	0	not_ready	\N
47	Stephan Johansen	1964-09-24	1	9	1	passed	2019-01-15
48	Anne Kristensen	1954-01-26	5	18	0	not_ready	\N
49	Charlotte Larsen	1967-02-08	20	19	0	not_ready	\N
50	Tina Jensen	1989-10-23	3	15	3	not_ready	\N
51	Maria Hansen	1963-02-10	11	15	1	ready	\N
52	Pia Nielsen	1967-11-30	15	17	0	not_ready	\N
53	Mads Johansen	1978-05-25	9	17	4	not_ready	\N
54	Christian Kristensen	1960-07-30	16	17	0	not_ready	\N
55	Jørgen Rasmussen	1991-08-02	16	12	0	passed	2019-06-29
56	Rasmus Hansen	1989-07-13	15	19	1	ready	\N
57	Mads Mortensen	1971-09-03	10	14	0	not_ready	\N
58	Kirsten Rasmussen	1981-03-12	12	14	3	ready	\N
59	Gitte Johansen	1964-10-14	1	16	3	not_ready	\N
60	Lone Johansen	1972-07-09	7	15	4	ready	\N
61	Niels Pedersen	1962-04-18	14	20	4	ready	\N
62	Kirsten Mortensen	1996-11-29	10	1	0	not_ready	\N
63	Helle Christiansen	1972-07-19	18	4	0	ready	\N
64	Charlotte Mortensen	1999-01-24	1	3	2	passed	2020-08-23
65	Bente Mortensen	1995-03-22	12	16	0	not_ready	\N
66	Pia Nielsen	1994-12-03	2	3	0	not_ready	\N
67	Stephan Olsen	1955-03-23	12	7	0	not_ready	\N
68	Kirsten Johansen	1986-02-14	11	20	0	ready	\N
69	Helle Jensen	1995-03-04	1	16	0	not_ready	\N
70	Jørgen Sørensen	1991-07-01	3	7	0	not_ready	\N
71	Stephan Jørgensen	1978-02-26	5	11	0	not_ready	\N
72	Pia Jørgensen	1991-10-11	3	2	0	not_ready	\N
73	Ole Christiansen	1956-10-05	17	14	0	not_ready	\N
74	Stephan Poulsen	1963-03-03	8	2	0	not_ready	\N
75	Marianne Hansen	1995-02-20	11	17	0	not_ready	\N
76	Per Jørgensen	1968-11-25	15	1	0	not_ready	\N
77	Pia Thomsen	1976-11-30	9	20	0	not_ready	\N
78	Martin Kristensen	1959-11-27	2	9	4	ready	\N
79	Mads Jørgensen	1991-08-29	9	11	0	not_ready	\N
80	Mette Larsen	1983-06-14	8	5	0	not_ready	\N
81	Niels Jørgensen	1991-12-17	7	15	0	not_ready	\N
82	Charlotte Jensen	1970-12-22	18	20	4	not_ready	\N
83	Jacob Jensen	1979-11-07	10	1	2	passed	2019-02-19
84	Susanne Jensen	1952-11-02	12	19	0	not_ready	\N
85	Jørgen Møller	1974-03-27	12	2	0	not_ready	\N
86	Nikolaj Kristensen	1980-01-05	16	5	0	not_ready	\N
87	Morten Jensen	1975-07-09	15	6	2	not_ready	\N
88	Camilla Jørgensen	1984-10-03	19	9	0	ready	\N
89	Lone Andersen	1969-04-05	3	3	0	not_ready	\N
90	Jørgen Mortensen	1961-11-21	17	20	4	passed	2021-03-29
91	Niels Poulsen	1952-04-06	18	18	1	not_ready	\N
92	Hanne Lindholm	1968-01-13	6	13	0	not_ready	\N
93	Camilla Hansen	1999-09-30	19	14	0	ready	\N
94	Lene Rasmussen	1987-05-25	7	5	0	not_ready	\N
95	Maria Kristensen	1963-03-26	20	9	2	ready	\N
96	Søren Hansen	1990-01-10	12	19	0	not_ready	\N
97	Anna Thomsen	1974-09-07	13	10	0	passed	2021-07-07
98	Karen Rasmussen	1955-12-05	7	17	0	not_ready	\N
99	Jesper Thomsen	1973-04-09	3	16	1	passed	2019-09-04
100	Helle Pedersen	1981-12-08	1	2	0	ready	\N
101	Peter Poulsen	1969-04-17	1	13	0	not_ready	\N
102	Charlotte Madsen	1982-09-24	10	10	0	not_ready	\N
103	Charlotte Jensen	1972-02-25	1	7	0	not_ready	\N
104	Jesper Poulsen	1956-10-09	14	14	0	not_ready	\N
105	Mads Jørgensen	1987-12-13	2	7	0	not_ready	\N
106	Lars Hansen	1994-08-05	17	8	0	not_ready	\N
107	Nikolaj Larsen	1986-01-18	3	5	2	not_ready	\N
108	Pia Thomsen	1964-08-03	16	20	0	not_ready	\N
109	Anna Hansen	1996-09-15	16	13	0	not_ready	\N
110	Tina Olsen	1951-09-24	15	17	0	not_ready	\N
111	Jørgen Larsen	1952-08-01	12	12	0	passed	2021-05-02
112	Kirsten Larsen	1995-12-19	8	18	0	not_ready	\N
113	Jens Sørensen	1963-12-25	4	2	2	passed	2019-11-27
114	Mette Sørensen	1970-09-26	10	5	0	not_ready	\N
115	Pia Thomsen	1992-02-06	1	6	0	not_ready	\N
116	Per Olsen	1981-09-16	14	4	4	ready	\N
117	Gitte Larsen	1972-01-11	16	7	3	ready	\N
118	Inge Jensen	1990-01-09	18	2	0	passed	2020-02-19
119	Daniel Poulsen	1977-02-09	4	14	0	not_ready	\N
120	Camilla Kristensen	1964-04-24	4	3	0	not_ready	\N
121	Pia Mortensen	1979-05-04	14	1	2	passed	2020-12-13
122	Lars Poulsen	1982-09-11	13	7	2	not_ready	\N
123	Charlotte Møller	1980-06-08	4	16	1	passed	2019-06-24
124	Susanne Mortensen	1950-04-18	18	17	0	not_ready	\N
125	Hanne Mortensen	1985-05-11	12	5	3	passed	2020-08-18
126	Jesper Jørgensen	1953-09-19	4	4	0	not_ready	\N
127	Jørgen Lindholm	1979-12-13	9	10	1	not_ready	\N
128	Nikolaj Andersen	1957-12-16	3	20	0	not_ready	\N
129	Michael Johansen	1954-01-07	5	10	0	not_ready	\N
130	Morten Nielsen	1996-06-06	9	1	0	ready	\N
131	Hanne Larsen	1970-08-15	10	1	0	not_ready	\N
132	Martin Mortensen	1995-10-26	1	15	0	not_ready	\N
133	Jens Kristensen	1985-07-09	20	13	0	not_ready	\N
134	Helle Lindholm	1985-05-09	15	8	0	not_ready	\N
135	Louise Møller	1956-09-29	11	15	0	not_ready	\N
136	Daniel Andersen	1978-06-02	13	17	3	not_ready	\N
137	Karen Jørgensen	1986-10-06	9	10	0	not_ready	\N
138	Jan Kristensen	1953-05-21	2	5	0	not_ready	\N
139	Camilla Poulsen	1966-07-04	16	12	0	not_ready	\N
140	Rasmus Larsen	1989-03-25	2	11	0	not_ready	\N
141	Pia Madsen	1998-02-21	4	16	0	not_ready	\N
142	Jan Jørgensen	1990-01-11	1	1	0	not_ready	\N
143	Mads Nielsen	1952-10-06	10	7	0	not_ready	\N
144	Karen Andersen	1958-06-22	20	10	0	not_ready	\N
145	Mette Petersen	1962-11-04	2	6	0	not_ready	\N
146	Camilla Madsen	1996-06-02	2	1	3	passed	2019-05-18
147	Jacob Nielsen	1970-02-03	2	4	0	not_ready	\N
148	Jacob Olsen	1994-09-30	18	19	0	not_ready	\N
149	Anne Sørensen	1995-02-23	19	5	0	not_ready	\N
150	Per Jørgensen	1953-11-14	19	16	0	not_ready	\N
151	Rasmus Petersen	1987-06-16	16	16	3	ready	\N
152	Kirsten Christensen	1981-02-24	15	2	0	not_ready	\N
153	Jacob Johansen	1995-02-13	11	14	0	not_ready	\N
154	Jørgen Olsen	1985-07-11	5	2	0	passed	2020-10-18
155	Tina Jensen	1965-06-02	3	8	0	not_ready	\N
156	Søren Rasmussen	1965-02-11	15	7	0	not_ready	\N
157	Anders Thomsen	1992-07-11	6	19	0	not_ready	\N
158	Søren Pedersen	1985-01-01	15	11	3	passed	2021-10-30
159	Peter Andersen	1993-01-08	12	13	0	not_ready	\N
160	Louise Petersen	1988-06-01	19	8	0	not_ready	\N
161	Martin Kristensen	1970-05-24	19	10	0	not_ready	\N
162	Ole Rasmussen	1969-10-20	6	8	0	not_ready	\N
163	Niels Olsen	1960-11-10	18	16	3	passed	2021-04-02
164	Louise Møller	1990-08-17	6	4	0	not_ready	\N
165	Anna Rasmussen	1979-12-12	6	10	0	not_ready	\N
166	Christian Møller	1964-01-09	10	7	0	not_ready	\N
167	Helle Lindholm	1979-04-22	3	14	0	not_ready	\N
168	Hans Lindholm	1968-12-21	18	19	0	passed	2019-01-29
169	Helle Johansen	1965-04-16	20	10	2	ready	\N
170	Inge Madsen	1979-06-24	8	4	0	not_ready	\N
171	Tina Hansen	1994-03-09	14	4	0	not_ready	\N
172	Jørgen Pedersen	1969-04-13	1	6	0	not_ready	\N
173	Henrik Larsen	1965-11-21	20	14	0	not_ready	\N
174	Marianne Lindholm	1971-05-20	18	5	1	not_ready	\N
175	Ole Christiansen	1955-05-28	16	11	0	not_ready	\N
176	Tina Johansen	1997-03-22	8	12	0	passed	2020-04-08
177	Jesper Sørensen	1954-06-01	13	19	0	not_ready	\N
178	Tina Hansen	1950-06-12	16	18	1	passed	2021-02-13
179	Jacob Nielsen	1960-04-08	7	8	4	passed	2020-10-19
180	Stephan Larsen	1984-03-24	15	12	1	ready	\N
181	Jan Olsen	1968-09-27	7	4	2	not_ready	\N
182	Pia Poulsen	1981-07-16	20	6	0	not_ready	\N
183	Susanne Johansen	1990-02-17	6	15	0	not_ready	\N
184	Stephan Christiansen	1991-09-20	5	14	0	passed	2020-11-15
185	Anne Thomsen	1989-12-29	9	15	0	not_ready	\N
186	Nikolaj Mortensen	1967-05-24	16	9	0	ready	\N
187	Thomas Petersen	1959-02-03	2	20	1	ready	\N
188	Charlotte Olsen	1957-03-16	10	10	0	not_ready	\N
189	Mette Olsen	1961-03-14	2	3	0	passed	2020-03-11
190	Maria Poulsen	1979-04-17	17	5	1	ready	\N
191	Susanne Nielsen	1993-11-08	7	2	0	not_ready	\N
192	Inge Larsen	1978-09-23	10	8	0	not_ready	\N
193	Rasmus Nielsen	1950-11-21	18	20	0	not_ready	\N
194	Hans Johansen	1968-07-05	1	4	0	not_ready	\N
195	Morten Nielsen	1965-04-02	10	12	0	not_ready	\N
196	Jan Petersen	1963-10-24	16	13	0	ready	\N
197	Rasmus Jensen	1961-09-23	4	6	0	not_ready	\N
198	Jan Rasmussen	1977-10-26	14	9	0	not_ready	\N
199	Jesper Rasmussen	1989-10-07	12	4	0	not_ready	\N
200	Marianne Jørgensen	1993-06-26	20	16	0	not_ready	\N
201	Pia Rasmussen	1992-07-16	13	4	0	not_ready	\N
202	Jacob Rasmussen	1981-01-09	20	17	1	ready	\N
203	Martin Madsen	1994-11-20	11	12	0	not_ready	\N
204	Jørgen Kristensen	1993-09-29	8	11	2	ready	\N
205	Stephan Jensen	1959-11-13	19	5	0	not_ready	\N
206	Jørgen Nielsen	1960-05-26	8	20	0	not_ready	\N
207	Michael Andersen	1982-03-13	18	18	4	ready	\N
208	Anders Jensen	1972-06-29	11	17	0	not_ready	\N
209	Susanne Olsen	1957-01-26	17	16	0	not_ready	\N
210	Rasmus Petersen	1976-03-26	7	20	1	ready	\N
211	Rasmus Thomsen	1993-03-26	18	17	0	not_ready	\N
212	Anders Larsen	1993-11-25	6	5	0	not_ready	\N
213	Morten Hansen	1972-10-29	17	5	0	not_ready	\N
214	Rasmus Olsen	1973-01-30	4	5	0	not_ready	\N
215	Tina Nielsen	1956-05-12	13	10	0	passed	2021-09-07
216	Jesper Nielsen	1971-02-14	1	9	0	not_ready	\N
217	Marianne Hansen	1998-09-23	18	13	0	not_ready	\N
218	Niels Christiansen	1986-06-21	4	1	4	passed	2019-05-16
219	Thomas Poulsen	1965-09-07	6	4	0	not_ready	\N
220	Bente Olsen	1989-11-27	15	5	0	not_ready	\N
221	Mads Sørensen	1977-12-20	16	9	3	passed	2019-12-20
222	Bente Johansen	1986-09-02	4	3	3	ready	\N
223	Martin Andersen	1966-07-22	12	6	3	passed	2020-07-05
224	Anne Rasmussen	1957-04-20	11	9	0	not_ready	\N
225	Karen Rasmussen	1950-12-29	14	19	2	not_ready	\N
226	Jens Lindholm	1979-03-27	16	10	4	passed	2020-03-25
227	Camilla Rasmussen	1968-08-08	5	7	0	not_ready	\N
228	Susanne Nielsen	1994-08-15	11	5	0	not_ready	\N
229	Anna Johansen	1991-10-16	6	9	0	not_ready	\N
230	Anna Thomsen	1975-05-06	6	16	0	not_ready	\N
231	Mette Madsen	1978-10-03	6	7	4	ready	\N
232	Søren Larsen	1963-06-04	2	8	0	not_ready	\N
233	Michael Thomsen	1995-10-14	17	8	3	passed	2020-09-27
234	Marianne Jensen	1991-09-19	3	17	0	not_ready	\N
235	Bente Petersen	1954-04-29	8	9	0	not_ready	\N
236	Anna Jørgensen	1971-12-11	4	8	0	not_ready	\N
237	Lone Kristensen	1994-02-19	7	14	0	not_ready	\N
238	Peter Poulsen	1979-07-21	2	5	2	passed	2020-05-29
239	Nikolaj Petersen	1985-07-07	19	12	0	not_ready	\N
240	Louise Christensen	1970-01-06	20	2	0	not_ready	\N
241	Peter Rasmussen	1974-03-01	12	9	3	ready	\N
242	Jan Andersen	1953-08-27	19	18	2	ready	\N
243	Christian Christiansen	1969-03-15	6	18	0	not_ready	\N
244	Hans Jensen	1998-09-10	16	8	0	not_ready	\N
245	Ole Christiansen	1965-09-09	16	9	0	not_ready	\N
246	Camilla Kristensen	1975-10-01	16	19	0	not_ready	\N
247	Daniel Petersen	1988-02-08	9	20	0	not_ready	\N
248	Mette Petersen	1957-12-29	8	4	2	ready	\N
249	Henrik Johansen	1966-02-11	6	13	0	not_ready	\N
250	Jesper Jørgensen	1966-10-08	1	12	0	not_ready	\N
251	Thomas Christiansen	1984-11-10	2	2	0	not_ready	\N
252	Tina Madsen	1972-06-15	15	13	0	not_ready	\N
253	Marianne Nielsen	1984-06-13	9	7	3	ready	\N
254	Christian Jensen	1989-06-28	1	13	0	not_ready	\N
255	Susanne Møller	1987-04-20	20	8	0	not_ready	\N
256	Michael Jørgensen	1969-12-29	20	6	0	not_ready	\N
257	Susanne Sørensen	1960-02-14	11	16	0	not_ready	\N
258	Marianne Christiansen	1950-07-09	17	1	1	ready	\N
259	Ole Rasmussen	1989-04-27	13	15	0	not_ready	\N
260	Niels Madsen	1995-05-05	13	16	0	not_ready	\N
261	Anna Larsen	1999-12-12	13	4	0	not_ready	\N
262	Daniel Madsen	1988-11-16	6	6	0	not_ready	\N
263	Marianne Olsen	1975-03-11	13	7	4	not_ready	\N
264	Daniel Poulsen	1969-05-16	20	10	0	not_ready	\N
265	Jan Madsen	1993-12-27	8	12	1	passed	2020-06-02
266	Morten Larsen	1995-04-06	8	18	0	not_ready	\N
267	Daniel Jensen	1969-04-07	16	20	0	not_ready	\N
268	Christian Larsen	1969-07-22	16	10	0	passed	2019-01-04
269	Lars Thomsen	1986-08-26	17	10	0	not_ready	\N
270	Thomas Nielsen	1985-05-05	4	19	0	not_ready	\N
271	Anna Jørgensen	1974-03-20	20	1	0	not_ready	\N
272	Marianne Christensen	1980-07-13	15	18	0	not_ready	\N
273	Lone Lindholm	1974-09-09	4	12	0	not_ready	\N
274	Peter Petersen	1990-06-18	12	19	3	passed	2021-07-21
275	Camilla Nielsen	1992-06-06	20	9	1	ready	\N
276	Nikolaj Poulsen	1985-01-09	9	9	0	not_ready	\N
277	Søren Lindholm	1969-08-09	14	10	0	not_ready	\N
278	Jørgen Lindholm	1982-08-15	8	13	1	ready	\N
279	Hans Petersen	1956-03-19	3	6	0	not_ready	\N
280	Christian Petersen	1997-02-16	20	1	2	passed	2019-02-05
281	Ole Thomsen	1973-11-25	10	4	0	not_ready	\N
282	Michael Kristensen	1993-03-22	3	10	3	passed	2019-10-26
283	Mette Sørensen	1958-03-19	5	2	0	not_ready	\N
284	Inge Rasmussen	1988-07-04	1	2	4	ready	\N
285	Jens Madsen	1993-08-28	20	7	0	not_ready	\N
286	Jacob Johansen	1995-11-20	13	10	2	not_ready	\N
287	Michael Pedersen	1975-09-23	20	2	2	passed	2019-09-21
288	Per Andersen	1974-04-06	10	13	0	not_ready	\N
289	Stephan Kristensen	1998-11-21	4	7	2	passed	2020-09-07
290	Niels Christensen	1963-01-18	14	7	2	not_ready	\N
291	Martin Madsen	1969-06-13	15	10	0	not_ready	\N
292	Jørgen Mortensen	1973-08-15	17	5	0	not_ready	\N
293	Stephan Jensen	1982-08-29	9	10	0	not_ready	\N
294	Christian Andersen	1982-10-23	18	9	4	passed	2021-08-27
295	Gitte Andersen	1985-03-03	17	7	0	not_ready	\N
296	Thomas Madsen	1992-10-29	11	6	0	not_ready	\N
297	Stephan Andersen	1971-02-10	3	18	2	passed	2021-05-27
298	Morten Kristensen	1976-02-16	11	5	4	ready	\N
299	Jan Madsen	1996-12-29	2	20	0	not_ready	\N
300	Lone Rasmussen	1985-10-03	4	2	2	passed	2019-06-29
301	Gitte Madsen	1973-05-10	9	8	2	passed	2020-06-09
302	Pia Nielsen	1971-02-02	11	8	0	not_ready	\N
303	Morten Johansen	1991-05-03	10	9	0	not_ready	\N
304	Anne Mortensen	1957-03-21	11	6	4	ready	\N
305	Søren Lindholm	1969-12-16	11	17	0	not_ready	\N
306	Daniel Jensen	1995-05-23	17	15	4	ready	\N
307	Stephan Poulsen	1951-11-22	20	5	0	ready	\N
308	Jan Hansen	1988-11-13	6	1	4	ready	\N
309	Bente Poulsen	1986-10-05	18	6	4	passed	2019-04-20
310	Anna Nielsen	1977-09-03	9	8	0	not_ready	\N
311	Stephan Kristensen	1991-01-02	9	6	0	not_ready	\N
312	Camilla Hansen	1994-02-02	12	1	2	not_ready	\N
313	Jørgen Johansen	1987-11-02	5	6	0	not_ready	\N
314	Tina Olsen	1999-04-27	13	14	4	ready	\N
315	Ole Jørgensen	1961-03-05	3	11	2	ready	\N
316	Gitte Mortensen	1961-04-23	2	18	4	ready	\N
317	Anders Møller	1952-10-13	17	17	2	not_ready	\N
318	Stephan Møller	1996-02-24	14	4	0	not_ready	\N
319	Søren Hansen	1995-06-01	3	10	0	not_ready	\N
320	Jesper Johansen	1983-02-13	9	12	0	not_ready	\N
321	Michael Petersen	1952-12-06	11	13	0	not_ready	\N
322	Thomas Mortensen	1969-12-20	18	14	0	not_ready	\N
323	Anders Johansen	1992-03-14	14	5	0	not_ready	\N
324	Michael Poulsen	1975-10-04	1	5	0	not_ready	\N
325	Nikolaj Rasmussen	1959-02-27	15	1	0	ready	\N
326	Thomas Jensen	1963-07-11	11	15	0	not_ready	\N
327	Michael Pedersen	1951-10-02	8	17	0	not_ready	\N
328	Camilla Johansen	1986-10-27	17	2	0	not_ready	\N
329	Michael Lindholm	1984-09-08	4	7	0	ready	\N
330	Hanne Lindholm	1982-09-15	10	1	0	passed	2018-12-01
331	Louise Christensen	1966-10-07	10	12	1	passed	2019-05-06
332	Niels Kristensen	1992-01-30	1	4	0	not_ready	\N
333	Marianne Mortensen	1983-08-11	2	13	1	ready	\N
334	Ole Jensen	1988-11-26	12	16	0	ready	\N
335	Anne Jensen	1991-06-28	2	9	2	ready	\N
336	Marianne Andersen	1964-05-11	1	15	0	not_ready	\N
337	Tina Larsen	1995-08-15	4	2	1	passed	2020-12-08
338	Per Møller	1969-11-09	5	8	0	not_ready	\N
339	Thomas Hansen	1969-04-25	11	11	0	not_ready	\N
340	Louise Andersen	1963-02-25	17	2	1	passed	2020-02-15
341	Anna Sørensen	1971-02-02	14	18	0	not_ready	\N
342	Karen Olsen	1976-05-02	10	16	0	not_ready	\N
343	Søren Johansen	1991-06-16	8	20	0	not_ready	\N
344	Karen Hansen	1975-02-06	6	13	0	not_ready	\N
345	Tina Thomsen	1952-01-15	12	5	0	not_ready	\N
346	Søren Møller	1979-02-27	16	7	0	not_ready	\N
347	Rasmus Pedersen	1985-12-30	18	14	0	not_ready	\N
348	Ole Hansen	1997-08-21	20	20	0	not_ready	\N
349	Anne Hansen	1970-03-17	2	7	0	not_ready	\N
350	Karen Christensen	1957-05-29	14	6	0	not_ready	\N
351	Niels Jørgensen	1958-11-01	4	1	3	ready	\N
352	Christian Pedersen	1985-11-20	13	5	1	not_ready	\N
353	Maria Petersen	1966-10-22	16	9	3	passed	2019-08-04
354	Søren Hansen	1973-12-30	16	14	0	not_ready	\N
355	Daniel Rasmussen	1988-06-25	11	11	0	not_ready	\N
356	Anders Kristensen	1968-07-10	4	4	0	not_ready	\N
357	Christian Jørgensen	1974-05-06	8	5	1	not_ready	\N
358	Peter Mortensen	1983-03-22	13	19	0	not_ready	\N
359	Mads Johansen	1999-02-09	17	16	0	ready	\N
360	Helle Madsen	1982-12-13	7	4	0	not_ready	\N
361	Anna Jørgensen	1969-01-18	10	5	1	passed	2020-06-17
362	Daniel Kristensen	1987-10-01	7	16	0	not_ready	\N
363	Jens Lindholm	1983-05-13	9	1	4	passed	2020-11-20
364	Helle Christiansen	1995-04-02	3	15	3	passed	2021-04-21
365	Inge Møller	1968-03-26	13	12	0	not_ready	\N
366	Thomas Sørensen	1999-08-09	3	7	0	not_ready	\N
367	Inge Mortensen	1961-06-23	1	18	4	ready	\N
368	Anders Thomsen	1974-10-15	11	12	0	not_ready	\N
369	Jens Johansen	1987-01-02	10	17	2	ready	\N
370	Lone Christiansen	1960-01-09	18	2	0	not_ready	\N
371	Charlotte Christensen	1992-03-05	1	3	4	passed	2019-06-15
372	Daniel Lindholm	1997-05-26	3	20	4	not_ready	\N
373	Hans Lindholm	1984-04-23	13	6	0	not_ready	\N
374	Morten Madsen	1955-11-05	4	6	0	not_ready	\N
375	Morten Jensen	1968-06-01	14	6	0	passed	2021-02-15
376	Niels Larsen	1958-01-28	6	4	4	passed	2019-11-24
377	Daniel Møller	1966-10-18	5	7	0	not_ready	\N
378	Jacob Nielsen	1972-02-10	3	11	4	passed	2020-09-12
379	Kirsten Christiansen	1974-04-23	20	14	0	not_ready	\N
380	Rasmus Hansen	1992-03-06	3	15	0	passed	2021-05-29
381	Søren Olsen	1961-01-23	9	12	0	not_ready	\N
382	Inge Madsen	1966-06-09	17	9	2	passed	2021-11-30
383	Niels Petersen	1987-06-05	18	4	0	not_ready	\N
384	Susanne Thomsen	1989-07-05	17	8	0	not_ready	\N
385	Pia Lindholm	1952-01-24	19	16	2	ready	\N
386	Mette Lindholm	1953-08-15	5	1	2	ready	\N
387	Henrik Christensen	1974-10-18	14	8	3	passed	2019-12-17
388	Nikolaj Mortensen	1992-04-15	3	20	0	not_ready	\N
389	Inge Petersen	1985-10-23	9	6	4	ready	\N
390	Peter Larsen	1950-06-30	2	15	0	not_ready	\N
391	Tina Møller	1965-12-16	6	5	0	not_ready	\N
392	Gitte Jensen	1976-11-05	2	12	0	not_ready	\N
393	Kirsten Olsen	1975-02-03	6	7	0	not_ready	\N
394	Daniel Andersen	1992-12-18	12	12	0	not_ready	\N
395	Anne Pedersen	1972-04-17	15	1	2	ready	\N
396	Inge Pedersen	1982-12-16	20	19	0	not_ready	\N
397	Gitte Christensen	1971-10-04	13	12	0	not_ready	\N
398	Anna Mortensen	1969-02-02	19	8	0	not_ready	\N
399	Louise Rasmussen	1980-03-22	19	19	3	ready	\N
400	Gitte Christensen	1991-01-07	8	19	0	not_ready	\N
401	Pia Thomsen	1954-09-01	20	3	0	not_ready	\N
402	Stephan Petersen	1989-07-05	1	14	0	passed	2020-02-27
403	Bente Mortensen	1951-01-05	11	17	0	not_ready	\N
404	Michael Hansen	1997-11-18	12	16	0	not_ready	\N
405	Per Kristensen	1970-09-30	13	15	0	not_ready	\N
406	Peter Rasmussen	1976-02-18	20	1	0	not_ready	\N
407	Camilla Christensen	1951-03-25	16	14	0	not_ready	\N
408	Marianne Christensen	1959-08-06	20	20	0	not_ready	\N
409	Bente Rasmussen	1958-03-08	13	3	2	ready	\N
410	Søren Kristensen	1965-01-06	20	1	0	not_ready	\N
411	Lone Christiansen	1988-02-04	19	20	0	not_ready	\N
412	Jens Larsen	1992-10-18	10	6	0	not_ready	\N
413	Michael Nielsen	1970-02-22	9	20	0	not_ready	\N
414	Jens Jensen	1977-10-13	5	14	2	ready	\N
415	Charlotte Poulsen	1991-03-12	20	6	0	not_ready	\N
416	Stephan Hansen	1958-10-11	14	17	0	not_ready	\N
417	Jørgen Rasmussen	1989-06-19	16	10	2	ready	\N
418	Camilla Olsen	1995-07-25	7	13	0	not_ready	\N
419	Søren Jensen	1994-05-20	2	2	2	ready	\N
420	Christian Jørgensen	1988-07-04	15	15	0	not_ready	\N
421	Kirsten Rasmussen	1961-02-25	6	15	0	not_ready	\N
422	Anne Johansen	1996-12-17	9	12	0	not_ready	\N
423	Daniel Madsen	1976-05-29	7	2	0	passed	2019-04-16
424	Karen Møller	1968-11-25	5	16	0	not_ready	\N
425	Karen Petersen	1993-04-19	17	3	1	not_ready	\N
426	Jens Kristensen	1986-02-21	14	9	4	passed	2020-11-30
427	Stephan Andersen	1952-02-09	14	5	0	not_ready	\N
428	Jesper Andersen	1992-09-09	19	7	0	not_ready	\N
429	Bente Jørgensen	1993-03-24	1	8	4	ready	\N
430	Louise Rasmussen	1999-09-06	20	11	0	not_ready	\N
431	Stephan Hansen	1954-06-03	17	8	0	not_ready	\N
432	Morten Olsen	1984-09-28	12	12	1	passed	2021-03-01
433	Susanne Mortensen	1996-06-17	12	13	0	not_ready	\N
434	Søren Mortensen	1953-02-03	12	3	2	ready	\N
435	Jacob Pedersen	1980-04-16	17	8	0	not_ready	\N
436	Peter Jørgensen	1992-11-26	5	12	3	ready	\N
437	Susanne Hansen	1952-02-25	10	1	0	ready	\N
438	Anna Mortensen	1982-08-14	2	1	0	not_ready	\N
439	Lene Petersen	1979-05-04	7	14	0	not_ready	\N
440	Thomas Mortensen	1974-10-20	4	7	1	not_ready	\N
441	Stephan Christensen	1974-09-30	9	14	0	not_ready	\N
442	Bente Christiansen	1981-01-18	16	9	0	not_ready	\N
443	Peter Mortensen	1959-09-21	3	1	3	ready	\N
444	Ole Pedersen	1998-05-07	11	6	0	not_ready	\N
445	Mads Sørensen	1995-02-25	1	17	3	ready	\N
446	Peter Madsen	1963-11-13	3	2	0	not_ready	\N
447	Mads Hansen	1958-07-26	18	13	0	not_ready	\N
448	Tina Jørgensen	1964-07-13	4	16	3	passed	2020-05-19
449	Jan Hansen	1964-05-30	10	1	0	not_ready	\N
450	Louise Petersen	1981-11-24	7	17	0	passed	2019-11-29
451	Charlotte Møller	1981-02-06	14	13	4	passed	2021-08-09
452	Gitte Hansen	1951-07-02	6	16	0	not_ready	\N
453	Thomas Møller	1980-04-29	5	17	0	not_ready	\N
454	Hans Christensen	1999-12-09	11	20	0	passed	2019-07-06
455	Hans Lindholm	1994-10-15	18	7	0	not_ready	\N
456	Ole Hansen	1993-09-14	15	1	0	passed	2021-04-25
457	Daniel Rasmussen	1960-02-27	4	10	0	not_ready	\N
458	Pia Sørensen	1953-03-26	7	13	0	not_ready	\N
459	Jens Mortensen	1963-03-09	7	17	1	passed	2019-12-26
460	Michael Mortensen	1981-11-21	11	6	0	not_ready	\N
461	Morten Hansen	1964-10-08	2	8	4	passed	2018-12-22
462	Søren Sørensen	1952-03-20	2	18	0	not_ready	\N
463	Marianne Mortensen	1969-07-01	15	9	4	passed	2019-01-20
464	Michael Thomsen	1972-04-22	14	4	0	not_ready	\N
465	Stephan Lindholm	1981-02-26	17	18	0	not_ready	\N
466	Mads Jørgensen	1985-06-12	10	8	0	not_ready	\N
467	Jan Jensen	1951-01-28	15	15	0	not_ready	\N
468	Michael Rasmussen	1961-02-02	19	14	2	ready	\N
469	Michael Pedersen	1962-02-24	1	9	0	not_ready	\N
470	Lene Rasmussen	1996-06-06	7	2	0	not_ready	\N
471	Thomas Kristensen	1968-05-20	18	12	3	passed	2021-05-18
472	Lone Jørgensen	1985-04-08	3	1	0	not_ready	\N
473	Tina Sørensen	1956-03-26	7	12	0	ready	\N
474	Nikolaj Lindholm	1984-10-14	5	20	0	not_ready	\N
475	Anna Thomsen	1982-09-28	13	4	0	not_ready	\N
476	Mads Nielsen	1975-11-09	2	15	0	not_ready	\N
477	Jacob Andersen	1978-03-30	4	9	0	passed	2020-07-30
478	Pia Jørgensen	1964-05-04	7	4	0	not_ready	\N
479	Marianne Rasmussen	1950-10-09	12	17	3	passed	2019-06-05
480	Søren Johansen	1964-05-21	9	4	0	passed	2020-05-08
481	Ole Thomsen	1966-11-12	10	20	2	ready	\N
482	Anne Sørensen	1978-07-28	14	19	3	passed	2021-04-01
483	Susanne Møller	1964-05-23	5	9	0	not_ready	\N
484	Mads Larsen	1977-01-22	4	18	4	ready	\N
485	Kirsten Christensen	1999-12-24	18	18	0	passed	2020-12-29
486	Anne Christensen	1959-03-12	17	14	0	not_ready	\N
487	Nikolaj Madsen	1986-12-10	5	19	0	not_ready	\N
488	Louise Jørgensen	1962-04-20	11	9	1	not_ready	\N
489	Per Johansen	1965-01-02	18	19	0	not_ready	\N
490	Hans Poulsen	1972-07-28	15	6	0	not_ready	\N
491	Pia Madsen	1970-08-01	15	5	0	passed	2020-06-28
492	Karen Jørgensen	1987-04-28	7	19	0	not_ready	\N
493	Søren Lindholm	1958-08-28	10	13	0	not_ready	\N
494	Martin Lindholm	1952-03-25	20	20	0	not_ready	\N
495	Nikolaj Hansen	1993-07-11	14	5	0	not_ready	\N
496	Anna Christensen	1968-09-05	5	1	2	ready	\N
497	Per Thomsen	1995-07-23	18	7	0	not_ready	\N
498	Anders Mortensen	1959-02-16	3	17	1	ready	\N
499	Anne Andersen	1981-02-21	10	9	3	passed	2020-11-03
500	Karen Olsen	1965-11-02	3	4	0	not_ready	\N
501	Susanne Madsen	1958-12-28	3	8	1	ready	\N
502	Lars Andersen	1963-12-08	11	2	0	not_ready	\N
503	Rasmus Poulsen	1987-03-12	3	18	0	not_ready	\N
504	Camilla Johansen	1989-09-25	7	14	0	not_ready	\N
505	Jesper Jørgensen	1955-12-06	18	12	0	not_ready	\N
506	Maria Hansen	1984-01-17	9	16	0	not_ready	\N
507	Jørgen Hansen	1989-01-14	19	18	0	not_ready	\N
508	Marianne Rasmussen	1999-03-11	12	11	0	not_ready	\N
509	Susanne Olsen	1991-10-23	6	5	0	not_ready	\N
510	Peter Pedersen	1965-08-23	17	12	0	not_ready	\N
511	Pia Thomsen	1969-07-28	5	11	0	not_ready	\N
512	Lars Lindholm	1973-09-09	16	11	0	ready	\N
513	Tina Hansen	1960-04-22	3	3	2	ready	\N
514	Jørgen Madsen	1991-01-30	13	9	0	not_ready	\N
515	Jesper Johansen	1980-09-26	20	2	0	not_ready	\N
516	Lars Christensen	1960-03-06	10	8	0	not_ready	\N
517	Stephan Johansen	1965-11-06	7	9	0	not_ready	\N
518	Jacob Christensen	1990-01-10	4	16	0	not_ready	\N
519	Christian Nielsen	1980-06-05	2	18	0	not_ready	\N
520	Per Nielsen	1972-08-03	7	3	0	not_ready	\N
521	Niels Thomsen	1971-11-09	5	11	1	passed	2021-07-28
522	Hans Poulsen	1994-04-14	19	17	0	not_ready	\N
523	Lars Poulsen	1977-07-19	6	16	2	ready	\N
524	Anders Christiansen	1961-04-09	3	1	0	not_ready	\N
525	Hanne Madsen	1999-09-18	7	11	0	not_ready	\N
526	Marianne Madsen	1958-09-12	8	7	2	ready	\N
527	Bente Mortensen	1994-02-03	6	18	0	not_ready	\N
528	Daniel Olsen	1974-07-18	11	16	0	not_ready	\N
529	Ole Jensen	1999-09-29	17	19	2	ready	\N
530	Morten Olsen	1974-03-13	7	19	0	not_ready	\N
531	Martin Christensen	1959-03-07	11	16	0	not_ready	\N
532	Mette Olsen	1969-04-05	15	14	0	not_ready	\N
533	Hanne Johansen	1956-01-12	12	16	0	not_ready	\N
534	Gitte Christensen	1956-06-07	18	8	0	ready	\N
535	Marianne Møller	1950-07-22	20	4	3	passed	2020-09-10
536	Helle Nielsen	1983-09-04	13	10	2	ready	\N
537	Mette Sørensen	1995-05-29	8	10	0	not_ready	\N
538	Pia Johansen	1998-08-13	17	9	0	not_ready	\N
539	Morten Rasmussen	1956-01-26	13	9	2	ready	\N
540	Charlotte Rasmussen	1989-04-19	3	4	1	ready	\N
541	Christian Jensen	1992-04-04	17	12	0	not_ready	\N
542	Kirsten Johansen	1956-07-22	2	4	1	ready	\N
543	Nikolaj Christensen	1950-02-20	2	14	1	passed	2021-04-26
544	Morten Christensen	1956-08-18	19	4	0	not_ready	\N
545	Anders Johansen	1981-05-15	10	11	0	not_ready	\N
546	Per Pedersen	1954-06-05	8	13	0	not_ready	\N
547	Christian Madsen	1971-12-21	20	17	0	not_ready	\N
548	Nikolaj Thomsen	1960-06-10	12	19	4	passed	2020-01-28
549	Camilla Hansen	1983-11-06	15	16	0	passed	2019-04-19
550	Lone Petersen	1956-09-07	18	14	0	not_ready	\N
551	Daniel Jensen	1962-10-21	11	1	0	not_ready	\N
552	Stephan Madsen	1984-03-26	2	18	3	passed	2019-09-20
553	Peter Christensen	1963-10-20	5	20	2	passed	2021-07-16
554	Pia Hansen	1956-04-02	9	16	0	not_ready	\N
555	Nikolaj Christensen	1953-04-16	10	8	0	not_ready	\N
556	Michael Olsen	1977-05-14	16	3	3	passed	2020-03-20
557	Rasmus Jørgensen	1977-12-24	5	1	4	passed	2021-08-29
558	Peter Hansen	1959-01-06	11	9	0	not_ready	\N
559	Pia Mortensen	1998-10-14	3	9	0	not_ready	\N
560	Camilla Petersen	1988-10-27	13	16	0	not_ready	\N
561	Anne Sørensen	1979-04-01	5	6	3	passed	2020-11-16
562	Inge Pedersen	1962-03-20	11	15	1	not_ready	\N
563	Pia Møller	1976-02-23	11	7	0	ready	\N
564	Rasmus Christiansen	1981-09-09	18	4	0	ready	\N
565	Kirsten Sørensen	1996-09-13	1	9	4	passed	2020-03-19
566	Lone Nielsen	1991-04-30	18	2	3	ready	\N
567	Hanne Poulsen	1956-05-01	9	14	3	ready	\N
568	Christian Thomsen	1978-06-24	9	18	4	ready	\N
569	Daniel Mortensen	1986-01-15	12	7	4	ready	\N
570	Hanne Møller	1957-11-09	10	6	3	not_ready	\N
571	Rasmus Hansen	1957-07-07	13	7	0	not_ready	\N
572	Bente Johansen	1994-07-26	17	6	0	not_ready	\N
573	Hanne Madsen	1957-07-17	14	3	4	passed	2021-05-02
574	Camilla Thomsen	1965-02-07	14	14	0	not_ready	\N
575	Mette Hansen	1970-10-09	2	15	0	not_ready	\N
576	Per Lindholm	1986-02-22	14	7	0	not_ready	\N
577	Louise Thomsen	1958-06-21	12	20	0	not_ready	\N
578	Gitte Christiansen	1975-04-16	3	5	0	not_ready	\N
579	Jacob Lindholm	1962-12-13	11	3	1	passed	2020-05-28
580	Peter Hansen	1977-11-22	16	19	4	ready	\N
581	Tina Møller	1979-10-27	17	13	2	ready	\N
582	Lars Hansen	1983-12-22	10	13	0	not_ready	\N
583	Camilla Jensen	1998-01-24	17	9	4	passed	2021-11-07
584	Helle Christensen	1987-08-18	17	10	1	passed	2020-01-23
585	Lone Pedersen	1968-06-11	5	9	0	not_ready	\N
586	Lars Mortensen	1994-03-03	8	15	0	not_ready	\N
587	Jørgen Petersen	1951-09-19	12	19	0	not_ready	\N
588	Jacob Jørgensen	1972-01-19	18	13	0	not_ready	\N
589	Jesper Kristensen	1965-08-14	19	10	0	not_ready	\N
590	Henrik Pedersen	1989-05-25	11	19	0	not_ready	\N
591	Susanne Johansen	1967-11-08	20	7	3	ready	\N
592	Lene Sørensen	1952-05-08	4	6	0	not_ready	\N
593	Karen Møller	1974-06-14	6	17	0	ready	\N
594	Jacob Larsen	1972-05-30	20	11	0	not_ready	\N
595	Hans Lindholm	1967-04-09	16	1	4	passed	2020-04-01
596	Charlotte Pedersen	1990-07-03	15	6	0	not_ready	\N
597	Mads Petersen	1994-07-23	5	7	0	not_ready	\N
598	Morten Pedersen	1955-09-15	1	15	1	passed	2021-05-24
599	Pia Larsen	1967-02-02	17	20	0	not_ready	\N
600	Thomas Lindholm	1951-08-20	17	13	0	not_ready	\N
601	Jesper Rasmussen	1950-12-17	15	8	0	not_ready	\N
602	Søren Olsen	1973-09-13	8	13	0	not_ready	\N
603	Mette Sørensen	1986-04-24	15	3	3	not_ready	\N
604	Hans Kristensen	1975-11-12	16	9	0	not_ready	\N
605	Inge Christiansen	1964-03-08	5	4	0	not_ready	\N
606	Kirsten Thomsen	1998-01-03	20	5	1	passed	2021-03-27
607	Mette Mortensen	1991-06-11	7	18	0	not_ready	\N
608	Jens Thomsen	1965-01-04	3	14	0	not_ready	\N
609	Marianne Johansen	1980-12-14	11	12	3	passed	2018-12-22
610	Hanne Christensen	1991-12-28	13	18	0	not_ready	\N
611	Marianne Lindholm	1959-11-30	4	3	1	not_ready	\N
612	Lene Christiansen	1976-11-12	9	10	0	not_ready	\N
613	Lene Møller	1954-01-19	18	7	2	not_ready	\N
614	Lone Madsen	1979-06-10	13	9	1	passed	2021-01-29
615	Maria Johansen	1951-01-05	5	6	3	ready	\N
616	Louise Andersen	1962-10-15	4	8	0	not_ready	\N
617	Lone Hansen	1963-04-25	4	20	0	not_ready	\N
618	Henrik Christiansen	1956-04-04	8	16	0	not_ready	\N
619	Stephan Petersen	1959-06-25	1	9	0	passed	2019-12-24
620	Karen Madsen	1993-12-25	13	17	4	ready	\N
621	Susanne Christensen	1969-11-11	12	10	0	not_ready	\N
622	Karen Christiansen	1999-09-28	16	12	0	not_ready	\N
623	Rasmus Rasmussen	1950-09-07	18	4	0	not_ready	\N
624	Jørgen Christensen	1981-11-23	3	2	0	not_ready	\N
625	Martin Jensen	1999-12-01	5	4	2	ready	\N
626	Bente Thomsen	1975-07-30	7	19	0	not_ready	\N
627	Anna Nielsen	1950-10-05	5	9	0	not_ready	\N
628	Susanne Jensen	1972-01-15	13	4	0	not_ready	\N
629	Jørgen Christensen	1953-04-23	19	17	1	ready	\N
630	Per Thomsen	1959-04-26	20	20	0	not_ready	\N
631	Peter Madsen	1953-08-11	20	1	0	not_ready	\N
632	Kirsten Johansen	1954-04-04	18	10	0	not_ready	\N
633	Maria Christiansen	1958-06-25	16	3	0	not_ready	\N
634	Karen Sørensen	1955-06-23	10	3	3	not_ready	\N
635	Daniel Jensen	1953-02-08	8	10	3	passed	2021-01-05
636	Niels Andersen	1978-02-10	9	13	0	not_ready	\N
637	Charlotte Christensen	1989-11-30	18	2	3	passed	2021-08-01
638	Jørgen Jensen	1951-02-01	16	1	3	ready	\N
639	Søren Christiansen	1993-04-09	5	14	0	not_ready	\N
640	Louise Nielsen	1962-06-05	7	1	0	not_ready	\N
641	Marianne Pedersen	1955-10-07	6	15	0	not_ready	\N
642	Christian Johansen	1972-02-11	15	12	3	passed	2019-10-30
643	Mette Thomsen	1974-02-24	4	17	0	not_ready	\N
644	Anne Kristensen	1990-06-26	1	12	0	not_ready	\N
645	Michael Mortensen	1978-02-08	20	3	0	not_ready	\N
646	Niels Jensen	1974-09-06	15	19	2	passed	2021-02-17
647	Louise Møller	1962-02-01	9	11	0	not_ready	\N
648	Bente Jørgensen	1969-10-28	5	3	0	not_ready	\N
649	Helle Lindholm	1992-08-06	10	20	0	not_ready	\N
650	Hans Christensen	1999-02-03	19	4	3	passed	2019-10-19
651	Bente Thomsen	1997-06-14	6	19	1	passed	2020-07-18
652	Hanne Olsen	1988-11-09	14	19	0	not_ready	\N
653	Bente Jensen	1985-06-23	13	5	0	not_ready	\N
654	Jesper Poulsen	1991-02-18	14	12	4	passed	2019-11-01
655	Inge Rasmussen	1966-11-19	17	8	0	ready	\N
656	Hans Møller	1960-04-27	9	8	0	not_ready	\N
657	Inge Sørensen	1985-10-18	2	2	0	not_ready	\N
658	Helle Jensen	1967-12-18	3	3	0	not_ready	\N
659	Jørgen Christensen	1967-05-27	1	10	0	not_ready	\N
660	Louise Thomsen	1964-04-17	5	18	2	ready	\N
661	Nikolaj Jørgensen	1997-10-18	4	20	0	not_ready	\N
662	Lone Sørensen	1996-09-09	1	4	2	ready	\N
663	Anne Mortensen	1950-06-17	11	17	0	passed	2020-07-24
664	Kirsten Møller	1952-07-13	11	11	0	not_ready	\N
665	Hanne Mortensen	1983-04-09	1	8	0	not_ready	\N
666	Mette Pedersen	1964-02-15	13	16	0	not_ready	\N
667	Jacob Lindholm	1958-01-08	5	20	0	not_ready	\N
668	Anna Sørensen	1956-04-07	3	15	2	ready	\N
669	Helle Møller	1998-07-15	13	1	0	not_ready	\N
670	Jens Jørgensen	1987-11-02	14	14	0	not_ready	\N
671	Thomas Madsen	1979-05-14	12	3	0	not_ready	\N
672	Jørgen Madsen	1990-01-09	15	14	3	ready	\N
673	Tina Hansen	1963-05-01	1	15	0	not_ready	\N
674	Lene Jensen	1986-07-13	11	18	1	ready	\N
675	Helle Andersen	1977-08-09	16	8	0	not_ready	\N
676	Pia Johansen	1997-03-20	19	14	1	ready	\N
677	Inge Kristensen	1982-06-15	1	14	4	ready	\N
678	Lone Poulsen	1952-02-23	7	14	3	passed	2021-12-08
679	Tina Christensen	1961-01-01	19	3	0	not_ready	\N
680	Niels Christensen	1958-10-02	4	8	0	not_ready	\N
681	Camilla Christiansen	1969-06-16	14	20	0	not_ready	\N
682	Camilla Kristensen	1993-02-14	20	9	1	passed	2021-12-25
683	Daniel Christensen	1986-01-09	18	6	3	ready	\N
684	Nikolaj Andersen	1980-12-29	19	13	2	not_ready	\N
685	Martin Sørensen	1950-05-28	19	19	4	ready	\N
686	Per Jørgensen	1974-09-25	15	1	0	not_ready	\N
687	Jens Møller	1987-06-06	5	1	0	not_ready	\N
688	Niels Mortensen	1985-02-11	19	11	4	ready	\N
689	Lone Madsen	1992-03-06	2	15	0	not_ready	\N
690	Bente Pedersen	1989-04-14	19	12	0	not_ready	\N
691	Nikolaj Møller	1957-04-28	3	9	0	not_ready	\N
692	Ole Andersen	1978-02-01	11	12	0	not_ready	\N
693	Lars Pedersen	1970-01-15	2	13	1	not_ready	\N
694	Jørgen Lindholm	1967-09-12	2	9	0	not_ready	\N
695	Marianne Christiansen	1950-10-02	3	4	1	passed	2019-02-10
696	Kirsten Møller	1975-04-26	3	13	1	not_ready	\N
697	Camilla Madsen	1969-12-21	18	12	0	not_ready	\N
698	Kirsten Poulsen	1968-09-15	5	6	0	not_ready	\N
699	Helle Sørensen	1961-05-07	7	3	0	not_ready	\N
700	Jesper Lindholm	1971-05-13	11	19	0	not_ready	\N
701	Mette Olsen	1995-05-02	8	2	1	ready	\N
702	Hanne Johansen	1982-01-12	14	19	4	passed	2019-09-28
703	Per Jørgensen	1961-05-13	18	12	0	not_ready	\N
704	Jacob Olsen	1954-10-17	3	20	0	not_ready	\N
705	Karen Jensen	1967-07-10	8	5	0	not_ready	\N
706	Helle Johansen	1976-10-29	16	20	0	not_ready	\N
707	Kirsten Larsen	1968-06-17	9	15	1	passed	2020-02-19
708	Anna Jørgensen	1993-02-23	19	1	0	not_ready	\N
709	Anders Olsen	1952-03-16	6	6	0	not_ready	\N
710	Jørgen Olsen	1954-01-08	9	1	2	passed	2021-04-01
711	Jens Jørgensen	1990-10-12	9	17	0	not_ready	\N
712	Morten Larsen	1974-06-16	5	14	0	not_ready	\N
713	Mads Petersen	1976-05-16	14	8	0	not_ready	\N
714	Kirsten Olsen	1995-05-29	11	11	2	passed	2021-09-22
715	Daniel Kristensen	1964-04-16	5	8	2	not_ready	\N
716	Pia Kristensen	1955-04-22	9	5	0	not_ready	\N
717	Niels Christiansen	1955-09-21	7	16	2	ready	\N
718	Jacob Kristensen	1997-12-16	6	12	1	not_ready	\N
719	Søren Madsen	1991-10-05	13	11	0	not_ready	\N
720	Daniel Jensen	1953-06-13	1	19	0	not_ready	\N
721	Karen Kristensen	1974-10-23	4	19	0	not_ready	\N
722	Peter Andersen	1993-12-04	2	1	0	not_ready	\N
723	Mads Andersen	1992-02-21	1	20	0	not_ready	\N
724	Lone Lindholm	1993-07-04	13	10	0	not_ready	\N
725	Rasmus Poulsen	1976-03-27	2	15	2	passed	2019-03-24
726	Daniel Andersen	1966-09-24	14	15	3	passed	2020-08-30
727	Maria Madsen	1981-04-12	4	19	2	ready	\N
728	Tina Madsen	1979-01-01	17	20	0	not_ready	\N
729	Inge Madsen	1953-02-19	4	13	1	passed	2021-01-23
730	Pia Jensen	1960-10-17	17	1	0	not_ready	\N
731	Gitte Pedersen	1968-11-30	20	1	0	not_ready	\N
732	Maria Jørgensen	1970-03-04	8	11	3	not_ready	\N
733	Jørgen Olsen	1951-08-24	9	20	0	not_ready	\N
734	Susanne Kristensen	1969-04-17	8	8	0	not_ready	\N
735	Gitte Møller	1971-10-08	13	8	0	not_ready	\N
736	Christian Thomsen	1961-01-05	12	1	0	passed	2019-02-24
737	Stephan Lindholm	1961-12-01	2	3	4	ready	\N
738	Lene Johansen	1985-02-19	2	2	0	ready	\N
739	Mette Mortensen	1963-08-16	20	6	0	not_ready	\N
740	Lene Petersen	1981-01-06	19	17	3	passed	2020-08-27
741	Pia Rasmussen	1988-11-25	1	19	0	ready	\N
742	Ole Olsen	1981-06-10	5	15	0	not_ready	\N
743	Martin Madsen	1967-01-14	11	10	0	not_ready	\N
744	Thomas Andersen	1981-06-10	13	2	4	passed	2020-10-01
745	Thomas Petersen	1980-02-03	20	15	0	not_ready	\N
746	Jesper Kristensen	1987-12-19	7	19	0	passed	2021-07-11
747	Thomas Pedersen	1970-05-22	5	8	0	not_ready	\N
748	Rasmus Pedersen	1965-12-11	18	14	0	not_ready	\N
749	Henrik Lindholm	1989-07-26	2	2	0	not_ready	\N
750	Jacob Rasmussen	1978-11-06	7	1	0	not_ready	\N
751	Inge Sørensen	1956-05-27	17	15	0	not_ready	\N
752	Mette Christiansen	1976-11-10	4	20	0	not_ready	\N
753	Pia Mortensen	1981-11-21	16	15	0	not_ready	\N
754	Jørgen Madsen	1952-07-01	20	17	0	not_ready	\N
755	Jens Pedersen	1960-09-14	15	4	0	not_ready	\N
756	Marianne Jensen	1960-02-03	6	3	1	not_ready	\N
757	Susanne Johansen	1987-08-20	4	14	0	not_ready	\N
758	Niels Mortensen	1996-04-19	13	20	0	not_ready	\N
759	Inge Christiansen	1963-02-20	7	18	0	not_ready	\N
760	Inge Thomsen	1985-04-03	18	20	0	not_ready	\N
761	Louise Christiansen	1979-01-28	15	14	0	not_ready	\N
762	Karen Rasmussen	1999-01-23	20	3	0	not_ready	\N
763	Mads Thomsen	1966-07-07	18	10	0	not_ready	\N
764	Daniel Møller	1989-02-22	2	15	0	not_ready	\N
765	Thomas Olsen	1991-11-21	14	2	0	not_ready	\N
766	Thomas Pedersen	1973-11-23	16	20	0	not_ready	\N
767	Per Olsen	1960-01-09	15	16	2	ready	\N
768	Inge Hansen	1977-01-24	5	17	0	not_ready	\N
769	Søren Sørensen	1952-11-06	2	11	0	not_ready	\N
770	Morten Jørgensen	1990-10-21	4	18	0	not_ready	\N
771	Lone Andersen	1992-12-05	2	11	0	not_ready	\N
772	Susanne Møller	1950-07-19	17	4	0	not_ready	\N
773	Mads Pedersen	1960-10-22	4	7	0	not_ready	\N
774	Mette Larsen	1967-12-02	8	18	3	passed	2021-06-09
775	Karen Sørensen	1976-08-16	6	2	0	not_ready	\N
776	Pia Madsen	1982-03-12	12	7	0	not_ready	\N
777	Lars Rasmussen	1954-06-12	8	8	0	not_ready	\N
778	Jacob Hansen	1976-05-19	9	3	0	not_ready	\N
779	Mads Poulsen	1983-09-02	13	7	3	ready	\N
780	Michael Larsen	1969-02-20	7	12	0	not_ready	\N
781	Michael Christiansen	1987-04-04	9	6	4	ready	\N
782	Lone Hansen	1964-05-08	9	3	0	not_ready	\N
783	Bente Rasmussen	1965-08-14	16	12	4	ready	\N
784	Søren Jensen	1982-03-28	9	19	1	passed	2020-12-11
785	Tina Lindholm	1950-11-18	6	14	0	not_ready	\N
786	Bente Mortensen	1957-06-10	3	14	0	not_ready	\N
787	Morten Madsen	1999-08-27	11	9	0	not_ready	\N
788	Karen Møller	1984-06-07	9	12	1	passed	2019-05-22
789	Mads Kristensen	1996-10-15	14	9	0	not_ready	\N
790	Jesper Sørensen	1974-07-07	20	14	0	not_ready	\N
791	Thomas Kristensen	1996-06-25	18	2	1	passed	2018-12-13
792	Helle Sørensen	1957-04-21	5	14	0	not_ready	\N
793	Karen Jensen	1954-12-11	18	13	0	not_ready	\N
794	Tina Madsen	1958-04-23	11	14	4	passed	2019-07-04
795	Lone Poulsen	1969-05-14	17	8	0	not_ready	\N
796	Anne Sørensen	1963-02-14	6	18	0	not_ready	\N
797	Ole Andersen	1994-08-03	7	18	0	not_ready	\N
798	Anne Christensen	1989-01-03	13	17	0	not_ready	\N
799	Inge Poulsen	1972-02-04	16	17	4	passed	2020-11-30
914	Henrik Madsen	1999-08-16	2	15	0	not_ready	\N
800	Nikolaj Lindholm	1965-03-25	1	10	0	not_ready	\N
801	Ole Christensen	1975-09-21	20	4	4	passed	2021-02-15
802	Thomas Lindholm	1965-06-11	8	14	0	passed	2019-12-24
803	Lars Nielsen	1978-10-09	19	19	1	ready	\N
804	Daniel Larsen	1998-08-02	14	15	0	passed	2019-10-18
805	Morten Pedersen	1970-09-21	15	12	1	passed	2020-12-29
806	Marianne Madsen	1959-12-28	19	19	0	not_ready	\N
807	Mads Christiansen	1958-01-10	20	3	0	not_ready	\N
808	Bente Møller	1992-03-21	12	15	3	ready	\N
809	Jacob Andersen	1993-10-07	17	3	0	not_ready	\N
810	Niels Jensen	1997-02-03	14	7	0	not_ready	\N
811	Jesper Mortensen	1988-04-14	17	14	0	passed	2019-07-10
812	Lone Poulsen	1952-03-22	5	12	0	not_ready	\N
813	Kirsten Mortensen	1973-03-11	20	9	0	not_ready	\N
814	Maria Nielsen	1977-05-04	8	6	0	not_ready	\N
815	Anna Christensen	1983-04-01	2	9	4	ready	\N
816	Susanne Olsen	1953-05-11	8	14	0	not_ready	\N
817	Pia Jørgensen	1984-11-01	17	3	0	not_ready	\N
818	Lars Petersen	1952-11-27	19	11	1	ready	\N
819	Bente Sørensen	1974-05-28	3	8	0	not_ready	\N
820	Gitte Jensen	1998-05-15	8	19	0	not_ready	\N
821	Hans Madsen	1970-01-12	16	1	4	passed	2020-09-13
822	Per Thomsen	1976-03-30	7	10	0	not_ready	\N
823	Lone Sørensen	1957-04-08	11	11	0	not_ready	\N
824	Lars Johansen	1981-10-28	11	19	0	not_ready	\N
825	Mads Andersen	1964-07-14	12	7	0	not_ready	\N
826	Hanne Andersen	1957-08-06	9	19	0	not_ready	\N
827	Mette Møller	1996-05-26	7	13	0	not_ready	\N
828	Rasmus Jørgensen	1999-11-02	8	10	0	not_ready	\N
829	Michael Olsen	1969-09-08	12	5	0	not_ready	\N
830	Jesper Mortensen	1951-11-01	8	12	0	not_ready	\N
831	Niels Kristensen	1950-10-06	10	11	0	not_ready	\N
832	Inge Andersen	1951-08-20	14	13	0	not_ready	\N
833	Maria Sørensen	1962-08-09	4	6	0	not_ready	\N
834	Marianne Thomsen	1992-11-20	2	17	3	passed	2020-08-09
835	Nikolaj Petersen	1988-07-06	19	4	0	not_ready	\N
836	Niels Rasmussen	1989-06-14	9	6	0	not_ready	\N
837	Jørgen Olsen	1950-07-22	6	12	4	passed	2021-07-14
838	Martin Poulsen	1986-05-10	17	3	0	not_ready	\N
839	Peter Petersen	1996-12-06	2	16	0	not_ready	\N
840	Jørgen Larsen	1999-11-08	15	12	0	not_ready	\N
841	Jesper Poulsen	1963-01-22	2	18	0	not_ready	\N
842	Lene Poulsen	1962-11-16	8	15	4	ready	\N
843	Christian Pedersen	1953-01-13	9	18	0	not_ready	\N
844	Mette Pedersen	1976-06-06	13	9	3	ready	\N
845	Tina Christensen	1968-08-05	8	8	0	not_ready	\N
846	Jørgen Christiansen	1981-02-04	14	15	0	not_ready	\N
847	Per Sørensen	1964-03-07	20	20	0	passed	2020-11-30
848	Hanne Rasmussen	1972-12-30	8	18	0	not_ready	\N
849	Christian Jensen	1975-10-01	7	1	0	not_ready	\N
850	Mads Mortensen	1998-12-02	3	2	1	passed	2020-07-11
851	Hanne Sørensen	1999-01-30	6	14	0	not_ready	\N
852	Martin Rasmussen	1991-04-09	16	15	0	not_ready	\N
853	Niels Olsen	1968-04-12	13	19	4	passed	2019-09-14
854	Anne Andersen	1967-08-05	5	4	0	not_ready	\N
855	Daniel Lindholm	1959-04-30	17	14	2	passed	2021-12-07
856	Gitte Pedersen	1991-11-08	10	12	1	ready	\N
857	Karen Madsen	1963-10-10	4	13	4	not_ready	\N
858	Maria Nielsen	1985-04-22	5	15	0	not_ready	\N
859	Jens Poulsen	1988-02-04	9	4	4	passed	2019-05-06
860	Karen Nielsen	1982-06-23	8	9	4	ready	\N
861	Louise Christiansen	1956-09-25	18	3	4	passed	2020-10-15
862	Lene Lindholm	1998-03-14	10	7	0	ready	\N
863	Nikolaj Lindholm	1954-11-14	5	5	0	not_ready	\N
864	Kirsten Nielsen	1963-07-30	3	3	0	not_ready	\N
865	Michael Lindholm	1979-10-25	14	9	0	not_ready	\N
866	Helle Christensen	1991-10-09	5	7	2	passed	2019-06-01
867	Gitte Sørensen	1963-09-16	8	6	0	not_ready	\N
868	Marianne Andersen	1970-04-18	17	11	4	not_ready	\N
869	Daniel Thomsen	1958-06-30	12	15	4	passed	2020-06-13
870	Hanne Hansen	1982-11-06	18	17	0	not_ready	\N
871	Susanne Madsen	1974-09-26	12	19	0	not_ready	\N
872	Jens Petersen	1983-11-27	18	14	0	not_ready	\N
873	Jørgen Sørensen	1959-01-01	18	20	0	not_ready	\N
874	Helle Thomsen	1984-11-25	10	14	0	not_ready	\N
875	Hanne Christiansen	1967-03-09	9	5	0	not_ready	\N
876	Lene Hansen	1964-08-24	9	6	0	not_ready	\N
877	Charlotte Kristensen	1967-07-28	7	4	0	not_ready	\N
878	Inge Møller	1976-08-12	7	15	0	passed	2020-11-28
879	Michael Lindholm	1993-12-12	15	3	0	not_ready	\N
880	Morten Madsen	1997-06-27	6	9	0	not_ready	\N
881	Stephan Olsen	1986-10-10	7	3	0	not_ready	\N
882	Rasmus Thomsen	1984-05-15	17	9	0	not_ready	\N
883	Susanne Mortensen	1952-04-18	7	15	0	not_ready	\N
884	Tina Madsen	1990-08-08	15	16	3	passed	2020-02-22
885	Søren Kristensen	1975-06-12	17	1	0	not_ready	\N
886	Thomas Johansen	1975-04-28	15	10	0	not_ready	\N
887	Hans Kristensen	1971-11-18	7	5	2	ready	\N
888	Mette Mortensen	1999-05-25	1	1	4	ready	\N
889	Lars Andersen	1984-02-21	4	13	1	ready	\N
890	Louise Christensen	1950-08-14	11	1	4	ready	\N
891	Hans Hansen	1995-07-15	11	10	0	not_ready	\N
892	Inge Hansen	1957-07-18	19	19	0	not_ready	\N
893	Camilla Madsen	1988-05-25	8	4	0	not_ready	\N
894	Helle Jørgensen	1963-01-15	13	5	0	not_ready	\N
895	Camilla Christensen	1995-05-07	20	3	3	ready	\N
896	Henrik Madsen	1991-10-29	2	11	0	not_ready	\N
897	Nikolaj Christensen	1966-10-07	3	8	2	not_ready	\N
898	Maria Olsen	1995-04-21	8	13	0	not_ready	\N
899	Martin Poulsen	1961-07-15	16	4	0	not_ready	\N
900	Jan Olsen	1993-02-26	8	11	4	passed	2020-06-11
901	Gitte Johansen	1986-02-10	2	16	3	ready	\N
902	Morten Christiansen	1969-02-01	5	4	4	ready	\N
903	Ole Andersen	1981-08-23	11	11	0	passed	2021-10-19
904	Bente Jensen	1961-08-12	1	5	0	not_ready	\N
905	Stephan Rasmussen	1973-04-17	20	6	0	not_ready	\N
906	Camilla Sørensen	1971-01-23	4	3	2	ready	\N
907	Jesper Poulsen	1950-06-30	5	18	0	not_ready	\N
908	Daniel Christiansen	1987-08-21	14	4	0	not_ready	\N
909	Marianne Petersen	1994-03-04	13	13	4	passed	2019-05-26
910	Michael Pedersen	1959-06-18	1	1	2	ready	\N
911	Morten Petersen	1972-01-30	17	17	0	not_ready	\N
912	Martin Olsen	1963-11-12	6	12	0	not_ready	\N
913	Jens Andersen	1970-08-08	14	11	0	ready	\N
915	Mette Christiansen	1968-04-30	1	11	1	passed	2019-04-10
916	Stephan Møller	1975-04-26	17	10	0	not_ready	\N
917	Morten Lindholm	1983-11-09	20	12	0	not_ready	\N
918	Christian Madsen	1952-11-01	20	18	0	not_ready	\N
919	Rasmus Pedersen	1990-02-22	10	18	0	passed	2021-12-14
920	Daniel Thomsen	1953-10-09	12	16	0	not_ready	\N
921	Lone Jørgensen	1966-06-13	14	18	0	not_ready	\N
922	Per Kristensen	1956-06-22	18	2	0	not_ready	\N
923	Maria Rasmussen	1966-12-19	19	19	4	passed	2021-07-26
924	Per Madsen	1952-02-08	16	20	0	not_ready	\N
925	Jacob Petersen	1990-12-19	4	4	1	passed	2020-09-02
926	Mads Christensen	1990-07-10	16	12	0	not_ready	\N
927	Bente Jørgensen	1996-01-29	7	7	4	not_ready	\N
928	Martin Sørensen	1965-03-20	10	17	3	ready	\N
929	Daniel Christiansen	1963-06-20	3	13	2	ready	\N
930	Marianne Mortensen	1965-04-17	8	13	0	not_ready	\N
931	Lars Madsen	1966-01-07	4	6	0	not_ready	\N
932	Bente Rasmussen	1952-05-01	14	14	4	not_ready	\N
933	Marianne Kristensen	1964-03-26	15	11	0	not_ready	\N
934	Jacob Kristensen	1991-02-17	20	12	0	not_ready	\N
935	Nikolaj Rasmussen	1955-07-10	8	16	0	passed	2019-07-29
936	Daniel Nielsen	1961-01-02	15	15	0	not_ready	\N
937	Tina Christensen	1989-05-16	4	13	0	not_ready	\N
938	Lars Jensen	1976-08-01	8	2	0	not_ready	\N
939	Jørgen Lindholm	1986-09-19	16	8	0	not_ready	\N
940	Nikolaj Christiansen	1956-05-21	9	11	3	ready	\N
941	Daniel Nielsen	1983-06-20	16	14	3	ready	\N
942	Morten Pedersen	1970-10-25	16	12	3	passed	2018-08-04
943	Stephan Sørensen	1998-04-02	3	10	0	not_ready	\N
944	Peter Lindholm	1978-04-21	9	7	0	not_ready	\N
945	Hans Nielsen	1968-09-24	18	4	4	passed	2020-09-03
946	Hanne Petersen	1980-11-08	11	19	4	ready	\N
947	Per Nielsen	1987-07-01	8	19	0	not_ready	\N
948	Ole Olsen	1950-05-26	15	14	0	not_ready	\N
949	Martin Mortensen	1988-07-19	3	15	2	not_ready	\N
950	Jacob Petersen	1957-05-23	7	15	0	not_ready	\N
951	Michael Larsen	1986-12-05	6	1	0	not_ready	\N
952	Lars Jørgensen	1992-08-08	12	18	4	passed	2020-12-17
953	Morten Jensen	1970-06-25	14	18	0	not_ready	\N
954	Per Møller	1987-03-13	5	8	0	not_ready	\N
955	Helle Larsen	1968-01-21	7	1	0	not_ready	\N
956	Hans Pedersen	1957-03-27	1	5	0	not_ready	\N
957	Jesper Madsen	1979-03-20	7	11	0	not_ready	\N
958	Stephan Jørgensen	1954-05-21	16	15	0	not_ready	\N
959	Rasmus Møller	1985-05-02	12	1	3	ready	\N
960	Lene Thomsen	1982-07-05	7	8	0	not_ready	\N
961	Hans Olsen	1975-03-06	2	4	0	not_ready	\N
962	Jens Pedersen	1963-05-12	14	1	0	passed	2021-03-16
963	Jørgen Jørgensen	1975-07-17	8	10	0	passed	2020-12-22
964	Lars Olsen	1982-01-14	10	12	2	passed	2019-01-28
965	Niels Andersen	1951-11-07	19	3	0	not_ready	\N
966	Ole Larsen	1965-07-11	6	14	0	not_ready	\N
967	Gitte Madsen	1958-11-16	17	7	0	not_ready	\N
968	Stephan Olsen	1999-01-08	11	2	0	not_ready	\N
969	Lone Møller	1971-05-23	13	11	0	not_ready	\N
970	Anne Pedersen	1958-08-05	17	9	0	not_ready	\N
971	Daniel Andersen	1961-08-13	19	18	0	ready	\N
972	Mads Christiansen	1957-11-17	5	2	0	not_ready	\N
973	Henrik Andersen	1961-03-02	2	11	0	not_ready	\N
974	Charlotte Hansen	1967-04-08	13	9	0	not_ready	\N
975	Susanne Kristensen	1954-12-03	11	9	0	not_ready	\N
976	Maria Sørensen	1989-09-26	11	1	0	not_ready	\N
977	Lene Hansen	1981-02-26	15	18	0	not_ready	\N
978	Jens Hansen	1989-12-16	17	1	3	ready	\N
979	Søren Petersen	1961-11-09	20	14	0	not_ready	\N
980	Hans Pedersen	1984-06-03	3	1	1	passed	2018-11-27
981	Jesper Poulsen	1994-10-10	11	17	0	not_ready	\N
982	Lars Thomsen	1988-09-01	8	2	0	ready	\N
983	Anna Pedersen	1969-03-20	2	19	1	passed	2018-12-09
984	Henrik Christiansen	1965-07-18	11	3	0	not_ready	\N
985	Susanne Christensen	1991-08-20	5	8	0	not_ready	\N
986	Michael Lindholm	1991-08-04	11	20	0	not_ready	\N
987	Stephan Christensen	1977-09-09	14	1	3	ready	\N
988	Søren Nielsen	1996-07-03	16	18	1	passed	2020-02-07
989	Marianne Christensen	1979-02-09	11	4	1	passed	2018-11-21
990	Lene Nielsen	1992-09-07	3	12	0	not_ready	\N
991	Jørgen Petersen	1969-08-11	12	6	0	not_ready	\N
992	Nikolaj Jørgensen	1971-05-08	12	5	0	not_ready	\N
993	Hans Petersen	1996-11-19	13	15	2	passed	2021-05-17
994	Michael Andersen	1954-01-07	8	3	0	not_ready	\N
995	Morten Madsen	1992-01-04	16	9	3	ready	\N
996	Lene Nielsen	1994-04-10	18	11	0	not_ready	\N
997	Anna Jørgensen	1969-02-11	6	18	0	not_ready	\N
998	Jørgen Mortensen	1952-02-14	6	9	0	not_ready	\N
999	Morten Johansen	1979-09-08	12	6	0	not_ready	\N
1000	Charlotte Lindholm	1954-11-22	18	16	0	not_ready	\N
1001	Stephan Christensen	1982-08-26	1	10	0	not_ready	\N
1002	Søren Christiansen	1960-01-11	7	9	0	not_ready	\N
1003	Peter Johansen	1993-02-08	7	3	2	passed	2020-12-09
1004	Martin Møller	1990-06-11	8	13	2	passed	2020-12-17
1005	Henrik Møller	1964-08-01	19	2	0	not_ready	\N
1006	Jan Thomsen	1968-05-21	2	16	0	not_ready	\N
1007	Christian Rasmussen	1966-03-10	7	11	0	not_ready	\N
1008	Inge Møller	1992-09-03	14	6	0	not_ready	\N
1009	Daniel Larsen	1985-10-08	8	10	0	not_ready	\N
1010	Hanne Madsen	1968-04-21	18	7	2	ready	\N
1011	Inge Mortensen	1972-11-13	8	15	0	not_ready	\N
1012	Susanne Johansen	1977-11-16	9	7	3	passed	2021-07-24
1013	Helle Thomsen	1958-07-24	5	2	0	not_ready	\N
1014	Henrik Christensen	1997-11-14	8	10	3	passed	2019-06-20
1015	Kirsten Nielsen	1972-08-26	12	10	4	ready	\N
1016	Niels Nielsen	1950-01-23	8	9	0	not_ready	\N
1017	Gitte Hansen	1982-08-28	14	7	0	passed	2019-10-14
1018	Jacob Madsen	1968-02-23	8	15	0	not_ready	\N
1019	Charlotte Poulsen	1986-03-18	17	14	0	not_ready	\N
1020	Søren Andersen	1968-08-28	17	5	4	passed	2020-07-16
1021	Rasmus Poulsen	1994-10-01	19	20	0	not_ready	\N
1022	Lars Mortensen	1963-01-10	16	2	3	not_ready	\N
1023	Morten Pedersen	1957-09-16	10	15	0	not_ready	\N
1024	Per Nielsen	1995-11-27	12	15	0	ready	\N
1025	Pia Lindholm	1985-09-21	1	4	0	not_ready	\N
1026	Tina Johansen	1976-05-19	5	18	0	not_ready	\N
1027	Thomas Rasmussen	1966-08-20	16	14	0	not_ready	\N
1028	Susanne Mortensen	1980-12-26	1	1	2	passed	2021-06-09
1029	Karen Kristensen	1994-09-05	5	1	0	not_ready	\N
1030	Hanne Petersen	1962-07-13	17	7	3	not_ready	\N
1031	Karen Rasmussen	1954-04-20	3	4	0	not_ready	\N
1032	Stephan Thomsen	1976-01-21	20	6	0	not_ready	\N
1033	Anne Sørensen	1981-01-15	4	7	0	not_ready	\N
1034	Jan Sørensen	1986-06-16	15	11	2	ready	\N
1035	Lars Christensen	1975-12-29	8	11	0	not_ready	\N
1036	Mette Christiansen	1968-07-12	14	19	0	not_ready	\N
1037	Hans Nielsen	1973-04-19	20	19	0	not_ready	\N
1038	Kirsten Sørensen	1991-08-13	11	2	0	not_ready	\N
1039	Ole Christensen	1997-08-14	6	3	0	not_ready	\N
1040	Tina Kristensen	1998-02-12	19	15	3	passed	2019-06-01
1041	Ole Andersen	1983-01-05	6	15	1	ready	\N
1042	Peter Poulsen	1997-03-13	6	8	1	passed	2019-09-12
1043	Rasmus Pedersen	1990-12-07	15	2	4	passed	2020-04-12
1044	Bente Johansen	1999-01-23	7	13	0	not_ready	\N
1045	Bente Lindholm	1974-03-07	9	17	3	passed	2020-01-22
1046	Helle Møller	1961-11-21	5	4	4	not_ready	\N
1047	Kirsten Olsen	1987-12-05	14	20	4	ready	\N
1048	Anna Petersen	1975-05-14	19	2	0	not_ready	\N
1049	Mette Hansen	1989-08-13	17	7	0	not_ready	\N
1050	Jens Poulsen	1974-01-28	19	9	0	not_ready	\N
1051	Christian Mortensen	1958-03-06	7	2	4	ready	\N
1052	Inge Møller	1985-08-08	15	13	0	not_ready	\N
1053	Jens Pedersen	1998-02-03	1	6	0	not_ready	\N
1054	Lars Petersen	1965-01-30	7	11	0	passed	2021-07-26
1055	Daniel Christensen	1991-01-23	10	2	0	not_ready	\N
1056	Daniel Andersen	1972-06-26	11	14	0	not_ready	\N
1057	Jacob Pedersen	1986-04-03	14	16	0	not_ready	\N
1058	Camilla Thomsen	1952-02-07	14	1	4	not_ready	\N
1059	Louise Christensen	1996-02-01	15	6	0	not_ready	\N
1060	Charlotte Jørgensen	1950-09-29	8	20	0	not_ready	\N
1061	Lone Pedersen	1987-04-19	10	7	1	ready	\N
1062	Anna Christiansen	1987-10-02	6	3	0	not_ready	\N
1063	Kirsten Jørgensen	1974-08-14	18	5	0	ready	\N
1064	Niels Hansen	1994-07-10	18	15	0	ready	\N
1065	Lars Andersen	1962-04-17	9	17	0	not_ready	\N
1066	Helle Petersen	1989-06-29	3	7	0	not_ready	\N
1067	Niels Andersen	1982-11-18	4	13	0	not_ready	\N
1068	Thomas Jørgensen	1990-10-13	20	9	0	not_ready	\N
1069	Mads Hansen	1999-09-05	10	1	4	passed	2019-05-28
1070	Marianne Olsen	1989-02-04	18	14	0	not_ready	\N
1071	Morten Petersen	1975-12-19	17	17	0	not_ready	\N
1072	Daniel Mortensen	1951-07-13	19	19	0	not_ready	\N
1073	Ole Johansen	1987-02-22	13	6	2	passed	2018-08-27
1074	Jacob Hansen	1996-10-22	4	20	3	passed	2020-09-12
1075	Hans Lindholm	1983-01-17	16	6	0	not_ready	\N
1076	Helle Johansen	1997-07-02	10	11	3	ready	\N
1077	Morten Christensen	1975-10-26	20	2	0	not_ready	\N
1078	Jacob Christiansen	1965-09-15	5	1	0	not_ready	\N
1079	Rasmus Thomsen	1985-07-19	5	20	1	ready	\N
1080	Jørgen Johansen	1959-08-05	15	17	0	not_ready	\N
1081	Michael Christensen	1953-04-09	20	10	0	not_ready	\N
1082	Maria Madsen	1998-06-04	5	2	2	ready	\N
1083	Jan Hansen	1961-11-10	14	5	0	not_ready	\N
1084	Pia Jørgensen	1967-02-12	2	4	0	not_ready	\N
1085	Lone Jensen	1962-07-07	17	13	0	not_ready	\N
1086	Mette Møller	1992-04-16	14	16	0	not_ready	\N
1087	Jens Jensen	1989-11-15	7	14	0	ready	\N
1088	Lone Thomsen	1954-05-27	20	15	0	not_ready	\N
1089	Tina Larsen	1996-06-11	5	4	0	not_ready	\N
1090	Pia Andersen	1990-05-03	18	2	0	not_ready	\N
1091	Susanne Christensen	1996-01-10	3	2	0	not_ready	\N
1092	Helle Johansen	1956-02-01	11	10	1	ready	\N
1093	Stephan Nielsen	1985-07-19	11	2	4	ready	\N
1094	Susanne Christiansen	1959-02-10	20	7	0	passed	2021-07-09
1095	Hans Larsen	1962-10-01	12	12	3	ready	\N
1096	Susanne Petersen	1979-01-07	9	14	0	not_ready	\N
1097	Morten Thomsen	1999-11-19	1	1	0	not_ready	\N
1098	Camilla Jørgensen	1977-12-11	12	19	0	not_ready	\N
1099	Jørgen Rasmussen	1958-06-23	8	15	3	ready	\N
1100	Lene Hansen	1959-01-19	6	20	0	not_ready	\N
1101	Helle Poulsen	1982-06-11	12	14	0	not_ready	\N
1102	Henrik Christensen	1979-11-06	4	3	3	not_ready	\N
1103	Peter Hansen	1957-10-21	15	6	0	not_ready	\N
1104	Helle Jensen	1966-11-15	9	17	0	passed	2021-03-19
1105	Peter Lindholm	1963-09-19	9	2	3	passed	2021-02-03
1106	Jørgen Olsen	1963-01-20	12	6	0	not_ready	\N
1107	Anders Christensen	1993-05-30	15	7	0	ready	\N
1108	Jørgen Olsen	1953-07-01	17	13	4	not_ready	\N
1109	Morten Olsen	1981-10-18	13	17	4	not_ready	\N
1110	Michael Rasmussen	1964-10-25	10	11	0	not_ready	\N
1111	Anders Sørensen	1993-10-10	12	15	0	not_ready	\N
1112	Camilla Christensen	1950-02-14	3	11	1	ready	\N
1113	Mette Christensen	1954-12-08	6	20	0	passed	2020-01-05
1114	Stephan Andersen	1999-07-06	5	16	0	not_ready	\N
1115	Susanne Nielsen	1988-02-04	9	3	0	not_ready	\N
1116	Hanne Jensen	1962-09-20	2	6	0	not_ready	\N
1117	Anna Johansen	1980-10-20	3	4	0	not_ready	\N
1118	Jacob Thomsen	1992-03-13	3	15	0	not_ready	\N
1119	Jesper Pedersen	1966-05-05	4	4	0	not_ready	\N
1120	Daniel Rasmussen	1973-01-23	8	20	0	not_ready	\N
1121	Per Kristensen	1961-04-11	18	7	0	not_ready	\N
1122	Søren Poulsen	1999-06-28	19	17	1	passed	2020-01-02
1123	Jens Christensen	1980-08-08	11	3	0	not_ready	\N
1124	Morten Rasmussen	1992-10-16	14	7	0	not_ready	\N
1125	Søren Hansen	1987-12-09	15	11	0	not_ready	\N
1126	Karen Johansen	1959-07-28	13	17	0	not_ready	\N
1127	Anders Madsen	1962-11-21	17	8	0	not_ready	\N
1128	Nikolaj Lindholm	1964-06-01	15	19	2	passed	2019-10-29
1129	Pia Jensen	1965-07-17	1	11	2	passed	2020-12-22
1130	Michael Olsen	1997-02-19	11	3	4	passed	2021-06-19
1131	Jesper Christensen	1981-04-07	20	6	0	not_ready	\N
1132	Peter Christensen	1974-09-28	5	1	0	not_ready	\N
1133	Jens Andersen	1950-02-23	19	13	0	not_ready	\N
1134	Morten Nielsen	1959-07-25	11	10	4	passed	2020-02-08
1135	Jens Larsen	1958-06-26	13	8	0	not_ready	\N
1136	Anna Møller	1970-09-20	20	4	4	passed	2020-04-08
1137	Thomas Christensen	1995-02-15	3	18	0	not_ready	\N
1138	Kirsten Larsen	1961-11-30	15	13	1	passed	2021-11-12
1139	Martin Andersen	1955-09-13	19	3	0	not_ready	\N
1140	Camilla Andersen	1959-09-25	7	19	0	not_ready	\N
1141	Tina Olsen	1994-01-27	5	12	4	ready	\N
1142	Marianne Kristensen	1971-02-18	15	1	0	not_ready	\N
1143	Peter Johansen	1950-12-27	3	18	0	not_ready	\N
1144	Tina Kristensen	1970-10-14	4	6	0	not_ready	\N
1145	Maria Larsen	1985-08-17	9	5	1	ready	\N
1146	Christian Kristensen	1966-07-02	7	17	4	not_ready	\N
1147	Peter Jensen	1965-11-10	8	16	0	not_ready	\N
1148	Hans Hansen	1974-08-21	11	8	0	not_ready	\N
1149	Kirsten Mortensen	1966-06-15	17	12	0	not_ready	\N
1150	Anders Jørgensen	1994-05-23	4	18	4	not_ready	\N
1151	Camilla Olsen	1966-03-30	11	16	0	passed	2019-01-24
1152	Ole Olsen	1984-04-20	8	8	1	ready	\N
1153	Per Sørensen	1998-08-07	17	11	0	not_ready	\N
1154	Thomas Møller	1953-11-19	11	16	3	passed	2021-02-13
1155	Daniel Jensen	1950-12-03	18	9	4	not_ready	\N
1156	Helle Olsen	1959-03-16	11	8	1	passed	2020-07-13
1157	Jan Thomsen	1972-06-17	19	17	0	not_ready	\N
1158	Nikolaj Christiansen	1951-07-18	12	8	0	not_ready	\N
1159	Hanne Nielsen	1953-07-22	16	15	4	not_ready	\N
1160	Jan Olsen	1970-03-14	6	2	0	not_ready	\N
1161	Anne Mortensen	1968-03-26	18	20	2	not_ready	\N
1162	Nikolaj Jensen	1990-06-15	3	19	0	not_ready	\N
1163	Rasmus Hansen	1980-12-26	5	16	0	not_ready	\N
1164	Mette Johansen	1977-09-25	14	7	0	not_ready	\N
1165	Hanne Madsen	1973-10-19	12	14	0	not_ready	\N
1166	Bente Larsen	1966-05-22	4	17	3	ready	\N
1167	Tina Lindholm	1972-05-06	14	5	4	ready	\N
1168	Peter Jørgensen	1962-06-17	13	12	0	not_ready	\N
1169	Karen Rasmussen	1956-04-30	2	1	0	not_ready	\N
1170	Inge Pedersen	1983-07-03	5	15	0	not_ready	\N
1171	Lene Madsen	1980-09-22	4	1	0	not_ready	\N
1172	Christian Petersen	1958-04-10	3	19	2	not_ready	\N
1173	Nikolaj Johansen	1986-04-30	16	9	0	not_ready	\N
1174	Charlotte Christiansen	1955-09-28	6	18	2	passed	2021-09-30
1175	Jan Jørgensen	1994-03-09	4	3	0	not_ready	\N
1176	Mette Andersen	1991-06-19	20	8	0	not_ready	\N
1177	Charlotte Poulsen	1972-04-03	13	10	0	not_ready	\N
1178	Mette Thomsen	1955-03-04	3	9	0	not_ready	\N
1179	Jesper Hansen	1958-11-11	11	14	0	not_ready	\N
1180	Tina Kristensen	1999-12-21	13	1	3	ready	\N
1181	Jens Møller	1997-09-13	9	11	0	not_ready	\N
1182	Søren Kristensen	1959-03-14	15	10	0	not_ready	\N
1183	Pia Petersen	1997-09-06	3	5	0	not_ready	\N
1184	Peter Petersen	1978-01-10	19	7	3	passed	2020-05-19
1185	Per Nielsen	1961-04-15	15	4	4	ready	\N
1186	Thomas Rasmussen	1984-01-23	11	2	0	not_ready	\N
1187	Per Jørgensen	1965-08-13	16	1	0	not_ready	\N
1188	Peter Thomsen	1981-12-24	2	4	0	not_ready	\N
1189	Camilla Christensen	1965-02-20	12	1	1	passed	2020-04-11
1190	Rasmus Pedersen	1991-01-04	6	5	0	ready	\N
1191	Henrik Mortensen	1972-05-09	15	10	0	ready	\N
1192	Susanne Jørgensen	1997-08-25	10	15	4	passed	2019-09-18
1193	Kirsten Hansen	1995-03-16	14	11	1	ready	\N
1194	Per Christiansen	1995-01-25	8	16	3	ready	\N
1195	Lars Hansen	1982-09-03	1	20	2	passed	2021-04-24
1196	Pia Hansen	1973-02-11	2	10	3	passed	2020-08-22
1197	Hans Pedersen	1966-01-29	2	19	0	not_ready	\N
1198	Anne Hansen	1951-01-14	14	2	0	not_ready	\N
1199	Jens Møller	1973-07-06	20	4	2	not_ready	\N
1200	Camilla Rasmussen	1989-01-18	11	11	1	passed	2019-04-17
1201	Lene Johansen	1953-11-06	5	8	3	not_ready	\N
1202	Charlotte Andersen	1997-01-06	8	11	1	passed	2019-09-25
1203	Jacob Christensen	1955-03-27	14	15	0	ready	\N
1204	Christian Thomsen	1986-11-07	8	11	3	ready	\N
1205	Gitte Sørensen	1968-10-23	9	7	0	not_ready	\N
1206	Per Møller	1950-11-20	10	4	0	not_ready	\N
1207	Søren Johansen	1971-05-13	12	10	0	not_ready	\N
1208	Jørgen Poulsen	1987-10-08	8	7	1	passed	2019-11-16
1209	Lone Lindholm	1998-07-07	9	11	0	not_ready	\N
1210	Bente Andersen	1987-09-02	5	7	0	not_ready	\N
1211	Karen Christensen	1991-01-27	14	7	0	not_ready	\N
1212	Jens Rasmussen	1991-09-19	10	20	0	not_ready	\N
1213	Stephan Mortensen	1954-12-29	12	18	0	not_ready	\N
1214	Mette Poulsen	1991-07-18	13	6	2	passed	2020-02-17
1215	Marianne Pedersen	1961-03-27	15	9	0	not_ready	\N
1216	Lars Sørensen	1989-07-16	19	9	4	not_ready	\N
1217	Rasmus Poulsen	1997-06-29	14	12	0	not_ready	\N
1218	Jørgen Pedersen	1976-02-03	12	10	0	not_ready	\N
1219	Charlotte Johansen	1970-06-01	6	11	0	not_ready	\N
1220	Susanne Andersen	1984-02-14	9	7	1	not_ready	\N
1221	Anna Hansen	1970-05-09	10	13	0	not_ready	\N
1222	Marianne Johansen	1959-03-14	5	1	0	not_ready	\N
1223	Mette Poulsen	1961-12-23	5	8	1	ready	\N
1224	Lars Christiansen	1969-11-24	3	4	0	not_ready	\N
1225	Morten Andersen	1978-08-04	2	18	4	ready	\N
1226	Anna Christensen	1976-09-06	10	14	0	not_ready	\N
1227	Louise Petersen	1986-01-11	6	16	0	not_ready	\N
1228	Stephan Nielsen	1981-06-15	3	9	4	ready	\N
1229	Martin Lindholm	1955-05-17	9	15	0	not_ready	\N
1230	Jan Møller	1959-09-23	15	20	0	not_ready	\N
1231	Louise Mortensen	1966-03-09	14	12	0	not_ready	\N
1232	Michael Christensen	1952-08-05	8	16	0	not_ready	\N
1233	Lone Madsen	1984-09-08	9	2	3	not_ready	\N
1234	Morten Jørgensen	1985-02-08	10	18	1	ready	\N
1235	Stephan Andersen	1955-12-19	4	15	4	ready	\N
1236	Michael Nielsen	1951-09-14	6	11	2	ready	\N
1237	Marianne Kristensen	1966-07-19	9	6	0	not_ready	\N
1238	Pia Larsen	1994-03-12	7	16	0	not_ready	\N
1239	Karen Rasmussen	1965-09-10	14	20	0	not_ready	\N
1240	Hans Larsen	1956-12-10	9	3	0	not_ready	\N
1241	Karen Mortensen	1958-10-16	16	3	0	not_ready	\N
1242	Mette Rasmussen	1974-09-14	17	1	0	not_ready	\N
1243	Anne Nielsen	1954-10-27	19	10	0	not_ready	\N
1244	Bente Pedersen	1994-08-04	11	10	2	not_ready	\N
1245	Søren Lindholm	1980-01-09	15	10	0	not_ready	\N
1246	Peter Lindholm	1978-05-24	10	1	0	not_ready	\N
1247	Bente Mortensen	1997-02-11	20	17	3	ready	\N
1248	Louise Hansen	1997-12-24	5	4	0	not_ready	\N
1249	Bente Jensen	1965-11-11	8	16	0	not_ready	\N
1250	Anne Møller	1965-01-11	12	18	0	not_ready	\N
1251	Anne Christensen	1959-08-03	19	3	0	not_ready	\N
1252	Karen Hansen	1978-01-01	16	18	0	not_ready	\N
1253	Jesper Andersen	1976-10-28	6	16	3	passed	2019-03-07
1254	Martin Kristensen	1990-01-15	18	18	3	not_ready	\N
1255	Morten Jensen	1955-07-25	6	9	1	not_ready	\N
1256	Mads Hansen	1975-06-05	14	19	0	not_ready	\N
1257	Jesper Christiansen	1973-09-15	18	17	2	ready	\N
1258	Kirsten Andersen	1974-09-01	18	8	0	not_ready	\N
1259	Nikolaj Kristensen	1995-05-16	15	3	0	not_ready	\N
1260	Anna Rasmussen	1955-06-24	20	19	0	not_ready	\N
1261	Niels Johansen	1973-01-06	4	13	0	not_ready	\N
1262	Lars Christiansen	1963-05-14	3	9	2	ready	\N
1263	Henrik Christensen	1993-03-25	4	13	0	not_ready	\N
1264	Niels Pedersen	1998-02-04	6	2	0	not_ready	\N
1265	Jens Pedersen	1960-09-07	7	20	4	ready	\N
1266	Peter Rasmussen	1973-11-30	14	11	0	not_ready	\N
1267	Stephan Johansen	1999-08-05	10	13	3	passed	2021-03-24
1268	Henrik Christensen	1987-11-05	18	20	0	ready	\N
1269	Jan Nielsen	1987-12-10	11	2	0	not_ready	\N
1270	Mads Nielsen	1964-02-22	12	2	0	not_ready	\N
1271	Nikolaj Pedersen	1984-02-22	1	17	0	not_ready	\N
1272	Michael Mortensen	1952-08-16	4	18	4	passed	2021-07-08
1273	Morten Petersen	1980-03-02	10	10	0	not_ready	\N
1274	Søren Mortensen	1992-03-18	6	11	0	ready	\N
1275	Pia Madsen	1967-10-26	15	11	0	not_ready	\N
1276	Karen Thomsen	1957-07-18	11	20	0	not_ready	\N
1277	Charlotte Larsen	1951-01-02	6	2	3	not_ready	\N
1278	Karen Christensen	1972-01-08	6	9	2	ready	\N
1279	Mads Larsen	1957-11-15	20	12	4	ready	\N
1280	Camilla Jensen	1985-10-27	14	14	0	ready	\N
1281	Marianne Sørensen	1995-08-27	11	13	0	not_ready	\N
1282	Hans Mortensen	1950-10-25	3	15	1	ready	\N
1283	Maria Christiansen	1960-09-22	14	9	0	not_ready	\N
1284	Rasmus Nielsen	1983-11-10	6	1	0	not_ready	\N
1285	Susanne Olsen	1992-07-20	4	20	1	not_ready	\N
1286	Rasmus Jørgensen	1966-10-27	18	8	0	not_ready	\N
1287	Ole Nielsen	1984-10-13	6	3	0	passed	2020-01-19
1288	Hans Mortensen	1959-01-05	4	10	4	not_ready	\N
1289	Susanne Lindholm	1951-12-24	3	6	0	not_ready	\N
1290	Jesper Olsen	1999-11-15	13	2	1	not_ready	\N
1291	Tina Jørgensen	1955-05-14	9	2	0	not_ready	\N
1292	Hanne Poulsen	1950-07-21	1	16	0	ready	\N
1293	Maria Larsen	1951-09-30	14	16	4	passed	2019-04-17
1294	Kirsten Johansen	1981-09-26	18	13	0	not_ready	\N
1295	Lene Lindholm	1985-03-26	19	7	0	not_ready	\N
1296	Tina Hansen	1957-03-30	6	4	0	not_ready	\N
1297	Martin Pedersen	1954-05-27	20	1	3	passed	2021-10-18
1298	Christian Jørgensen	1989-11-22	3	6	0	not_ready	\N
1299	Thomas Madsen	1971-01-24	9	11	0	not_ready	\N
1300	Mette Hansen	1972-04-26	20	4	3	not_ready	\N
1301	Charlotte Hansen	1971-06-10	13	10	4	ready	\N
1302	Søren Nielsen	1970-04-19	7	13	4	not_ready	\N
1303	Mette Johansen	1980-04-05	20	9	0	not_ready	\N
1304	Ole Sørensen	1999-01-05	9	14	1	passed	2020-02-25
1305	Louise Hansen	1952-06-22	14	19	2	ready	\N
1306	Per Madsen	1953-12-30	6	12	0	ready	\N
1307	Jesper Andersen	1994-07-24	9	12	4	ready	\N
1308	Kirsten Madsen	1969-09-05	14	11	4	ready	\N
1309	Maria Poulsen	1992-09-21	10	10	0	not_ready	\N
1310	Søren Nielsen	1986-09-02	8	8	0	not_ready	\N
1311	Ole Nielsen	1977-07-04	18	2	4	passed	2019-06-12
1312	Charlotte Mortensen	1967-10-13	7	16	3	passed	2020-10-17
1313	Rasmus Larsen	1951-09-11	5	14	0	not_ready	\N
1314	Gitte Hansen	1998-08-28	11	17	2	ready	\N
1315	Jesper Møller	1966-10-27	4	3	0	not_ready	\N
1316	Per Jørgensen	1975-07-09	3	17	0	not_ready	\N
1317	Lars Kristensen	1962-12-13	12	20	0	not_ready	\N
1318	Niels Poulsen	1992-09-11	2	2	0	not_ready	\N
1319	Charlotte Johansen	1950-11-17	10	12	0	not_ready	\N
1320	Bente Larsen	1963-09-06	1	12	1	ready	\N
1321	Helle Christensen	1964-05-01	2	19	0	not_ready	\N
1322	Hans Christiansen	1977-12-20	6	4	0	not_ready	\N
1323	Lone Sørensen	1998-02-23	10	6	0	not_ready	\N
1324	Camilla Møller	1951-12-27	8	9	0	not_ready	\N
1325	Per Petersen	1981-12-05	16	15	0	ready	\N
1326	Daniel Poulsen	1991-12-14	9	8	0	not_ready	\N
1327	Ole Christiansen	1953-05-27	12	1	0	not_ready	\N
1328	Maria Poulsen	1974-08-08	20	4	1	passed	2019-02-08
1329	Lene Madsen	1959-03-26	1	12	0	not_ready	\N
1330	Anne Hansen	1954-06-09	17	4	0	not_ready	\N
1331	Tina Petersen	1974-04-13	13	10	2	ready	\N
1332	Ole Pedersen	1967-12-27	7	12	2	ready	\N
1333	Karen Møller	1993-11-09	8	5	0	not_ready	\N
1334	Peter Lindholm	1958-12-24	1	13	0	not_ready	\N
1335	Henrik Christiansen	1970-09-04	16	7	0	not_ready	\N
1336	Søren Christensen	1961-09-25	15	6	0	not_ready	\N
1337	Morten Madsen	1982-04-15	1	17	0	not_ready	\N
1338	Pia Jensen	1993-10-06	13	3	0	not_ready	\N
1339	Nikolaj Kristensen	1975-06-16	19	6	0	not_ready	\N
1340	Lene Thomsen	1979-05-05	3	7	1	ready	\N
1341	Anders Sørensen	1992-08-10	5	9	0	not_ready	\N
1342	Kirsten Poulsen	1952-11-04	17	5	0	not_ready	\N
1343	Jørgen Nielsen	1967-07-29	10	18	0	not_ready	\N
1344	Anders Rasmussen	1972-02-16	17	6	0	not_ready	\N
1345	Hans Mortensen	1968-07-19	18	8	0	passed	2019-11-19
1346	Jan Nielsen	1960-11-24	10	2	0	passed	2019-05-06
1347	Søren Rasmussen	1977-06-28	8	20	0	not_ready	\N
1348	Stephan Jørgensen	1978-11-21	2	10	0	not_ready	\N
1349	Michael Rasmussen	1977-12-29	8	18	0	not_ready	\N
1350	Lene Møller	1997-10-21	2	9	0	not_ready	\N
1351	Thomas Christensen	1954-02-02	20	11	0	not_ready	\N
1352	Anna Mortensen	1985-11-13	19	20	0	not_ready	\N
1353	Per Christensen	1962-08-27	13	8	2	passed	2020-04-13
1354	Martin Olsen	1982-06-10	20	19	2	passed	2019-02-14
1355	Christian Thomsen	1950-01-10	6	2	3	ready	\N
1356	Anders Mortensen	1974-04-23	15	3	0	not_ready	\N
1357	Anna Jørgensen	1991-05-21	5	6	0	not_ready	\N
1358	Henrik Christiansen	1980-05-04	1	1	0	not_ready	\N
1359	Lars Jørgensen	1960-04-09	16	14	0	not_ready	\N
1360	Christian Nielsen	1980-07-22	12	7	1	ready	\N
1361	Michael Lindholm	1966-12-24	7	14	4	passed	2020-04-04
1362	Marianne Hansen	1957-02-13	4	2	0	not_ready	\N
1363	Gitte Christensen	1986-06-03	6	16	3	ready	\N
1364	Jørgen Nielsen	1959-10-24	18	4	0	not_ready	\N
1365	Susanne Olsen	1978-06-30	2	7	0	not_ready	\N
1366	Mette Petersen	1967-02-24	5	2	0	not_ready	\N
1367	Christian Petersen	1961-12-03	20	6	2	ready	\N
1368	Søren Mortensen	1996-10-21	2	11	0	ready	\N
1369	Anne Petersen	1976-07-01	20	11	2	passed	2020-03-21
1370	Jørgen Olsen	1960-02-02	1	7	2	passed	2019-11-04
1371	Camilla Lindholm	1970-08-04	18	19	0	not_ready	\N
1372	Marianne Lindholm	1983-08-20	12	2	0	not_ready	\N
1373	Henrik Christiansen	1993-12-29	12	15	0	not_ready	\N
1374	Anders Jensen	1971-12-02	18	11	0	not_ready	\N
1375	Martin Lindholm	1955-08-24	14	12	0	not_ready	\N
1376	Gitte Pedersen	1975-12-16	5	3	0	not_ready	\N
1377	Bente Nielsen	1999-12-18	4	11	2	ready	\N
1378	Michael Poulsen	1971-04-27	19	3	0	not_ready	\N
1379	Anne Larsen	1955-09-02	2	4	0	not_ready	\N
1380	Niels Olsen	1954-12-07	3	14	2	passed	2020-03-10
1381	Martin Jørgensen	1983-10-19	1	10	4	not_ready	\N
1382	Jørgen Andersen	1995-11-03	9	7	0	not_ready	\N
1383	Jens Hansen	1976-11-15	8	10	0	not_ready	\N
1384	Charlotte Rasmussen	1985-06-14	7	1	2	passed	2020-06-08
1385	Inge Lindholm	1994-10-08	15	18	0	not_ready	\N
1386	Thomas Jensen	1953-02-21	15	14	0	not_ready	\N
1387	Daniel Madsen	1968-01-25	4	19	0	not_ready	\N
1388	Bente Madsen	1954-01-16	12	7	0	not_ready	\N
1389	Hans Hansen	1978-04-24	13	12	4	passed	2021-03-20
1390	Gitte Johansen	1985-04-30	6	17	2	ready	\N
1391	Jens Jørgensen	1966-06-28	2	16	0	not_ready	\N
1392	Nikolaj Pedersen	1990-11-20	7	1	0	not_ready	\N
1393	Gitte Rasmussen	1979-11-16	6	7	1	ready	\N
1394	Lars Christensen	1953-02-02	6	8	0	not_ready	\N
1395	Susanne Hansen	1995-05-24	10	16	0	not_ready	\N
1396	Mette Kristensen	1960-08-03	3	18	0	not_ready	\N
1397	Lars Petersen	1992-06-09	4	20	0	not_ready	\N
1398	Pia Christensen	1993-07-04	4	15	1	passed	2019-06-09
1399	Anne Johansen	1963-10-17	6	7	0	not_ready	\N
1400	Ole Møller	1960-12-29	10	17	0	not_ready	\N
1401	Helle Jørgensen	1989-10-19	11	7	0	not_ready	\N
1402	Gitte Hansen	1991-04-08	6	3	4	passed	2020-11-21
1403	Pia Olsen	1980-09-18	12	2	0	not_ready	\N
1404	Henrik Jensen	1978-05-01	17	12	3	passed	2019-07-30
1405	Jesper Lindholm	1998-12-02	3	12	0	not_ready	\N
1406	Inge Madsen	1982-05-02	17	1	0	not_ready	\N
1407	Lone Johansen	1983-12-27	11	9	0	not_ready	\N
1408	Kirsten Mortensen	1952-09-26	11	6	4	passed	2021-01-15
1409	Michael Møller	1994-01-03	7	16	0	not_ready	\N
1410	Hans Johansen	1975-01-17	8	20	3	ready	\N
1411	Mette Rasmussen	1965-08-06	18	7	1	ready	\N
1412	Nikolaj Petersen	1972-10-12	16	3	2	ready	\N
1413	Mette Jørgensen	1968-01-29	20	1	0	not_ready	\N
1414	Peter Kristensen	1999-05-29	4	12	0	not_ready	\N
1415	Ole Andersen	1984-05-01	4	17	0	not_ready	\N
1416	Martin Møller	1960-08-15	6	15	0	not_ready	\N
1417	Karen Poulsen	1970-12-04	14	11	0	not_ready	\N
1418	Gitte Møller	1980-02-03	2	16	0	not_ready	\N
1419	Anna Olsen	1994-04-18	5	7	0	not_ready	\N
1420	Jørgen Rasmussen	1956-11-20	8	3	0	not_ready	\N
1421	Peter Mortensen	1969-08-29	15	18	1	ready	\N
1422	Lene Kristensen	1969-11-11	12	9	0	not_ready	\N
1423	Camilla Jensen	1968-06-12	14	10	0	not_ready	\N
1424	Jan Larsen	1984-10-25	5	11	2	passed	2019-09-02
1425	Peter Lindholm	1970-08-03	20	12	0	not_ready	\N
1426	Morten Jensen	1956-10-14	16	6	0	not_ready	\N
1427	Hanne Andersen	1994-08-28	13	2	0	not_ready	\N
1428	Ole Rasmussen	1978-08-16	13	12	4	passed	2020-03-18
1429	Jesper Jensen	1996-05-19	16	16	0	not_ready	\N
1430	Helle Poulsen	1961-06-30	4	3	0	not_ready	\N
1431	Per Nielsen	1998-09-29	7	15	4	passed	2020-03-22
1432	Lars Rasmussen	1987-12-22	11	15	0	ready	\N
1433	Jens Nielsen	1985-07-06	11	17	0	not_ready	\N
1434	Ole Rasmussen	1996-07-04	15	19	0	ready	\N
1435	Jesper Andersen	1991-08-20	3	5	2	ready	\N
1436	Ole Johansen	1968-07-18	12	7	0	not_ready	\N
1437	Lars Larsen	1952-11-30	5	9	4	passed	2021-01-19
1438	Niels Jensen	1987-12-27	12	11	2	ready	\N
1439	Daniel Kristensen	1982-05-21	18	19	0	not_ready	\N
1440	Per Johansen	1952-11-25	5	7	0	not_ready	\N
1441	Jens Rasmussen	1966-06-27	16	9	0	ready	\N
1442	Niels Andersen	1953-12-29	19	18	2	passed	2021-05-17
1443	Hanne Olsen	1977-05-28	10	13	0	not_ready	\N
1444	Jesper Rasmussen	1982-01-03	2	18	2	not_ready	\N
1445	Hans Poulsen	1999-09-26	2	17	0	not_ready	\N
1446	Maria Kristensen	1961-02-20	18	11	1	passed	2020-12-15
1447	Maria Larsen	1982-09-18	12	1	0	not_ready	\N
1448	Henrik Olsen	1999-08-12	1	2	0	not_ready	\N
1449	Nikolaj Madsen	1977-01-05	6	20	0	not_ready	\N
1450	Michael Sørensen	1995-08-12	2	8	0	not_ready	\N
1451	Thomas Madsen	1965-11-10	19	14	2	passed	2021-04-13
1452	Helle Andersen	1974-09-23	16	12	0	not_ready	\N
1453	Stephan Møller	1950-04-20	8	11	0	not_ready	\N
1454	Marianne Olsen	1968-12-02	20	6	0	ready	\N
1455	Jesper Poulsen	1993-04-20	7	17	0	not_ready	\N
1456	Louise Thomsen	1967-05-26	10	8	4	passed	2019-06-27
1457	Mette Møller	1953-11-08	20	2	0	not_ready	\N
1458	Maria Møller	1963-10-20	19	16	1	not_ready	\N
1459	Jens Pedersen	1966-04-13	10	11	0	not_ready	\N
1460	Helle Mortensen	1950-08-06	11	3	3	ready	\N
1461	Hanne Madsen	1997-11-23	20	7	1	not_ready	\N
1462	Jacob Johansen	1990-07-02	10	19	0	not_ready	\N
1463	Helle Christensen	1994-08-30	8	15	0	not_ready	\N
1464	Lars Madsen	1986-04-13	18	6	0	not_ready	\N
1465	Martin Andersen	1950-11-16	7	6	2	ready	\N
1466	Michael Sørensen	1962-04-03	17	5	3	passed	2020-09-29
1467	Rasmus Thomsen	1951-03-25	16	6	0	not_ready	\N
1468	Jacob Johansen	1999-05-21	15	7	4	not_ready	\N
1469	Anna Christensen	1993-05-10	2	6	0	not_ready	\N
1470	Daniel Pedersen	1989-02-08	8	17	2	ready	\N
1471	Camilla Nielsen	1991-04-09	8	2	0	not_ready	\N
1472	Louise Rasmussen	1974-04-12	19	11	0	not_ready	\N
1473	Lone Olsen	1968-05-23	12	10	0	not_ready	\N
1474	Inge Sørensen	1964-10-26	8	18	3	ready	\N
1475	Pia Poulsen	1960-01-17	18	8	0	not_ready	\N
1476	Jacob Møller	1966-08-07	8	3	0	not_ready	\N
1477	Mads Johansen	1998-10-27	8	8	0	not_ready	\N
1478	Marianne Christensen	1966-11-10	15	1	0	not_ready	\N
1479	Bente Andersen	1961-11-22	9	12	4	passed	2020-10-29
1480	Jesper Mortensen	1972-03-01	13	9	0	not_ready	\N
1481	Anders Pedersen	1959-08-20	13	5	0	not_ready	\N
1482	Per Lindholm	1991-01-18	19	5	0	passed	2020-04-21
1483	Gitte Møller	1988-08-12	7	9	0	not_ready	\N
1484	Martin Kristensen	1997-03-06	1	12	0	not_ready	\N
1485	Inge Poulsen	1981-08-14	2	5	0	not_ready	\N
1600	Marianne Larsen	1999-07-12	12	3	0	not_ready	\N
1486	Martin Sørensen	1968-12-05	7	1	0	passed	2021-02-08
1487	Maria Møller	1952-02-26	4	10	1	ready	\N
1488	Helle Mortensen	1992-05-21	20	2	1	ready	\N
1489	Bente Jensen	1957-12-18	11	17	4	not_ready	\N
1490	Kirsten Kristensen	1986-12-19	2	20	0	not_ready	\N
1491	Henrik Hansen	1975-06-28	13	13	0	not_ready	\N
1492	Anders Pedersen	1967-02-18	3	3	0	not_ready	\N
1493	Charlotte Larsen	1956-11-13	11	8	0	not_ready	\N
1494	Stephan Petersen	1977-11-11	17	10	1	passed	2020-11-26
1495	Lars Hansen	1975-09-19	6	20	4	passed	2019-05-18
1496	Daniel Christensen	1970-01-15	10	19	0	not_ready	\N
1497	Hanne Larsen	1991-02-23	11	10	0	not_ready	\N
1498	Jan Sørensen	1954-09-15	2	5	0	not_ready	\N
1499	Jacob Sørensen	1986-06-13	1	19	4	ready	\N
1500	Karen Kristensen	1967-04-14	10	2	1	passed	2020-04-05
1501	Jan Petersen	1997-10-04	20	5	0	not_ready	\N
1502	Anders Poulsen	1969-08-02	20	13	0	not_ready	\N
1503	Jacob Olsen	1987-07-15	1	12	0	not_ready	\N
1504	Gitte Madsen	1982-04-07	2	17	1	passed	2021-05-15
1505	Gitte Sørensen	1955-12-26	9	3	0	passed	2020-12-17
1506	Mette Larsen	1957-11-22	9	15	0	ready	\N
1507	Hans Olsen	1999-09-13	2	13	1	passed	2019-07-03
1508	Stephan Andersen	1952-01-09	17	1	0	not_ready	\N
1509	Søren Christensen	1994-11-06	1	19	0	not_ready	\N
1510	Ole Christensen	1999-12-12	19	14	0	not_ready	\N
1511	Louise Madsen	1957-07-08	17	3	0	not_ready	\N
1512	Jan Christiansen	1980-12-27	11	15	0	not_ready	\N
1513	Niels Kristensen	1997-07-17	3	3	0	not_ready	\N
1514	Jacob Thomsen	1954-04-29	20	18	0	not_ready	\N
1515	Anna Kristensen	1994-09-18	2	3	0	not_ready	\N
1516	Anne Poulsen	1976-02-24	10	2	0	not_ready	\N
1517	Jacob Nielsen	1995-08-26	13	18	3	passed	2019-05-20
1518	Karen Pedersen	1967-10-10	7	10	0	not_ready	\N
1519	Lene Jørgensen	1958-10-20	9	14	0	not_ready	\N
1520	Lene Pedersen	1952-09-06	11	14	1	ready	\N
1521	Jens Jensen	1980-03-24	20	3	0	not_ready	\N
1522	Søren Sørensen	1975-06-27	19	6	0	not_ready	\N
1523	Camilla Rasmussen	1981-06-08	18	18	0	not_ready	\N
1524	Hans Pedersen	1987-08-17	6	2	0	not_ready	\N
1525	Pia Sørensen	1981-02-24	9	13	2	passed	2020-07-04
1526	Inge Christensen	1970-04-29	9	14	0	not_ready	\N
1527	Stephan Lindholm	1975-01-25	15	10	0	not_ready	\N
1528	Per Nielsen	1961-04-28	14	14	0	not_ready	\N
1529	Thomas Pedersen	1991-11-03	13	20	4	passed	2021-11-05
1530	Susanne Jensen	1964-04-22	15	9	1	passed	2019-07-16
1531	Jacob Johansen	1953-04-30	1	20	0	not_ready	\N
1532	Ole Madsen	1981-10-11	11	1	1	passed	2020-04-19
1533	Camilla Sørensen	1968-07-16	14	6	0	not_ready	\N
1534	Kirsten Christiansen	1953-03-11	12	11	4	passed	2020-10-19
1535	Lene Poulsen	1963-02-20	18	3	1	passed	2019-02-26
1536	Tina Larsen	1957-06-20	16	6	0	not_ready	\N
1537	Hans Jensen	1960-11-17	14	14	0	not_ready	\N
1538	Jens Poulsen	1997-09-16	9	9	4	ready	\N
1539	Hans Kristensen	1966-12-25	20	15	1	passed	2021-06-16
1540	Stephan Madsen	1957-09-02	3	15	4	ready	\N
1541	Hanne Kristensen	1992-06-16	4	8	0	not_ready	\N
1542	Jens Johansen	1984-01-14	19	7	0	not_ready	\N
1543	Hans Poulsen	1972-09-27	13	6	3	ready	\N
1544	Kirsten Jensen	1973-05-17	17	12	0	not_ready	\N
1545	Christian Thomsen	1995-11-29	7	14	4	passed	2019-12-29
1546	Peter Johansen	1976-06-08	15	10	0	not_ready	\N
1547	Pia Petersen	1960-10-29	10	11	0	not_ready	\N
1548	Niels Lindholm	1986-06-22	4	4	0	not_ready	\N
1549	Jørgen Larsen	1966-11-22	11	16	0	passed	2019-11-11
1550	Lone Lindholm	1973-10-17	10	17	4	passed	2021-05-06
1551	Thomas Madsen	1993-11-03	15	19	0	not_ready	\N
1552	Daniel Sørensen	1990-02-05	18	13	0	not_ready	\N
1553	Lene Christensen	1958-07-30	16	11	0	not_ready	\N
1554	Jesper Lindholm	1987-10-16	18	8	0	not_ready	\N
1555	Rasmus Kristensen	1956-04-04	16	20	4	ready	\N
1556	Jacob Christiansen	1987-01-29	6	9	2	not_ready	\N
1557	Jesper Olsen	1985-10-26	8	17	2	ready	\N
1558	Tina Jensen	1991-03-28	10	10	0	not_ready	\N
1559	Anders Andersen	1975-08-22	13	13	1	passed	2019-07-28
1560	Pia Kristensen	1954-11-30	7	14	0	passed	2020-04-07
1561	Nikolaj Lindholm	1952-12-13	2	17	2	ready	\N
1562	Peter Jørgensen	1989-09-19	15	16	0	not_ready	\N
1563	Martin Larsen	1967-05-09	11	18	0	not_ready	\N
1564	Stephan Thomsen	1985-09-18	15	11	0	not_ready	\N
1565	Hans Mortensen	1970-07-26	18	16	0	not_ready	\N
1566	Stephan Pedersen	1998-09-07	20	17	0	passed	2019-03-22
1567	Peter Møller	1995-01-07	17	8	0	not_ready	\N
1568	Jens Pedersen	1959-04-11	8	11	4	passed	2021-07-14
1569	Hanne Christiansen	1968-01-15	1	15	0	not_ready	\N
1570	Tina Mortensen	1960-05-24	8	1	3	not_ready	\N
1571	Jørgen Madsen	1986-12-03	3	15	0	not_ready	\N
1572	Susanne Madsen	1990-02-01	5	18	0	not_ready	\N
1573	Stephan Kristensen	1958-03-05	3	7	4	passed	2019-03-09
1574	Peter Olsen	1989-05-18	4	10	1	not_ready	\N
1575	Mads Pedersen	1991-08-27	13	14	4	not_ready	\N
1576	Lene Andersen	1994-12-04	4	6	0	not_ready	\N
1577	Morten Johansen	1990-12-19	11	17	4	ready	\N
1578	Maria Jensen	1964-12-27	19	10	0	not_ready	\N
1579	Gitte Jørgensen	1969-05-29	11	15	0	not_ready	\N
1580	Gitte Hansen	1982-07-21	20	7	0	not_ready	\N
1581	Anne Lindholm	1995-05-18	1	8	2	ready	\N
1582	Martin Pedersen	1960-07-08	13	6	0	not_ready	\N
1583	Niels Rasmussen	1993-02-02	10	17	3	ready	\N
1584	Henrik Madsen	1989-10-10	20	11	1	passed	2020-09-06
1585	Per Petersen	1967-11-06	15	13	0	not_ready	\N
1586	Gitte Jørgensen	1988-05-26	12	14	0	not_ready	\N
1587	Lars Christensen	1977-11-24	8	11	1	passed	2020-07-27
1588	Peter Olsen	1979-06-03	3	4	4	not_ready	\N
1589	Inge Pedersen	1963-03-13	6	16	3	ready	\N
1590	Jacob Petersen	1994-02-23	2	20	0	passed	2020-05-05
1591	Kirsten Nielsen	1982-05-02	15	12	0	not_ready	\N
1592	Stephan Sørensen	1979-07-12	9	20	0	not_ready	\N
1593	Niels Olsen	1953-11-11	3	10	0	not_ready	\N
1594	Daniel Christiansen	1977-10-21	16	14	3	passed	2019-07-23
1595	Tina Thomsen	1992-01-13	2	4	0	not_ready	\N
1596	Anders Pedersen	1959-04-12	15	10	0	not_ready	\N
1597	Søren Christiansen	1952-03-20	8	3	0	not_ready	\N
1598	Helle Larsen	1985-12-21	15	9	0	not_ready	\N
1599	Daniel Jensen	1978-07-01	13	5	0	not_ready	\N
1601	Lone Mortensen	1988-09-11	8	20	0	not_ready	\N
1602	Michael Lindholm	1961-11-08	18	6	1	ready	\N
1603	Anders Petersen	1991-02-02	18	13	0	not_ready	\N
1604	Jan Hansen	1978-08-17	10	15	1	passed	2020-12-26
1605	Gitte Jensen	1990-12-21	3	19	0	not_ready	\N
1606	Mads Madsen	1992-10-15	7	6	0	passed	2021-03-28
1607	Charlotte Olsen	1954-07-01	6	5	2	passed	2020-09-09
1608	Bente Poulsen	1990-03-08	3	4	3	not_ready	\N
1609	Charlotte Madsen	1993-11-08	1	6	4	passed	2021-06-20
1610	Mette Mortensen	1956-11-13	1	16	0	not_ready	\N
1611	Pia Johansen	1992-11-23	4	18	0	passed	2020-03-21
1612	Søren Hansen	1974-01-01	8	3	1	not_ready	\N
1613	Anna Kristensen	1970-07-25	4	12	0	not_ready	\N
1614	Hanne Jensen	1954-11-28	9	13	0	not_ready	\N
1615	Ole Lindholm	1970-05-22	20	15	0	not_ready	\N
1616	Jacob Nielsen	1982-07-25	13	20	2	ready	\N
1617	Rasmus Møller	1968-06-10	17	2	0	not_ready	\N
1618	Michael Hansen	1984-11-09	19	10	0	not_ready	\N
1619	Jens Mortensen	1969-06-05	16	11	0	not_ready	\N
1620	Mette Poulsen	1953-04-12	1	13	2	ready	\N
1621	Helle Mortensen	1994-08-13	14	14	0	not_ready	\N
1622	Stephan Jørgensen	1991-07-10	1	11	0	not_ready	\N
1623	Thomas Lindholm	1987-02-04	8	7	0	not_ready	\N
1624	Lone Jensen	1975-07-26	15	12	2	ready	\N
1625	Michael Nielsen	1968-03-05	2	20	0	not_ready	\N
1626	Susanne Lindholm	1987-07-02	10	6	4	ready	\N
1627	Louise Lindholm	1999-05-17	14	11	0	not_ready	\N
1628	Jacob Pedersen	1965-03-11	9	9	1	ready	\N
1629	Niels Andersen	1991-02-18	1	9	0	not_ready	\N
1630	Jørgen Jørgensen	1964-08-28	20	4	3	not_ready	\N
1631	Ole Christensen	1966-03-06	2	3	0	not_ready	\N
1632	Anne Lindholm	1971-03-22	17	4	0	not_ready	\N
1633	Lars Madsen	1983-05-24	10	1	0	not_ready	\N
1634	Lene Jørgensen	1964-04-14	7	1	0	not_ready	\N
1635	Henrik Lindholm	1976-07-08	4	7	3	ready	\N
1636	Maria Christiansen	1950-10-09	12	19	1	ready	\N
1637	Anders Madsen	1991-05-24	1	2	3	not_ready	\N
1638	Stephan Møller	1958-07-15	1	17	1	not_ready	\N
1639	Martin Larsen	1975-11-23	7	18	1	ready	\N
1640	Inge Christiansen	1956-01-16	11	2	0	not_ready	\N
1641	Helle Sørensen	1984-03-21	19	19	0	not_ready	\N
1642	Jan Madsen	1987-11-01	14	5	0	not_ready	\N
1643	Inge Sørensen	1973-03-14	6	13	0	not_ready	\N
1644	Ole Hansen	1964-05-30	2	3	3	not_ready	\N
1645	Gitte Hansen	1981-01-23	12	11	0	not_ready	\N
1646	Ole Madsen	1998-03-09	12	15	3	ready	\N
1647	Daniel Madsen	1957-11-08	9	10	0	not_ready	\N
1648	Stephan Christensen	1998-09-24	15	16	0	not_ready	\N
1649	Henrik Olsen	1958-06-10	8	6	0	ready	\N
1650	Anna Kristensen	1964-04-13	20	8	0	not_ready	\N
1651	Kirsten Kristensen	1992-04-05	2	13	1	passed	2021-03-18
1652	Tina Mortensen	1960-04-11	10	17	0	not_ready	\N
1653	Kirsten Christiansen	1975-12-30	2	15	3	not_ready	\N
1654	Helle Madsen	1954-06-24	8	3	0	not_ready	\N
1655	Helle Kristensen	1956-05-19	14	10	0	not_ready	\N
1656	Lone Thomsen	1966-03-07	7	5	0	not_ready	\N
1657	Inge Møller	1984-03-05	11	13	0	not_ready	\N
1658	Jacob Johansen	1987-12-25	13	17	4	passed	2019-08-04
1659	Jesper Larsen	1992-06-01	16	5	1	ready	\N
1660	Charlotte Kristensen	1976-05-04	2	19	1	not_ready	\N
1661	Daniel Hansen	1962-06-15	20	9	0	not_ready	\N
1662	Christian Christiansen	1979-12-30	14	7	2	passed	2019-07-28
1663	Per Jørgensen	1984-09-19	2	2	3	ready	\N
1664	Nikolaj Sørensen	1990-09-02	2	19	4	ready	\N
1665	Daniel Poulsen	1961-04-02	2	19	0	not_ready	\N
1666	Mette Larsen	1976-11-19	10	4	0	not_ready	\N
1667	Jesper Jørgensen	1990-04-28	11	10	0	not_ready	\N
1668	Peter Kristensen	1967-09-08	15	15	3	passed	2021-02-01
1669	Camilla Lindholm	1994-08-10	11	20	4	passed	2021-04-13
1670	Thomas Sørensen	1977-04-30	18	15	0	not_ready	\N
1671	Camilla Pedersen	1960-02-22	15	15	0	not_ready	\N
1672	Niels Petersen	1977-08-17	2	14	0	not_ready	\N
1673	Anna Nielsen	1989-05-26	13	8	0	not_ready	\N
1674	Niels Madsen	1951-12-19	17	19	0	not_ready	\N
1675	Pia Andersen	1964-07-03	17	20	3	not_ready	\N
1676	Maria Thomsen	1978-07-22	20	5	1	ready	\N
1677	Ole Sørensen	1973-11-09	14	6	0	not_ready	\N
1678	Helle Thomsen	1988-09-23	1	12	2	passed	2021-08-01
1679	Henrik Olsen	1974-05-09	18	7	2	ready	\N
1680	Hans Mortensen	1972-07-05	9	3	4	passed	2020-02-18
1681	Peter Madsen	1954-04-03	12	15	0	not_ready	\N
1682	Jacob Thomsen	1986-05-11	16	20	0	passed	2020-01-12
1683	Maria Christiansen	1960-09-14	9	7	0	ready	\N
1684	Jacob Christensen	1982-04-17	15	3	0	not_ready	\N
1685	Anne Hansen	1967-05-15	5	1	1	ready	\N
1686	Henrik Møller	1979-09-07	8	2	0	not_ready	\N
1687	Jesper Johansen	1982-11-19	16	5	3	ready	\N
1688	Niels Rasmussen	1959-10-05	14	10	3	not_ready	\N
1689	Stephan Lindholm	1971-05-07	4	7	0	not_ready	\N
1690	Jørgen Kristensen	1961-01-19	3	7	0	not_ready	\N
1691	Mads Johansen	1990-07-11	8	12	4	passed	2021-09-24
1692	Kirsten Sørensen	1993-09-22	10	16	0	not_ready	\N
1693	Mads Andersen	1961-08-15	12	10	4	not_ready	\N
1694	Søren Thomsen	1979-04-21	13	4	0	not_ready	\N
1695	Louise Thomsen	1995-06-18	4	20	0	not_ready	\N
1696	Mads Mortensen	1953-01-19	19	19	3	not_ready	\N
1697	Anna Larsen	1972-04-15	13	2	4	not_ready	\N
1698	Thomas Hansen	1990-03-30	11	8	1	ready	\N
1699	Henrik Jørgensen	1988-09-04	4	11	0	not_ready	\N
1700	Jan Olsen	1987-03-06	8	20	0	not_ready	\N
1701	Hanne Lindholm	1963-08-21	4	12	4	passed	2020-01-08
1702	Jens Jensen	1960-11-01	4	6	0	not_ready	\N
1703	Maria Lindholm	1983-04-15	11	1	3	passed	2019-01-01
1704	Christian Madsen	1998-03-18	16	9	0	not_ready	\N
1705	Daniel Møller	1991-09-01	14	5	0	not_ready	\N
1706	Lone Rasmussen	1981-04-14	8	17	0	not_ready	\N
1707	Thomas Sørensen	1983-09-14	17	13	0	not_ready	\N
1708	Jan Johansen	1974-11-25	5	19	0	not_ready	\N
1709	Karen Sørensen	1980-05-08	5	17	0	not_ready	\N
1710	Lene Møller	1983-05-22	15	5	0	not_ready	\N
1711	Inge Nielsen	1991-11-01	6	12	2	passed	2021-04-29
1712	Anne Madsen	1963-07-29	1	5	1	ready	\N
1713	Marianne Andersen	1992-02-22	11	5	1	not_ready	\N
1714	Lene Lindholm	1976-09-18	2	1	0	not_ready	\N
1715	Gitte Mortensen	1973-04-16	7	6	0	not_ready	\N
1716	Hans Johansen	1959-11-18	20	15	1	not_ready	\N
1717	Jens Larsen	1998-01-11	12	6	0	not_ready	\N
1718	Jørgen Johansen	1986-08-05	3	19	0	not_ready	\N
1719	Tina Madsen	1993-04-06	13	18	4	passed	2019-04-07
1720	Nikolaj Johansen	1968-02-26	4	1	0	not_ready	\N
1721	Stephan Johansen	1958-08-24	13	9	0	passed	2019-04-05
1722	Maria Nielsen	1970-04-16	17	12	0	not_ready	\N
1723	Tina Petersen	1954-04-24	2	13	2	passed	2020-08-13
1724	Nikolaj Hansen	1965-03-12	10	1	1	passed	2020-05-23
1725	Helle Madsen	1953-06-17	16	4	3	ready	\N
1726	Karen Kristensen	1991-07-20	4	1	0	not_ready	\N
1727	Susanne Madsen	1953-03-18	14	3	0	not_ready	\N
1728	Daniel Andersen	1975-07-25	18	9	0	not_ready	\N
1729	Rasmus Petersen	1955-08-27	3	14	0	not_ready	\N
1730	Charlotte Poulsen	1963-08-25	17	5	0	not_ready	\N
1731	Lene Rasmussen	1952-10-09	3	15	2	ready	\N
1732	Pia Mortensen	1989-01-01	4	1	0	not_ready	\N
1733	Christian Poulsen	1980-09-16	16	5	0	ready	\N
1734	Camilla Sørensen	1983-04-02	9	13	0	passed	2020-09-05
1735	Jesper Johansen	1972-11-12	15	17	0	not_ready	\N
1736	Anders Jørgensen	1997-06-24	9	1	1	passed	2019-09-06
1737	Marianne Christensen	1998-04-01	3	6	4	passed	2021-12-06
1738	Morten Johansen	1993-02-04	17	5	0	not_ready	\N
1739	Daniel Christensen	1998-03-16	19	13	0	not_ready	\N
1740	Anne Pedersen	1983-08-19	3	13	0	passed	2020-02-02
1741	Helle Kristensen	1975-01-24	17	8	0	not_ready	\N
1742	Gitte Madsen	1974-11-19	3	19	0	not_ready	\N
1743	Hanne Sørensen	1951-02-26	19	4	0	not_ready	\N
1744	Per Jørgensen	1951-05-28	17	11	0	not_ready	\N
1745	Jørgen Lindholm	1977-12-27	6	4	0	not_ready	\N
1746	Anna Lindholm	1985-11-09	14	18	0	not_ready	\N
1747	Morten Christensen	1999-10-04	12	7	0	not_ready	\N
1748	Peter Nielsen	1959-09-28	6	11	3	ready	\N
1749	Daniel Sørensen	1952-11-13	12	18	0	not_ready	\N
1750	Christian Christensen	1968-11-12	11	7	0	not_ready	\N
1751	Mette Larsen	1981-01-13	11	7	2	ready	\N
1752	Hans Nielsen	1997-11-19	17	9	0	not_ready	\N
1753	Morten Jensen	1994-04-01	5	20	4	ready	\N
1754	Jacob Mortensen	1966-04-22	11	13	4	ready	\N
1755	Peter Madsen	1980-10-10	5	4	2	passed	2018-12-21
1756	Michael Johansen	1980-04-14	4	14	0	not_ready	\N
1757	Jørgen Nielsen	1998-03-26	20	14	0	ready	\N
1758	Martin Sørensen	1987-08-29	9	5	4	ready	\N
1759	Søren Thomsen	1952-10-06	18	6	0	not_ready	\N
1760	Hans Hansen	1983-06-28	8	18	2	passed	2021-03-21
1761	Karen Christensen	1968-02-14	5	2	0	not_ready	\N
1762	Pia Johansen	1980-04-19	14	17	0	not_ready	\N
1763	Jens Thomsen	1980-04-07	16	7	4	passed	2018-12-21
1764	Michael Larsen	1990-02-02	11	20	0	not_ready	\N
1765	Stephan Jensen	1997-09-03	1	4	3	not_ready	\N
1766	Susanne Petersen	1973-08-24	4	19	0	not_ready	\N
1767	Anna Madsen	1950-07-17	18	11	4	ready	\N
1768	Niels Hansen	1989-06-12	14	1	0	not_ready	\N
1769	Mette Hansen	1960-02-10	18	20	0	not_ready	\N
1770	Charlotte Hansen	1980-04-21	12	10	2	passed	2020-01-26
1771	Hanne Poulsen	1991-08-03	9	3	2	passed	2021-11-12
1772	Morten Møller	1969-05-10	10	18	0	not_ready	\N
1773	Anna Hansen	1976-05-23	1	6	2	not_ready	\N
1774	Jesper Johansen	1950-07-01	6	4	3	passed	2019-01-18
1775	Michael Poulsen	1980-11-22	10	14	0	not_ready	\N
1776	Inge Christiansen	1992-03-18	9	3	0	not_ready	\N
1777	Peter Poulsen	1952-04-11	10	13	1	ready	\N
1778	Søren Johansen	1973-11-01	14	19	0	not_ready	\N
1779	Louise Kristensen	1978-06-11	14	11	1	ready	\N
1780	Daniel Lindholm	1957-12-21	12	2	0	not_ready	\N
1781	Anne Larsen	1988-01-19	7	1	1	ready	\N
1782	Christian Christensen	1972-02-10	6	19	0	not_ready	\N
1783	Anne Sørensen	1968-01-09	17	19	0	not_ready	\N
1784	Peter Johansen	1980-06-12	5	9	4	ready	\N
1785	Camilla Christensen	1991-01-22	11	13	0	not_ready	\N
1786	Gitte Rasmussen	1958-12-11	10	8	0	ready	\N
1787	Jacob Madsen	1989-04-24	13	1	4	passed	2021-02-13
1788	Morten Jørgensen	1950-08-20	1	1	4	ready	\N
1789	Stephan Olsen	1966-10-13	9	13	4	passed	2021-11-19
1790	Inge Nielsen	1998-10-05	7	11	0	not_ready	\N
1791	Martin Nielsen	1954-06-22	16	19	0	not_ready	\N
1792	Jan Poulsen	1970-06-21	4	4	1	not_ready	\N
1793	Charlotte Poulsen	1955-02-22	15	6	0	not_ready	\N
1794	Anne Christensen	1982-07-16	17	6	0	not_ready	\N
1795	Anna Pedersen	1970-02-10	4	15	0	not_ready	\N
1796	Peter Kristensen	1990-10-19	3	13	1	passed	2019-12-11
1797	Jan Sørensen	1997-11-03	7	19	4	ready	\N
1798	Lone Lindholm	1989-06-02	16	2	2	passed	2020-03-11
1799	Charlotte Sørensen	1993-06-20	12	4	4	passed	2020-07-28
1800	Jan Hansen	1958-01-06	19	8	0	ready	\N
1801	Kirsten Rasmussen	1986-11-22	9	14	0	not_ready	\N
1802	Inge Christiansen	1950-01-29	15	16	0	not_ready	\N
1803	Christian Madsen	1969-02-12	7	7	0	not_ready	\N
1804	Jesper Møller	1978-12-19	2	18	1	passed	2019-05-10
1805	Thomas Jørgensen	1991-10-12	3	6	0	not_ready	\N
1806	Mads Poulsen	1988-06-20	11	20	0	ready	\N
1807	Mette Lindholm	1963-01-10	18	3	0	not_ready	\N
1808	Helle Kristensen	1960-11-10	17	17	0	not_ready	\N
1809	Martin Pedersen	1991-05-12	11	10	0	not_ready	\N
1810	Kirsten Hansen	1999-04-16	15	11	4	ready	\N
1811	Jørgen Møller	1999-03-10	10	16	4	not_ready	\N
1812	Inge Lindholm	1969-10-14	5	20	0	not_ready	\N
1813	Morten Rasmussen	1981-04-28	2	14	0	not_ready	\N
1814	Jørgen Petersen	1962-07-18	19	14	0	not_ready	\N
1815	Jesper Kristensen	1953-02-09	15	12	0	not_ready	\N
1816	Jørgen Rasmussen	1992-09-02	15	18	0	not_ready	\N
1817	Ole Poulsen	1959-09-18	16	12	0	not_ready	\N
1818	Michael Hansen	1996-04-13	2	8	0	not_ready	\N
1819	Anne Larsen	1955-12-11	1	8	0	not_ready	\N
1820	Inge Lindholm	1964-12-07	2	11	0	not_ready	\N
1821	Jesper Thomsen	1966-05-24	10	7	0	passed	2019-08-23
1822	Lone Nielsen	1975-01-13	9	11	0	passed	2021-11-27
1823	Gitte Nielsen	1997-09-05	12	7	0	ready	\N
1824	Thomas Andersen	1962-09-22	1	1	0	not_ready	\N
1825	Bente Madsen	1972-02-16	2	16	0	not_ready	\N
1826	Karen Sørensen	1998-12-14	19	17	2	passed	2020-03-07
1827	Anne Mortensen	1980-04-13	18	14	0	ready	\N
1828	Charlotte Andersen	1955-07-25	2	2	4	ready	\N
1829	Peter Thomsen	1953-08-21	4	9	0	not_ready	\N
1830	Jan Nielsen	1955-11-16	11	8	0	not_ready	\N
1831	Martin Petersen	1998-07-29	17	6	0	ready	\N
1832	Kirsten Jørgensen	1968-10-06	3	2	0	not_ready	\N
1833	Martin Lindholm	1964-05-05	14	5	0	not_ready	\N
1834	Lone Larsen	1966-07-06	20	14	0	not_ready	\N
1835	Jesper Olsen	1998-07-12	10	3	4	passed	2019-11-19
1836	Martin Johansen	1968-03-19	8	14	0	not_ready	\N
1837	Tina Johansen	1984-04-10	1	19	0	not_ready	\N
1838	Ole Sørensen	1959-12-19	1	19	0	not_ready	\N
1839	Jørgen Jørgensen	1986-05-09	16	18	0	not_ready	\N
1840	Henrik Johansen	1990-06-03	7	3	4	passed	2019-02-26
1841	Daniel Rasmussen	1984-09-07	10	15	1	ready	\N
1842	Daniel Christiansen	1972-12-22	18	1	0	not_ready	\N
1843	Lene Madsen	1964-06-01	19	2	0	not_ready	\N
1844	Anna Christiansen	1959-09-14	13	17	3	passed	2020-12-05
1845	Lars Hansen	1985-07-02	20	6	0	ready	\N
1846	Nikolaj Jørgensen	1962-07-18	7	5	0	not_ready	\N
1847	Susanne Sørensen	1974-03-15	12	3	2	passed	2020-03-17
1848	Christian Kristensen	1968-07-02	14	9	0	passed	2019-04-17
1849	Mette Jørgensen	1972-09-29	14	8	0	not_ready	\N
1850	Lone Poulsen	1987-04-09	15	4	0	not_ready	\N
1851	Ole Johansen	1991-09-21	20	13	1	passed	2019-09-16
1852	Kirsten Lindholm	1962-05-06	3	8	2	ready	\N
1853	Charlotte Poulsen	1997-06-12	14	5	0	not_ready	\N
1854	Jan Sørensen	1958-10-15	19	6	0	passed	2021-09-22
1855	Lars Kristensen	1990-10-10	15	20	2	ready	\N
1856	Jesper Nielsen	1962-04-29	7	20	0	not_ready	\N
1857	Nikolaj Pedersen	1951-03-23	10	8	3	ready	\N
1858	Jan Hansen	1970-08-09	9	12	0	not_ready	\N
1859	Nikolaj Mortensen	1953-05-12	20	5	0	not_ready	\N
1860	Lone Johansen	1984-08-26	17	20	0	not_ready	\N
1861	Nikolaj Christiansen	1997-07-08	19	20	3	ready	\N
1862	Rasmus Møller	1969-02-16	8	8	0	not_ready	\N
1863	Kirsten Johansen	1968-07-21	7	12	0	not_ready	\N
1864	Thomas Sørensen	1978-02-14	6	9	0	not_ready	\N
1865	Nikolaj Christiansen	1952-03-28	19	16	3	ready	\N
1866	Karen Møller	1965-03-24	19	1	0	not_ready	\N
1867	Rasmus Poulsen	1996-08-27	12	1	0	not_ready	\N
1868	Lone Poulsen	1984-12-27	19	13	0	passed	2018-09-19
1869	Per Olsen	1979-06-26	19	6	0	not_ready	\N
1870	Morten Hansen	1969-03-28	12	17	0	not_ready	\N
1871	Mette Andersen	1962-05-14	5	12	4	passed	2019-04-05
1872	Nikolaj Poulsen	1956-09-26	16	17	0	not_ready	\N
1873	Henrik Lindholm	1992-05-28	7	16	0	not_ready	\N
1874	Inge Møller	1955-04-29	12	10	0	ready	\N
1875	Tina Nielsen	1990-12-14	12	3	4	not_ready	\N
1876	Rasmus Poulsen	1988-06-21	4	19	0	ready	\N
1877	Karen Thomsen	1954-04-13	1	4	0	not_ready	\N
1878	Hanne Johansen	1989-07-13	18	6	4	ready	\N
1879	Mette Sørensen	1999-01-05	15	13	2	ready	\N
1880	Gitte Kristensen	1978-04-13	5	19	0	not_ready	\N
1881	Henrik Hansen	1971-04-16	12	20	0	not_ready	\N
1882	Stephan Pedersen	1970-11-20	4	10	0	not_ready	\N
1883	Christian Hansen	1983-10-28	2	11	1	ready	\N
1884	Thomas Kristensen	1976-04-22	11	16	0	not_ready	\N
1885	Jørgen Olsen	1985-02-03	11	13	0	not_ready	\N
1886	Jens Poulsen	1957-08-15	17	9	4	passed	2019-11-27
1887	Nikolaj Johansen	1968-04-30	15	12	2	ready	\N
1888	Pia Petersen	1961-09-13	9	20	0	not_ready	\N
1889	Helle Nielsen	1960-03-04	14	14	3	passed	2020-07-20
1890	Jens Christensen	1974-05-10	4	17	0	not_ready	\N
1891	Hans Møller	1951-11-17	16	10	0	not_ready	\N
1892	Søren Kristensen	1960-05-13	6	19	0	not_ready	\N
1893	Camilla Rasmussen	1964-09-20	11	9	0	not_ready	\N
1894	Christian Sørensen	1996-03-29	2	10	0	passed	2020-08-11
1895	Susanne Jensen	1994-06-15	8	13	2	ready	\N
1896	Per Mortensen	1986-10-03	20	4	0	not_ready	\N
1897	Søren Kristensen	1987-07-06	17	7	0	not_ready	\N
1898	Michael Pedersen	1989-03-01	5	18	0	not_ready	\N
1899	Pia Hansen	1989-11-20	20	4	0	not_ready	\N
1900	Lars Pedersen	1964-04-26	3	10	0	not_ready	\N
1901	Lene Pedersen	1982-11-27	19	12	0	not_ready	\N
1902	Helle Jensen	1952-06-23	9	2	4	ready	\N
1903	Henrik Andersen	1991-10-29	10	15	2	passed	2019-11-29
1904	Niels Andersen	1960-02-07	2	5	0	ready	\N
1905	Kirsten Lindholm	1980-12-02	3	19	1	passed	2021-07-24
1906	Pia Sørensen	1992-03-22	4	14	0	not_ready	\N
1907	Morten Møller	1996-03-15	3	9	3	not_ready	\N
1908	Mette Kristensen	1981-03-15	9	9	0	not_ready	\N
1909	Mads Møller	1982-07-25	19	7	4	not_ready	\N
1910	Søren Møller	1980-11-29	7	19	3	passed	2021-01-30
1911	Ole Lindholm	1957-05-12	17	9	0	not_ready	\N
1912	Gitte Nielsen	1980-04-20	18	4	0	not_ready	\N
1913	Marianne Jørgensen	1980-04-06	3	2	0	not_ready	\N
1914	Marianne Hansen	1955-09-13	8	1	0	ready	\N
1915	Ole Jørgensen	1957-11-30	10	8	0	not_ready	\N
1916	Tina Larsen	1977-04-18	10	9	1	not_ready	\N
1917	Mads Christensen	1987-09-01	3	19	0	not_ready	\N
1918	Jørgen Petersen	1952-01-12	1	5	0	not_ready	\N
1919	Thomas Jensen	1959-07-17	3	14	0	not_ready	\N
1920	Inge Christiansen	1960-09-30	14	18	1	not_ready	\N
1921	Jesper Pedersen	1953-10-02	13	18	0	not_ready	\N
1922	Søren Olsen	1973-09-05	4	5	1	passed	2020-10-19
1923	Peter Madsen	1966-07-15	18	3	0	not_ready	\N
1924	Helle Johansen	1995-07-12	10	3	0	not_ready	\N
1925	Anders Christensen	1953-09-12	8	18	1	not_ready	\N
1926	Thomas Jørgensen	1965-01-12	1	5	0	not_ready	\N
1927	Jens Kristensen	1959-05-13	9	8	4	ready	\N
1928	Peter Sørensen	1971-04-06	12	6	1	not_ready	\N
1929	Hans Poulsen	1970-01-10	19	14	0	not_ready	\N
1930	Thomas Petersen	1989-01-21	20	15	0	not_ready	\N
1931	Henrik Rasmussen	1968-10-30	7	3	0	not_ready	\N
1932	Anders Olsen	1997-07-04	15	11	0	not_ready	\N
1933	Jørgen Thomsen	1989-04-25	13	1	0	not_ready	\N
1934	Louise Christensen	1972-12-14	20	15	0	not_ready	\N
1935	Per Christiansen	1962-10-19	20	2	0	not_ready	\N
1936	Jens Johansen	1991-02-17	19	10	4	ready	\N
1937	Morten Petersen	1988-06-16	8	18	2	not_ready	\N
1938	Hanne Kristensen	1955-03-24	4	13	0	not_ready	\N
1939	Rasmus Nielsen	1974-06-24	9	12	2	ready	\N
1940	Karen Petersen	1974-12-04	15	12	0	passed	2021-05-06
1941	Lone Pedersen	1990-10-21	10	12	0	not_ready	\N
1942	Per Johansen	1993-03-11	3	13	0	ready	\N
1943	Anders Madsen	1954-06-10	16	8	0	not_ready	\N
1944	Pia Møller	1959-02-20	17	5	0	not_ready	\N
1945	Jens Christensen	1990-01-27	7	4	3	passed	2020-02-05
1946	Pia Madsen	1960-03-30	5	16	2	passed	2020-01-22
1947	Kirsten Johansen	1966-09-08	20	11	1	ready	\N
1948	Tina Thomsen	1974-02-03	20	4	0	not_ready	\N
1949	Jens Johansen	1971-08-19	10	17	2	ready	\N
1950	Kirsten Kristensen	1989-06-03	5	20	0	not_ready	\N
1951	Rasmus Thomsen	1979-06-03	13	7	0	not_ready	\N
1952	Anne Nielsen	1956-07-14	17	10	0	not_ready	\N
1953	Lone Jensen	1979-02-17	3	6	0	not_ready	\N
1954	Tina Pedersen	1987-01-06	15	1	4	passed	2019-06-29
1955	Gitte Olsen	1959-12-23	13	20	0	not_ready	\N
1956	Thomas Johansen	1974-09-18	12	9	0	not_ready	\N
1957	Maria Poulsen	1973-02-11	11	9	0	not_ready	\N
1958	Hans Pedersen	1954-04-22	10	14	4	ready	\N
1959	Anna Jørgensen	1980-04-17	18	16	0	not_ready	\N
1960	Christian Johansen	1978-02-14	12	2	0	not_ready	\N
1961	Jens Nielsen	1987-11-17	11	14	2	not_ready	\N
1962	Hanne Olsen	1989-07-12	7	9	0	not_ready	\N
1963	Ole Jørgensen	1976-11-12	16	15	0	not_ready	\N
1964	Helle Thomsen	1998-11-24	5	10	0	passed	2019-06-11
1965	Tina Pedersen	1964-06-28	1	16	0	not_ready	\N
1966	Jørgen Hansen	1986-04-12	2	9	0	not_ready	\N
1967	Lone Møller	1983-07-06	3	14	1	passed	2021-08-16
1968	Anna Mortensen	1984-06-27	16	2	0	not_ready	\N
1969	Pia Christensen	1981-08-25	8	20	0	not_ready	\N
1970	Karen Mortensen	1962-02-11	8	19	2	ready	\N
1971	Hans Hansen	1974-10-26	18	12	2	passed	2019-01-27
1972	Søren Mortensen	1994-03-27	14	2	0	passed	2020-05-11
1973	Helle Møller	1964-05-12	3	7	3	passed	2021-07-05
1974	Anders Madsen	1974-05-25	7	18	0	ready	\N
1975	Anders Christiansen	1965-12-20	14	15	3	passed	2020-09-08
1976	Søren Thomsen	1952-05-09	14	17	0	passed	2021-06-25
1977	Pia Pedersen	1982-06-08	16	11	0	not_ready	\N
1978	Pia Hansen	1954-04-30	20	17	0	not_ready	\N
1979	Søren Olsen	1959-04-29	20	10	0	not_ready	\N
1980	Helle Pedersen	1958-01-11	17	12	0	not_ready	\N
1981	Morten Jørgensen	1951-06-29	2	4	0	not_ready	\N
1982	Maria Møller	1978-08-15	2	18	0	not_ready	\N
1983	Martin Rasmussen	1976-03-28	6	7	4	ready	\N
1984	Nikolaj Andersen	1960-04-04	15	18	0	not_ready	\N
1985	Hans Johansen	1981-11-16	7	11	3	ready	\N
1986	Michael Møller	1972-08-25	3	20	0	not_ready	\N
1987	Morten Christensen	1973-06-11	10	15	0	not_ready	\N
1988	Søren Hansen	1964-12-06	15	9	0	not_ready	\N
1989	Stephan Christensen	1987-06-08	15	2	4	not_ready	\N
1990	Anders Christensen	1977-06-09	19	2	0	not_ready	\N
1991	Nikolaj Thomsen	1983-11-09	6	10	4	ready	\N
1992	Mads Christensen	1968-01-08	8	5	1	passed	2019-09-08
1993	Maria Kristensen	1971-12-02	16	18	0	not_ready	\N
1994	Jacob Andersen	1968-01-03	1	11	0	not_ready	\N
1995	Gitte Møller	1985-02-18	19	2	0	not_ready	\N
1996	Lone Rasmussen	1977-01-13	6	11	0	passed	2020-09-18
1997	Anders Christiansen	1954-06-30	13	13	0	not_ready	\N
1998	Jens Nielsen	1970-09-08	10	8	0	not_ready	\N
1999	Helle Christiansen	1993-04-15	13	20	1	ready	\N
2000	Stephan Christensen	1997-02-06	18	18	0	not_ready	\N
\.


--
-- Data for Name: employees; Type: TABLE DATA; Schema: driving_school; Owner: stephan
--

COPY driving_school.employees (emp, name, title) FROM stdin;
1	Michael Nielsen	instructor
2	Søren Johansen	instructor
3	Martin Hansen	instructor
4	Lene Jensen	instructor
5	Maria Johansen	instructor
6	Lars Kristensen	instructor
7	Søren Jørgensen	instructor
8	Tina Poulsen	instructor
9	Lars Sørensen	instructor
10	Anne Kristensen	instructor
11	Henrik Jørgensen	instructor
12	Daniel Petersen	instructor
13	Martin Madsen	instructor
14	Morten Sørensen	instructor
15	Christian Thomsen	instructor
16	Lene Christensen	instructor
17	Anna Christensen	instructor
18	Pia Poulsen	instructor
19	Lars Lindholm	instructor
20	Bente Olsen	instructor
21	Lene Lindholm	administrative_staff
22	Lars Hansen	administrative_staff
23	Tina Johansen	administrative_staff
24	Christian Nielsen	auto_technicians
25	Pia Kristensen	auto_technicians
26	Anne Madsen	auto_technicians
27	Daniel Madsen	auto_technicians
\.


--
-- Data for Name: interviews; Type: TABLE DATA; Schema: driving_school; Owner: stephan
--

COPY driving_school.interviews (interview, employee, client, start) FROM stdin;
1	21	1	2017-04-01 00:00:00
2	22	2	2018-08-24 00:00:00
3	22	3	2018-02-11 00:00:00
4	23	4	2018-05-03 00:00:00
5	23	5	2019-06-04 00:00:00
6	21	6	2017-02-19 00:00:00
7	21	7	2018-04-19 00:00:00
8	23	8	2018-05-11 00:00:00
9	23	9	2018-10-05 00:00:00
10	23	10	2018-04-11 00:00:00
11	22	11	2019-07-28 00:00:00
12	23	12	2017-08-03 00:00:00
13	23	13	2018-04-01 00:00:00
14	23	14	2019-08-01 00:00:00
15	23	15	2017-02-03 00:00:00
16	23	16	2017-10-30 00:00:00
17	21	17	2017-05-24 00:00:00
18	22	18	2017-06-28 00:00:00
19	21	19	2019-02-25 00:00:00
20	22	20	2019-07-13 00:00:00
21	22	21	2018-09-24 00:00:00
22	22	22	2018-08-04 00:00:00
23	23	23	2019-10-17 00:00:00
24	23	24	2017-08-29 00:00:00
25	21	25	2019-05-05 00:00:00
26	22	26	2017-02-07 00:00:00
27	22	27	2019-09-18 00:00:00
28	22	28	2017-05-10 00:00:00
29	23	29	2019-02-04 00:00:00
30	22	30	2018-07-18 00:00:00
31	23	31	2019-04-08 00:00:00
32	21	32	2018-10-15 00:00:00
33	22	33	2017-09-10 00:00:00
34	22	34	2018-03-23 00:00:00
35	23	35	2018-09-16 00:00:00
36	23	36	2017-12-28 00:00:00
37	22	37	2019-05-13 00:00:00
38	23	38	2019-06-07 00:00:00
39	21	39	2017-06-30 00:00:00
40	22	40	2019-01-14 00:00:00
41	22	41	2019-01-05 00:00:00
42	22	42	2018-09-01 00:00:00
43	21	43	2018-05-24 00:00:00
44	23	44	2018-02-16 00:00:00
45	23	45	2019-05-24 00:00:00
46	23	46	2017-07-17 00:00:00
47	23	47	2017-01-18 00:00:00
48	21	48	2018-05-18 00:00:00
49	21	49	2017-11-01 00:00:00
50	22	50	2019-02-02 00:00:00
51	22	51	2018-11-07 00:00:00
52	23	52	2017-10-26 00:00:00
53	21	53	2017-02-03 00:00:00
54	21	54	2018-12-29 00:00:00
55	21	55	2017-06-08 00:00:00
56	23	56	2019-12-11 00:00:00
57	23	57	2017-01-09 00:00:00
58	22	58	2019-04-17 00:00:00
59	22	59	2019-05-29 00:00:00
60	21	60	2017-08-22 00:00:00
61	22	61	2018-04-03 00:00:00
62	22	62	2017-10-18 00:00:00
63	22	63	2017-06-22 00:00:00
64	22	64	2018-08-13 00:00:00
65	22	65	2019-09-05 00:00:00
66	21	66	2018-02-07 00:00:00
67	22	67	2019-02-10 00:00:00
68	23	68	2018-07-29 00:00:00
69	22	69	2019-10-25 00:00:00
70	22	70	2018-10-05 00:00:00
71	21	71	2018-09-27 00:00:00
72	22	72	2019-04-21 00:00:00
73	23	73	2017-07-07 00:00:00
74	22	74	2017-12-12 00:00:00
75	22	75	2018-12-30 00:00:00
76	22	76	2018-07-20 00:00:00
77	23	77	2017-01-06 00:00:00
78	23	78	2017-05-22 00:00:00
79	22	79	2018-05-11 00:00:00
80	22	80	2017-09-04 00:00:00
81	22	81	2018-01-09 00:00:00
82	21	82	2019-10-26 00:00:00
83	21	83	2017-03-06 00:00:00
84	21	84	2018-11-13 00:00:00
85	23	85	2019-08-21 00:00:00
86	23	86	2019-11-28 00:00:00
87	22	87	2017-06-24 00:00:00
88	22	88	2018-06-01 00:00:00
89	22	89	2018-06-16 00:00:00
90	23	90	2019-04-06 00:00:00
91	22	91	2017-02-11 00:00:00
92	23	92	2019-04-11 00:00:00
93	23	93	2019-06-17 00:00:00
94	23	94	2019-03-10 00:00:00
95	21	95	2018-10-13 00:00:00
96	23	96	2017-05-26 00:00:00
97	23	97	2019-09-03 00:00:00
98	23	98	2017-09-27 00:00:00
99	21	99	2017-10-19 00:00:00
100	21	100	2017-11-18 00:00:00
101	21	101	2017-12-09 00:00:00
102	22	102	2018-02-09 00:00:00
103	23	103	2019-11-19 00:00:00
104	22	104	2019-07-29 00:00:00
105	21	105	2018-02-21 00:00:00
106	21	106	2017-08-13 00:00:00
107	22	107	2019-01-07 00:00:00
108	22	108	2017-09-16 00:00:00
109	22	109	2018-11-22 00:00:00
110	21	110	2017-06-08 00:00:00
111	23	111	2019-05-06 00:00:00
112	22	112	2019-02-02 00:00:00
113	21	113	2017-11-07 00:00:00
114	23	114	2018-09-25 00:00:00
115	23	115	2017-02-23 00:00:00
116	22	116	2018-01-15 00:00:00
117	22	117	2017-01-08 00:00:00
118	22	118	2018-05-15 00:00:00
119	22	119	2018-03-22 00:00:00
120	21	120	2019-12-14 00:00:00
121	23	121	2018-12-07 00:00:00
122	21	122	2018-06-30 00:00:00
123	23	123	2017-06-03 00:00:00
124	22	124	2018-02-11 00:00:00
125	22	125	2018-08-04 00:00:00
126	21	126	2019-01-10 00:00:00
127	23	127	2017-08-05 00:00:00
128	21	128	2017-09-15 00:00:00
129	23	129	2017-05-04 00:00:00
130	23	130	2019-03-08 00:00:00
131	23	131	2017-03-19 00:00:00
132	23	132	2019-12-05 00:00:00
133	23	133	2019-02-09 00:00:00
134	23	134	2017-12-12 00:00:00
135	22	135	2017-08-01 00:00:00
136	21	136	2017-05-29 00:00:00
137	23	137	2019-03-15 00:00:00
138	21	138	2018-10-11 00:00:00
139	21	139	2019-04-18 00:00:00
140	23	140	2018-12-09 00:00:00
141	21	141	2018-05-17 00:00:00
142	23	142	2017-08-02 00:00:00
143	23	143	2019-04-22 00:00:00
144	21	144	2019-11-01 00:00:00
145	21	145	2019-12-28 00:00:00
146	21	146	2017-05-11 00:00:00
147	21	147	2018-10-29 00:00:00
148	21	148	2019-04-21 00:00:00
149	21	149	2019-07-06 00:00:00
150	22	150	2018-04-23 00:00:00
151	21	151	2017-10-02 00:00:00
152	21	152	2018-02-07 00:00:00
153	23	153	2018-09-25 00:00:00
154	21	154	2019-01-27 00:00:00
155	23	155	2019-06-29 00:00:00
156	21	156	2018-07-19 00:00:00
157	21	157	2019-08-15 00:00:00
158	22	158	2019-12-19 00:00:00
159	23	159	2017-02-14 00:00:00
160	21	160	2017-06-15 00:00:00
161	22	161	2018-05-10 00:00:00
162	22	162	2017-08-11 00:00:00
163	22	163	2019-06-06 00:00:00
164	23	164	2019-05-13 00:00:00
165	22	165	2017-06-20 00:00:00
166	21	166	2018-01-02 00:00:00
167	23	167	2017-03-13 00:00:00
168	21	168	2017-02-22 00:00:00
169	22	169	2019-07-12 00:00:00
170	21	170	2017-10-09 00:00:00
171	23	171	2019-11-01 00:00:00
172	23	172	2019-03-15 00:00:00
173	23	173	2018-11-15 00:00:00
174	23	174	2018-01-17 00:00:00
175	23	175	2017-07-05 00:00:00
176	22	176	2018-05-29 00:00:00
177	23	177	2018-10-13 00:00:00
178	23	178	2019-02-03 00:00:00
179	21	179	2018-11-06 00:00:00
180	22	180	2018-04-13 00:00:00
181	21	181	2018-06-07 00:00:00
182	22	182	2019-01-26 00:00:00
183	22	183	2019-08-01 00:00:00
184	21	184	2018-11-19 00:00:00
185	23	185	2017-01-16 00:00:00
186	22	186	2018-01-17 00:00:00
187	23	187	2017-06-12 00:00:00
188	21	188	2017-07-13 00:00:00
189	23	189	2018-04-20 00:00:00
190	23	190	2018-09-04 00:00:00
191	23	191	2018-04-22 00:00:00
192	21	192	2017-04-09 00:00:00
193	21	193	2019-11-04 00:00:00
194	23	194	2018-12-13 00:00:00
195	22	195	2018-12-19 00:00:00
196	22	196	2018-03-14 00:00:00
197	23	197	2019-02-14 00:00:00
198	22	198	2018-02-02 00:00:00
199	21	199	2019-03-12 00:00:00
200	21	200	2019-03-09 00:00:00
201	22	201	2018-06-19 00:00:00
202	23	202	2018-12-23 00:00:00
203	22	203	2018-02-04 00:00:00
204	23	204	2018-11-23 00:00:00
205	21	205	2017-05-06 00:00:00
206	21	206	2019-05-29 00:00:00
207	23	207	2019-03-18 00:00:00
208	23	208	2018-10-27 00:00:00
209	22	209	2017-11-18 00:00:00
210	23	210	2017-01-13 00:00:00
211	22	211	2017-12-30 00:00:00
212	23	212	2019-11-04 00:00:00
213	22	213	2018-04-22 00:00:00
214	23	214	2019-01-14 00:00:00
215	22	215	2019-11-03 00:00:00
216	22	216	2018-07-28 00:00:00
217	22	217	2017-02-14 00:00:00
218	23	218	2017-06-03 00:00:00
219	21	219	2018-11-09 00:00:00
220	23	220	2019-03-23 00:00:00
221	22	221	2018-02-07 00:00:00
222	22	222	2017-04-12 00:00:00
223	22	223	2018-08-16 00:00:00
224	23	224	2017-10-17 00:00:00
225	23	225	2019-02-15 00:00:00
226	23	226	2018-03-12 00:00:00
227	22	227	2018-04-10 00:00:00
228	22	228	2018-12-22 00:00:00
229	21	229	2017-06-24 00:00:00
230	23	230	2018-12-29 00:00:00
231	21	231	2017-12-05 00:00:00
232	22	232	2018-06-27 00:00:00
233	22	233	2018-09-17 00:00:00
234	22	234	2017-09-04 00:00:00
235	23	235	2017-12-14 00:00:00
236	21	236	2017-01-20 00:00:00
237	22	237	2019-08-17 00:00:00
238	23	238	2018-09-29 00:00:00
239	22	239	2018-04-24 00:00:00
240	21	240	2019-12-04 00:00:00
241	21	241	2017-11-28 00:00:00
242	23	242	2019-09-26 00:00:00
243	23	243	2017-04-10 00:00:00
244	21	244	2019-03-19 00:00:00
245	22	245	2019-09-07 00:00:00
246	23	246	2017-06-08 00:00:00
247	22	247	2019-03-20 00:00:00
248	22	248	2017-07-24 00:00:00
249	21	249	2018-12-22 00:00:00
250	21	250	2019-04-23 00:00:00
251	21	251	2017-10-04 00:00:00
252	21	252	2019-03-02 00:00:00
253	22	253	2018-08-26 00:00:00
254	21	254	2017-11-28 00:00:00
255	22	255	2017-09-29 00:00:00
256	23	256	2019-08-06 00:00:00
257	21	257	2018-11-25 00:00:00
258	22	258	2017-09-25 00:00:00
259	23	259	2018-01-07 00:00:00
260	21	260	2019-09-20 00:00:00
261	21	261	2017-06-18 00:00:00
262	23	262	2018-10-22 00:00:00
263	21	263	2017-02-24 00:00:00
264	22	264	2017-01-20 00:00:00
265	21	265	2018-08-20 00:00:00
266	21	266	2018-02-17 00:00:00
267	23	267	2018-05-16 00:00:00
268	22	268	2017-05-15 00:00:00
269	22	269	2018-12-26 00:00:00
270	22	270	2018-05-30 00:00:00
271	21	271	2019-03-13 00:00:00
272	23	272	2019-07-10 00:00:00
273	21	273	2017-01-25 00:00:00
274	22	274	2019-09-24 00:00:00
275	23	275	2017-09-08 00:00:00
276	23	276	2018-09-18 00:00:00
277	22	277	2019-10-13 00:00:00
278	22	278	2019-09-17 00:00:00
279	22	279	2017-08-12 00:00:00
280	22	280	2017-02-25 00:00:00
281	23	281	2018-06-28 00:00:00
282	22	282	2017-10-17 00:00:00
283	21	283	2017-11-13 00:00:00
284	22	284	2019-02-22 00:00:00
285	22	285	2019-07-03 00:00:00
286	22	286	2019-08-27 00:00:00
287	22	287	2017-09-10 00:00:00
288	23	288	2019-08-03 00:00:00
289	22	289	2018-09-19 00:00:00
290	21	290	2019-01-07 00:00:00
291	23	291	2017-02-16 00:00:00
292	21	292	2019-11-15 00:00:00
293	23	293	2019-06-19 00:00:00
294	22	294	2019-09-15 00:00:00
295	23	295	2018-07-08 00:00:00
296	21	296	2019-12-17 00:00:00
297	21	297	2019-06-15 00:00:00
298	21	298	2019-06-16 00:00:00
299	23	299	2018-05-30 00:00:00
300	21	300	2017-07-10 00:00:00
301	23	301	2018-07-09 00:00:00
302	21	302	2019-04-15 00:00:00
303	21	303	2019-01-03 00:00:00
304	22	304	2018-01-30 00:00:00
305	22	305	2019-06-05 00:00:00
306	23	306	2018-03-13 00:00:00
307	21	307	2018-10-11 00:00:00
308	21	308	2019-12-08 00:00:00
309	22	309	2017-06-08 00:00:00
310	22	310	2019-03-04 00:00:00
311	22	311	2019-11-29 00:00:00
312	23	312	2019-07-21 00:00:00
313	21	313	2017-01-15 00:00:00
314	21	314	2018-05-06 00:00:00
315	22	315	2018-12-11 00:00:00
316	23	316	2018-02-13 00:00:00
317	22	317	2017-09-16 00:00:00
318	22	318	2018-02-18 00:00:00
319	22	319	2019-03-27 00:00:00
320	22	320	2019-12-30 00:00:00
321	21	321	2019-02-12 00:00:00
322	22	322	2017-03-08 00:00:00
323	23	323	2017-08-29 00:00:00
324	23	324	2017-06-25 00:00:00
325	23	325	2019-01-29 00:00:00
326	21	326	2019-07-03 00:00:00
327	23	327	2019-01-18 00:00:00
328	22	328	2018-02-03 00:00:00
329	22	329	2018-03-27 00:00:00
330	23	330	2017-04-27 00:00:00
331	22	331	2017-06-27 00:00:00
332	23	332	2019-06-17 00:00:00
333	23	333	2018-07-30 00:00:00
334	21	334	2017-01-27 00:00:00
335	22	335	2017-09-29 00:00:00
336	23	336	2018-06-28 00:00:00
337	22	337	2019-02-26 00:00:00
338	23	338	2018-06-29 00:00:00
339	22	339	2017-02-03 00:00:00
340	23	340	2018-02-02 00:00:00
341	22	341	2017-11-30 00:00:00
342	21	342	2019-10-01 00:00:00
343	23	343	2017-04-20 00:00:00
344	23	344	2019-09-05 00:00:00
345	22	345	2019-01-11 00:00:00
346	23	346	2018-10-20 00:00:00
347	22	347	2018-07-06 00:00:00
348	21	348	2018-04-02 00:00:00
349	22	349	2019-05-26 00:00:00
350	22	350	2017-06-25 00:00:00
351	21	351	2017-09-22 00:00:00
352	23	352	2019-07-25 00:00:00
353	21	353	2017-10-14 00:00:00
354	23	354	2017-02-15 00:00:00
355	21	355	2017-01-02 00:00:00
356	23	356	2018-04-30 00:00:00
357	22	357	2019-09-03 00:00:00
358	22	358	2019-03-18 00:00:00
359	21	359	2017-01-23 00:00:00
360	23	360	2017-02-21 00:00:00
361	22	361	2018-07-01 00:00:00
362	23	362	2018-02-19 00:00:00
363	23	363	2018-11-09 00:00:00
364	22	364	2019-04-14 00:00:00
365	23	365	2019-05-27 00:00:00
366	23	366	2017-05-15 00:00:00
367	23	367	2017-03-16 00:00:00
368	22	368	2017-10-23 00:00:00
369	22	369	2019-06-03 00:00:00
370	23	370	2019-08-17 00:00:00
371	23	371	2017-06-01 00:00:00
372	22	372	2019-10-06 00:00:00
373	23	373	2019-07-05 00:00:00
374	22	374	2019-06-08 00:00:00
375	23	375	2019-05-11 00:00:00
376	23	376	2017-12-15 00:00:00
377	23	377	2019-02-04 00:00:00
378	23	378	2018-09-15 00:00:00
379	22	379	2019-12-16 00:00:00
380	23	380	2019-06-13 00:00:00
381	22	381	2017-01-18 00:00:00
382	21	382	2019-11-10 00:00:00
383	21	383	2018-09-16 00:00:00
384	21	384	2017-10-10 00:00:00
385	21	385	2018-04-18 00:00:00
386	21	386	2019-09-25 00:00:00
387	22	387	2018-01-29 00:00:00
388	21	388	2019-02-10 00:00:00
389	22	389	2018-03-30 00:00:00
390	22	390	2018-05-08 00:00:00
391	21	391	2018-11-30 00:00:00
392	22	392	2018-07-25 00:00:00
393	21	393	2018-06-11 00:00:00
394	22	394	2017-06-08 00:00:00
395	23	395	2018-06-08 00:00:00
396	23	396	2018-03-21 00:00:00
397	23	397	2017-11-20 00:00:00
398	22	398	2019-09-14 00:00:00
399	23	399	2017-01-02 00:00:00
400	21	400	2017-11-29 00:00:00
401	21	401	2019-08-20 00:00:00
402	22	402	2018-03-04 00:00:00
403	21	403	2019-11-08 00:00:00
404	21	404	2019-02-24 00:00:00
405	21	405	2018-10-19 00:00:00
406	21	406	2017-02-08 00:00:00
407	22	407	2018-01-19 00:00:00
408	22	408	2019-09-24 00:00:00
409	23	409	2017-04-22 00:00:00
410	21	410	2018-01-02 00:00:00
411	22	411	2019-12-24 00:00:00
412	23	412	2017-09-03 00:00:00
413	23	413	2019-09-13 00:00:00
414	23	414	2017-03-16 00:00:00
415	21	415	2018-07-26 00:00:00
416	21	416	2019-05-06 00:00:00
417	22	417	2018-01-11 00:00:00
418	22	418	2018-03-20 00:00:00
419	23	419	2018-11-30 00:00:00
420	21	420	2019-06-27 00:00:00
421	21	421	2017-05-29 00:00:00
422	23	422	2017-06-01 00:00:00
423	22	423	2017-05-11 00:00:00
424	21	424	2018-03-22 00:00:00
425	22	425	2018-07-02 00:00:00
426	23	426	2018-11-28 00:00:00
427	22	427	2018-09-28 00:00:00
428	21	428	2018-08-21 00:00:00
429	21	429	2017-12-18 00:00:00
430	23	430	2018-11-17 00:00:00
431	21	431	2019-07-01 00:00:00
432	22	432	2019-03-20 00:00:00
433	22	433	2017-03-01 00:00:00
434	21	434	2018-01-01 00:00:00
435	21	435	2017-03-04 00:00:00
436	22	436	2018-02-19 00:00:00
437	21	437	2018-09-08 00:00:00
438	22	438	2018-09-22 00:00:00
439	22	439	2019-02-11 00:00:00
440	23	440	2018-09-14 00:00:00
441	21	441	2019-11-05 00:00:00
442	21	442	2019-01-07 00:00:00
443	22	443	2019-04-08 00:00:00
444	22	444	2017-10-10 00:00:00
445	22	445	2017-10-23 00:00:00
446	23	446	2017-03-08 00:00:00
447	22	447	2017-09-30 00:00:00
448	21	448	2018-05-29 00:00:00
449	23	449	2017-10-14 00:00:00
450	23	450	2018-01-22 00:00:00
451	22	451	2019-09-21 00:00:00
452	21	452	2019-07-20 00:00:00
453	23	453	2019-09-07 00:00:00
454	23	454	2017-08-02 00:00:00
455	22	455	2019-02-19 00:00:00
456	23	456	2019-09-20 00:00:00
457	21	457	2017-06-26 00:00:00
458	21	458	2017-10-17 00:00:00
459	22	459	2018-04-26 00:00:00
460	22	460	2018-02-23 00:00:00
461	23	461	2017-02-22 00:00:00
462	23	462	2019-04-12 00:00:00
463	21	463	2017-04-26 00:00:00
464	21	464	2018-08-25 00:00:00
465	21	465	2018-03-19 00:00:00
466	22	466	2018-08-04 00:00:00
467	22	467	2017-03-03 00:00:00
468	23	468	2019-05-01 00:00:00
469	21	469	2017-08-28 00:00:00
470	22	470	2019-11-30 00:00:00
471	23	471	2019-08-29 00:00:00
472	23	472	2019-01-20 00:00:00
473	21	473	2019-07-13 00:00:00
474	23	474	2017-09-24 00:00:00
475	21	475	2019-09-29 00:00:00
476	22	476	2017-07-16 00:00:00
477	23	477	2018-07-18 00:00:00
478	22	478	2019-01-23 00:00:00
479	22	479	2017-06-24 00:00:00
480	23	480	2018-08-26 00:00:00
481	21	481	2018-08-14 00:00:00
482	22	482	2019-05-16 00:00:00
483	23	483	2017-04-18 00:00:00
484	21	484	2018-05-02 00:00:00
485	22	485	2019-02-15 00:00:00
486	22	486	2019-03-27 00:00:00
487	22	487	2019-03-11 00:00:00
488	23	488	2019-05-23 00:00:00
489	21	489	2019-07-08 00:00:00
490	21	490	2017-12-12 00:00:00
491	22	491	2018-08-02 00:00:00
492	21	492	2018-06-26 00:00:00
493	23	493	2019-04-06 00:00:00
494	21	494	2019-11-30 00:00:00
495	22	495	2018-11-01 00:00:00
496	23	496	2019-03-04 00:00:00
497	23	497	2018-06-04 00:00:00
498	23	498	2017-08-01 00:00:00
499	22	499	2019-01-19 00:00:00
500	23	500	2018-06-29 00:00:00
501	23	501	2018-10-21 00:00:00
502	23	502	2019-09-08 00:00:00
503	22	503	2019-05-21 00:00:00
504	23	504	2019-02-03 00:00:00
505	23	505	2019-03-21 00:00:00
506	23	506	2019-09-19 00:00:00
507	21	507	2018-07-03 00:00:00
508	23	508	2019-12-23 00:00:00
509	22	509	2019-04-05 00:00:00
510	22	510	2017-05-23 00:00:00
511	23	511	2017-06-24 00:00:00
512	22	512	2019-04-18 00:00:00
513	22	513	2019-12-06 00:00:00
514	21	514	2017-10-18 00:00:00
515	21	515	2017-06-06 00:00:00
516	23	516	2017-01-21 00:00:00
517	22	517	2019-02-04 00:00:00
518	23	518	2019-02-04 00:00:00
519	23	519	2017-01-01 00:00:00
520	21	520	2017-02-22 00:00:00
521	21	521	2019-07-24 00:00:00
522	23	522	2019-09-10 00:00:00
523	23	523	2018-08-23 00:00:00
524	21	524	2017-01-29 00:00:00
525	23	525	2018-10-06 00:00:00
526	21	526	2017-03-15 00:00:00
527	22	527	2018-12-28 00:00:00
528	21	528	2018-12-27 00:00:00
529	22	529	2017-02-05 00:00:00
530	22	530	2019-02-25 00:00:00
531	23	531	2019-08-29 00:00:00
532	21	532	2019-08-25 00:00:00
533	22	533	2017-03-06 00:00:00
534	21	534	2019-05-03 00:00:00
535	22	535	2018-11-16 00:00:00
536	22	536	2019-06-12 00:00:00
537	22	537	2018-12-12 00:00:00
538	23	538	2017-11-08 00:00:00
539	21	539	2017-07-21 00:00:00
540	23	540	2017-07-14 00:00:00
541	22	541	2018-09-03 00:00:00
542	23	542	2018-12-09 00:00:00
543	21	543	2019-06-03 00:00:00
544	21	544	2019-03-18 00:00:00
545	23	545	2018-02-09 00:00:00
546	22	546	2018-03-27 00:00:00
547	23	547	2017-10-24 00:00:00
548	22	548	2018-06-04 00:00:00
549	22	549	2017-05-28 00:00:00
550	23	550	2018-04-25 00:00:00
551	21	551	2017-07-20 00:00:00
552	23	552	2017-09-04 00:00:00
553	21	553	2019-09-13 00:00:00
554	23	554	2017-11-27 00:00:00
555	22	555	2017-12-10 00:00:00
556	21	556	2018-04-04 00:00:00
557	21	557	2019-09-07 00:00:00
558	23	558	2019-12-23 00:00:00
559	21	559	2017-11-22 00:00:00
560	22	560	2018-05-11 00:00:00
561	21	561	2018-12-12 00:00:00
562	22	562	2018-08-10 00:00:00
563	23	563	2019-03-15 00:00:00
564	22	564	2019-10-19 00:00:00
565	21	565	2018-04-21 00:00:00
566	21	566	2018-10-28 00:00:00
567	23	567	2019-02-02 00:00:00
568	23	568	2018-11-04 00:00:00
569	23	569	2019-08-23 00:00:00
570	21	570	2017-03-28 00:00:00
571	21	571	2017-09-15 00:00:00
572	21	572	2017-05-01 00:00:00
573	23	573	2019-05-18 00:00:00
574	21	574	2018-07-08 00:00:00
575	21	575	2017-08-12 00:00:00
576	23	576	2018-10-20 00:00:00
577	22	577	2017-02-07 00:00:00
578	22	578	2018-09-28 00:00:00
579	21	579	2018-07-15 00:00:00
580	22	580	2018-08-03 00:00:00
581	23	581	2018-04-16 00:00:00
582	22	582	2019-11-15 00:00:00
583	22	583	2019-12-09 00:00:00
584	22	584	2018-02-11 00:00:00
585	21	585	2018-11-13 00:00:00
586	22	586	2019-11-19 00:00:00
587	22	587	2017-09-28 00:00:00
588	23	588	2019-10-18 00:00:00
589	21	589	2017-12-08 00:00:00
590	22	590	2018-08-22 00:00:00
591	22	591	2018-11-06 00:00:00
592	22	592	2019-11-13 00:00:00
593	21	593	2017-09-20 00:00:00
594	23	594	2018-02-12 00:00:00
595	22	595	2018-05-30 00:00:00
596	23	596	2017-12-03 00:00:00
597	22	597	2019-10-11 00:00:00
598	23	598	2019-05-04 00:00:00
599	22	599	2018-01-14 00:00:00
600	22	600	2019-12-21 00:00:00
601	23	601	2019-03-22 00:00:00
602	22	602	2018-09-04 00:00:00
603	21	603	2019-06-19 00:00:00
604	23	604	2019-07-21 00:00:00
605	22	605	2019-03-29 00:00:00
606	21	606	2019-06-17 00:00:00
607	21	607	2019-07-28 00:00:00
608	21	608	2018-08-30 00:00:00
609	23	609	2017-04-27 00:00:00
610	23	610	2017-03-13 00:00:00
611	21	611	2018-05-17 00:00:00
612	21	612	2018-06-06 00:00:00
613	23	613	2018-09-23 00:00:00
614	23	614	2019-01-12 00:00:00
615	21	615	2018-07-22 00:00:00
616	22	616	2017-01-20 00:00:00
617	21	617	2017-05-01 00:00:00
618	23	618	2018-12-02 00:00:00
619	22	619	2018-03-04 00:00:00
620	22	620	2018-03-07 00:00:00
621	21	621	2017-05-16 00:00:00
622	23	622	2017-02-02 00:00:00
623	23	623	2019-04-16 00:00:00
624	23	624	2018-05-03 00:00:00
625	23	625	2018-03-15 00:00:00
626	21	626	2019-12-26 00:00:00
627	23	627	2017-09-07 00:00:00
628	23	628	2017-03-25 00:00:00
629	21	629	2018-12-13 00:00:00
630	23	630	2019-01-07 00:00:00
631	22	631	2018-06-13 00:00:00
632	22	632	2017-05-18 00:00:00
633	22	633	2019-02-03 00:00:00
634	21	634	2019-03-09 00:00:00
635	22	635	2019-04-29 00:00:00
636	22	636	2018-01-07 00:00:00
637	21	637	2019-10-12 00:00:00
638	23	638	2017-01-13 00:00:00
639	21	639	2018-11-26 00:00:00
640	21	640	2019-06-09 00:00:00
641	21	641	2017-01-18 00:00:00
642	22	642	2017-10-11 00:00:00
643	22	643	2017-07-10 00:00:00
644	21	644	2017-01-15 00:00:00
645	23	645	2019-11-12 00:00:00
646	22	646	2019-09-27 00:00:00
647	23	647	2018-12-23 00:00:00
648	22	648	2017-09-25 00:00:00
649	23	649	2019-05-10 00:00:00
650	23	650	2017-10-16 00:00:00
651	21	651	2018-08-23 00:00:00
652	21	652	2018-03-03 00:00:00
653	23	653	2019-12-05 00:00:00
654	23	654	2017-11-18 00:00:00
655	22	655	2019-06-10 00:00:00
656	22	656	2018-02-17 00:00:00
657	21	657	2019-11-08 00:00:00
658	23	658	2017-07-03 00:00:00
659	23	659	2017-07-03 00:00:00
660	22	660	2017-11-26 00:00:00
661	23	661	2019-10-06 00:00:00
662	21	662	2018-03-04 00:00:00
663	21	663	2018-11-29 00:00:00
664	23	664	2017-09-26 00:00:00
665	21	665	2019-02-12 00:00:00
666	22	666	2019-08-23 00:00:00
667	21	667	2019-02-03 00:00:00
668	23	668	2018-05-15 00:00:00
669	22	669	2018-12-06 00:00:00
670	21	670	2017-07-22 00:00:00
671	23	671	2017-02-25 00:00:00
672	22	672	2019-05-29 00:00:00
673	21	673	2019-05-05 00:00:00
674	23	674	2018-08-23 00:00:00
675	22	675	2019-12-10 00:00:00
676	23	676	2018-09-03 00:00:00
677	22	677	2018-12-02 00:00:00
678	21	678	2019-12-27 00:00:00
679	23	679	2019-11-18 00:00:00
680	23	680	2018-03-01 00:00:00
681	23	681	2017-08-22 00:00:00
682	21	682	2019-12-04 00:00:00
683	21	683	2019-01-09 00:00:00
684	23	684	2018-04-23 00:00:00
685	22	685	2019-10-10 00:00:00
686	21	686	2017-06-13 00:00:00
687	21	687	2019-07-22 00:00:00
688	22	688	2018-01-04 00:00:00
689	22	689	2019-07-18 00:00:00
690	22	690	2019-01-07 00:00:00
691	21	691	2019-01-28 00:00:00
692	23	692	2018-12-15 00:00:00
693	23	693	2017-05-23 00:00:00
694	23	694	2019-02-02 00:00:00
695	21	695	2017-05-19 00:00:00
696	21	696	2019-02-06 00:00:00
697	22	697	2018-11-17 00:00:00
698	23	698	2017-09-27 00:00:00
699	21	699	2017-11-17 00:00:00
700	23	700	2018-10-08 00:00:00
701	22	701	2019-01-07 00:00:00
702	23	702	2017-09-08 00:00:00
703	22	703	2018-08-07 00:00:00
704	22	704	2019-12-22 00:00:00
705	22	705	2017-03-11 00:00:00
706	21	706	2017-06-10 00:00:00
707	22	707	2018-03-15 00:00:00
708	22	708	2019-02-03 00:00:00
709	23	709	2017-07-08 00:00:00
710	21	710	2019-05-04 00:00:00
711	21	711	2018-07-27 00:00:00
712	22	712	2018-08-03 00:00:00
713	21	713	2019-08-04 00:00:00
714	21	714	2019-09-23 00:00:00
715	21	715	2018-01-14 00:00:00
716	23	716	2019-07-06 00:00:00
717	23	717	2019-12-22 00:00:00
718	21	718	2019-10-05 00:00:00
719	21	719	2017-11-03 00:00:00
720	23	720	2017-04-24 00:00:00
721	21	721	2018-04-30 00:00:00
722	23	722	2017-07-04 00:00:00
723	23	723	2018-01-28 00:00:00
724	21	724	2018-05-07 00:00:00
725	23	725	2017-03-29 00:00:00
726	21	726	2018-10-23 00:00:00
727	23	727	2018-04-01 00:00:00
728	23	728	2017-11-25 00:00:00
729	23	729	2019-02-02 00:00:00
730	22	730	2019-06-30 00:00:00
731	23	731	2018-11-30 00:00:00
732	22	732	2019-12-16 00:00:00
733	21	733	2018-10-26 00:00:00
734	22	734	2019-08-28 00:00:00
735	22	735	2018-01-18 00:00:00
736	23	736	2017-02-12 00:00:00
737	22	737	2018-02-11 00:00:00
738	21	738	2019-02-04 00:00:00
739	22	739	2019-08-23 00:00:00
740	21	740	2018-08-30 00:00:00
741	23	741	2017-12-21 00:00:00
742	23	742	2019-11-01 00:00:00
743	21	743	2019-01-28 00:00:00
744	23	744	2018-12-28 00:00:00
745	22	745	2019-01-28 00:00:00
746	23	746	2019-07-02 00:00:00
747	23	747	2019-12-11 00:00:00
748	21	748	2019-09-08 00:00:00
749	22	749	2017-09-25 00:00:00
750	21	750	2017-12-18 00:00:00
751	23	751	2017-09-29 00:00:00
752	23	752	2018-09-28 00:00:00
753	21	753	2019-10-03 00:00:00
754	21	754	2017-06-20 00:00:00
755	23	755	2018-02-10 00:00:00
756	21	756	2017-11-20 00:00:00
757	23	757	2017-02-12 00:00:00
758	23	758	2017-11-01 00:00:00
759	23	759	2017-02-25 00:00:00
760	22	760	2017-06-30 00:00:00
761	23	761	2018-10-07 00:00:00
762	23	762	2019-06-05 00:00:00
763	22	763	2018-09-27 00:00:00
764	23	764	2017-10-07 00:00:00
765	22	765	2018-01-17 00:00:00
766	22	766	2018-04-24 00:00:00
767	23	767	2019-12-04 00:00:00
768	23	768	2019-02-07 00:00:00
769	23	769	2018-08-24 00:00:00
770	22	770	2018-12-26 00:00:00
771	22	771	2018-12-11 00:00:00
772	23	772	2017-09-16 00:00:00
773	22	773	2019-08-12 00:00:00
774	22	774	2019-11-23 00:00:00
775	22	775	2019-09-05 00:00:00
776	21	776	2019-08-19 00:00:00
777	22	777	2019-10-27 00:00:00
778	23	778	2017-05-09 00:00:00
779	23	779	2018-06-03 00:00:00
780	23	780	2019-01-03 00:00:00
781	22	781	2017-03-21 00:00:00
782	23	782	2019-03-26 00:00:00
783	21	783	2018-09-09 00:00:00
784	21	784	2018-12-03 00:00:00
785	21	785	2018-05-14 00:00:00
786	22	786	2018-10-06 00:00:00
787	22	787	2019-02-26 00:00:00
788	23	788	2017-06-09 00:00:00
789	22	789	2017-01-30 00:00:00
790	21	790	2019-12-05 00:00:00
791	21	791	2017-01-20 00:00:00
792	21	792	2019-04-23 00:00:00
793	22	793	2017-10-25 00:00:00
794	23	794	2017-07-05 00:00:00
795	23	795	2019-02-18 00:00:00
796	22	796	2018-11-30 00:00:00
797	21	797	2019-06-16 00:00:00
798	21	798	2018-01-13 00:00:00
799	23	799	2018-11-26 00:00:00
800	21	800	2017-10-29 00:00:00
801	22	801	2019-03-11 00:00:00
802	21	802	2018-01-05 00:00:00
803	22	803	2019-12-16 00:00:00
804	23	804	2018-03-22 00:00:00
805	21	805	2019-01-08 00:00:00
806	23	806	2018-07-08 00:00:00
807	22	807	2017-07-18 00:00:00
808	23	808	2018-02-16 00:00:00
809	23	809	2018-11-05 00:00:00
810	21	810	2017-09-02 00:00:00
811	21	811	2017-10-18 00:00:00
812	22	812	2017-01-02 00:00:00
813	22	813	2018-01-16 00:00:00
814	22	814	2017-04-12 00:00:00
815	23	815	2017-11-03 00:00:00
816	22	816	2019-02-15 00:00:00
817	21	817	2018-07-22 00:00:00
818	22	818	2018-06-01 00:00:00
819	23	819	2017-05-06 00:00:00
820	22	820	2017-11-14 00:00:00
821	21	821	2018-12-06 00:00:00
822	21	822	2017-05-20 00:00:00
823	21	823	2017-02-14 00:00:00
824	21	824	2018-09-12 00:00:00
825	22	825	2018-10-02 00:00:00
826	23	826	2018-11-21 00:00:00
827	23	827	2018-06-11 00:00:00
828	22	828	2019-01-23 00:00:00
829	23	829	2017-06-12 00:00:00
830	22	830	2018-04-30 00:00:00
831	23	831	2017-12-02 00:00:00
832	21	832	2017-03-04 00:00:00
833	22	833	2018-10-27 00:00:00
834	23	834	2018-08-16 00:00:00
835	22	835	2018-09-18 00:00:00
836	23	836	2017-04-24 00:00:00
837	22	837	2019-10-01 00:00:00
838	22	838	2018-07-16 00:00:00
839	23	839	2019-10-14 00:00:00
840	23	840	2018-04-10 00:00:00
841	21	841	2018-12-21 00:00:00
842	23	842	2019-04-06 00:00:00
843	23	843	2018-05-04 00:00:00
844	23	844	2019-04-04 00:00:00
845	23	845	2019-03-28 00:00:00
846	21	846	2017-04-29 00:00:00
847	22	847	2019-01-11 00:00:00
848	22	848	2017-12-11 00:00:00
849	22	849	2017-12-13 00:00:00
850	23	850	2018-07-15 00:00:00
851	23	851	2017-12-08 00:00:00
852	22	852	2019-05-22 00:00:00
853	22	853	2017-11-14 00:00:00
854	21	854	2017-01-22 00:00:00
855	21	855	2019-12-30 00:00:00
856	22	856	2017-09-26 00:00:00
857	22	857	2019-01-23 00:00:00
858	21	858	2019-10-10 00:00:00
859	23	859	2017-05-15 00:00:00
860	22	860	2018-07-05 00:00:00
861	21	861	2019-01-19 00:00:00
862	22	862	2018-01-11 00:00:00
863	21	863	2017-10-14 00:00:00
864	22	864	2017-04-14 00:00:00
865	22	865	2019-01-08 00:00:00
866	21	866	2017-08-04 00:00:00
867	22	867	2018-05-05 00:00:00
868	22	868	2017-09-16 00:00:00
869	23	869	2018-08-29 00:00:00
870	23	870	2017-10-13 00:00:00
871	23	871	2017-06-30 00:00:00
872	23	872	2017-12-02 00:00:00
873	22	873	2017-09-01 00:00:00
874	22	874	2019-10-17 00:00:00
875	21	875	2019-03-12 00:00:00
876	22	876	2017-06-22 00:00:00
877	23	877	2019-01-25 00:00:00
878	21	878	2019-01-20 00:00:00
879	22	879	2018-07-04 00:00:00
880	23	880	2018-12-10 00:00:00
881	22	881	2019-03-05 00:00:00
882	23	882	2017-06-29 00:00:00
883	21	883	2019-12-05 00:00:00
884	21	884	2018-02-13 00:00:00
885	23	885	2019-10-01 00:00:00
886	23	886	2018-01-16 00:00:00
887	21	887	2018-03-30 00:00:00
888	21	888	2017-12-09 00:00:00
889	23	889	2017-07-13 00:00:00
890	23	890	2019-12-18 00:00:00
891	21	891	2018-12-11 00:00:00
892	23	892	2018-08-08 00:00:00
893	23	893	2017-05-20 00:00:00
894	22	894	2019-10-25 00:00:00
895	21	895	2018-02-02 00:00:00
896	22	896	2019-02-23 00:00:00
897	22	897	2018-12-30 00:00:00
898	23	898	2017-12-19 00:00:00
899	22	899	2018-10-28 00:00:00
900	21	900	2018-07-03 00:00:00
901	22	901	2017-12-12 00:00:00
902	22	902	2019-11-11 00:00:00
903	21	903	2019-12-24 00:00:00
904	21	904	2018-01-15 00:00:00
905	21	905	2019-02-19 00:00:00
906	21	906	2019-06-09 00:00:00
907	22	907	2018-03-20 00:00:00
908	21	908	2018-06-28 00:00:00
909	21	909	2017-05-26 00:00:00
910	22	910	2019-02-07 00:00:00
911	23	911	2018-08-07 00:00:00
912	23	912	2019-08-25 00:00:00
913	22	913	2017-09-08 00:00:00
914	21	914	2017-09-11 00:00:00
915	21	915	2017-10-10 00:00:00
916	21	916	2017-04-20 00:00:00
917	21	917	2017-06-09 00:00:00
918	21	918	2017-08-30 00:00:00
919	22	919	2019-12-01 00:00:00
920	23	920	2018-05-28 00:00:00
921	22	921	2019-11-16 00:00:00
922	22	922	2017-06-11 00:00:00
923	23	923	2019-08-10 00:00:00
924	21	924	2019-08-01 00:00:00
925	22	925	2018-12-09 00:00:00
926	21	926	2017-10-29 00:00:00
927	23	927	2017-06-01 00:00:00
928	23	928	2017-10-11 00:00:00
929	21	929	2018-04-15 00:00:00
930	23	930	2019-05-07 00:00:00
931	22	931	2019-05-24 00:00:00
932	22	932	2018-05-26 00:00:00
933	21	933	2018-08-21 00:00:00
934	23	934	2019-06-20 00:00:00
935	23	935	2017-08-25 00:00:00
936	22	936	2019-03-06 00:00:00
937	21	937	2019-12-27 00:00:00
938	22	938	2018-01-16 00:00:00
939	22	939	2019-09-21 00:00:00
940	21	940	2017-03-14 00:00:00
941	23	941	2019-11-11 00:00:00
942	23	942	2017-01-23 00:00:00
943	21	943	2017-02-04 00:00:00
944	22	944	2017-01-22 00:00:00
945	23	945	2019-01-17 00:00:00
946	21	946	2017-11-30 00:00:00
947	23	947	2017-03-26 00:00:00
948	22	948	2017-02-11 00:00:00
949	22	949	2019-08-15 00:00:00
950	22	950	2018-10-13 00:00:00
951	23	951	2019-06-22 00:00:00
952	21	952	2018-12-12 00:00:00
953	22	953	2019-07-09 00:00:00
954	21	954	2019-07-12 00:00:00
955	23	955	2018-12-30 00:00:00
956	22	956	2018-09-26 00:00:00
957	23	957	2017-04-03 00:00:00
958	21	958	2019-04-16 00:00:00
959	23	959	2019-11-17 00:00:00
960	22	960	2019-08-27 00:00:00
961	22	961	2017-09-06 00:00:00
962	23	962	2019-03-03 00:00:00
963	23	963	2019-01-22 00:00:00
964	21	964	2017-03-26 00:00:00
965	22	965	2017-01-03 00:00:00
966	23	966	2019-04-12 00:00:00
967	22	967	2019-10-27 00:00:00
968	22	968	2017-05-26 00:00:00
969	21	969	2018-11-26 00:00:00
970	23	970	2017-06-24 00:00:00
971	22	971	2019-02-22 00:00:00
972	21	972	2018-06-25 00:00:00
973	21	973	2017-11-06 00:00:00
974	22	974	2017-12-14 00:00:00
975	21	975	2017-10-04 00:00:00
976	21	976	2017-12-26 00:00:00
977	23	977	2018-08-10 00:00:00
978	23	978	2018-04-02 00:00:00
979	23	979	2019-01-15 00:00:00
980	22	980	2017-01-08 00:00:00
981	21	981	2017-09-10 00:00:00
982	21	982	2017-10-07 00:00:00
983	21	983	2017-01-02 00:00:00
984	23	984	2018-02-11 00:00:00
985	22	985	2017-07-19 00:00:00
986	22	986	2018-07-03 00:00:00
987	22	987	2017-10-05 00:00:00
988	22	988	2018-02-26 00:00:00
989	22	989	2017-04-19 00:00:00
990	22	990	2019-01-29 00:00:00
991	22	991	2018-06-06 00:00:00
992	21	992	2019-11-15 00:00:00
993	23	993	2019-05-21 00:00:00
994	23	994	2017-08-30 00:00:00
995	21	995	2017-09-14 00:00:00
996	23	996	2018-04-15 00:00:00
997	23	997	2017-02-20 00:00:00
998	21	998	2018-09-27 00:00:00
999	21	999	2017-10-28 00:00:00
1000	23	1000	2018-05-15 00:00:00
1001	23	1001	2019-11-30 00:00:00
1002	21	1002	2019-03-23 00:00:00
1003	21	1003	2019-03-25 00:00:00
1004	23	1004	2019-03-28 00:00:00
1005	23	1005	2017-10-10 00:00:00
1006	22	1006	2018-09-22 00:00:00
1007	23	1007	2018-10-04 00:00:00
1008	22	1008	2018-05-07 00:00:00
1009	22	1009	2018-01-27 00:00:00
1010	23	1010	2019-01-19 00:00:00
1011	21	1011	2017-10-28 00:00:00
1012	21	1012	2019-07-06 00:00:00
1013	23	1013	2017-06-10 00:00:00
1014	21	1014	2017-06-27 00:00:00
1015	23	1015	2017-04-02 00:00:00
1016	21	1016	2018-09-09 00:00:00
1017	23	1017	2017-12-26 00:00:00
1018	23	1018	2018-02-02 00:00:00
1019	22	1019	2019-08-02 00:00:00
1020	23	1020	2018-09-06 00:00:00
1021	21	1021	2017-05-26 00:00:00
1022	21	1022	2017-06-06 00:00:00
1023	21	1023	2017-06-17 00:00:00
1024	23	1024	2017-06-03 00:00:00
1025	22	1025	2019-06-18 00:00:00
1026	23	1026	2019-09-19 00:00:00
1027	21	1027	2019-07-30 00:00:00
1028	22	1028	2019-07-01 00:00:00
1029	21	1029	2019-11-14 00:00:00
1030	22	1030	2019-08-29 00:00:00
1031	22	1031	2017-02-04 00:00:00
1032	23	1032	2017-05-20 00:00:00
1033	21	1033	2018-11-16 00:00:00
1034	21	1034	2018-01-03 00:00:00
1035	21	1035	2019-03-29 00:00:00
1036	22	1036	2018-05-19 00:00:00
1037	22	1037	2017-07-08 00:00:00
1038	23	1038	2019-03-11 00:00:00
1039	21	1039	2017-09-09 00:00:00
1040	22	1040	2017-09-16 00:00:00
1041	21	1041	2019-01-09 00:00:00
1042	21	1042	2017-11-05 00:00:00
1043	23	1043	2018-04-07 00:00:00
1044	22	1044	2017-03-18 00:00:00
1045	23	1045	2018-02-04 00:00:00
1046	21	1046	2019-01-16 00:00:00
1047	22	1047	2019-01-14 00:00:00
1048	23	1048	2019-02-01 00:00:00
1049	21	1049	2018-05-29 00:00:00
1050	23	1050	2017-02-17 00:00:00
1051	21	1051	2017-01-27 00:00:00
1052	21	1052	2019-06-02 00:00:00
1053	22	1053	2018-09-07 00:00:00
1054	21	1054	2019-09-05 00:00:00
1055	23	1055	2018-11-30 00:00:00
1056	21	1056	2018-07-11 00:00:00
1057	23	1057	2018-04-29 00:00:00
1058	23	1058	2018-05-28 00:00:00
1059	23	1059	2017-07-24 00:00:00
1060	23	1060	2019-06-25 00:00:00
1061	22	1061	2018-07-28 00:00:00
1062	21	1062	2017-08-27 00:00:00
1063	23	1063	2018-09-19 00:00:00
1064	23	1064	2017-05-07 00:00:00
1065	23	1065	2018-07-19 00:00:00
1066	23	1066	2018-06-27 00:00:00
1067	21	1067	2017-10-25 00:00:00
1068	22	1068	2017-09-23 00:00:00
1069	23	1069	2017-06-09 00:00:00
1070	23	1070	2017-12-26 00:00:00
1071	22	1071	2019-04-02 00:00:00
1072	21	1072	2018-10-18 00:00:00
1073	23	1073	2017-02-04 00:00:00
1074	23	1074	2018-09-21 00:00:00
1075	21	1075	2017-10-27 00:00:00
1076	23	1076	2019-09-11 00:00:00
1077	21	1077	2017-07-17 00:00:00
1078	21	1078	2018-07-24 00:00:00
1079	22	1079	2017-12-08 00:00:00
1080	21	1080	2017-07-10 00:00:00
1081	22	1081	2019-01-05 00:00:00
1082	23	1082	2019-02-25 00:00:00
1083	23	1083	2019-04-27 00:00:00
1084	23	1084	2018-12-15 00:00:00
1085	22	1085	2017-01-04 00:00:00
1086	22	1086	2018-09-18 00:00:00
1087	23	1087	2019-01-10 00:00:00
1088	22	1088	2017-02-04 00:00:00
1089	22	1089	2018-12-03 00:00:00
1090	22	1090	2019-10-12 00:00:00
1091	21	1091	2019-09-02 00:00:00
1092	22	1092	2019-10-25 00:00:00
1093	22	1093	2017-01-07 00:00:00
1094	21	1094	2019-09-28 00:00:00
1095	23	1095	2019-11-16 00:00:00
1096	21	1096	2018-12-12 00:00:00
1097	23	1097	2018-02-12 00:00:00
1098	23	1098	2017-06-30 00:00:00
1099	23	1099	2018-02-23 00:00:00
1100	23	1100	2018-08-24 00:00:00
1101	21	1101	2019-05-13 00:00:00
1102	23	1102	2019-06-03 00:00:00
1103	22	1103	2018-06-27 00:00:00
1104	22	1104	2019-04-17 00:00:00
1105	22	1105	2019-05-12 00:00:00
1106	21	1106	2018-11-09 00:00:00
1107	22	1107	2018-01-03 00:00:00
1108	22	1108	2017-08-08 00:00:00
1109	22	1109	2019-09-25 00:00:00
1110	23	1110	2017-02-01 00:00:00
1111	23	1111	2017-10-10 00:00:00
1112	21	1112	2018-02-02 00:00:00
1113	22	1113	2018-02-16 00:00:00
1114	23	1114	2017-06-22 00:00:00
1115	22	1115	2017-02-23 00:00:00
1116	22	1116	2017-11-20 00:00:00
1117	23	1117	2019-07-30 00:00:00
1118	21	1118	2017-07-02 00:00:00
1119	22	1119	2017-11-29 00:00:00
1120	21	1120	2018-02-15 00:00:00
1121	22	1121	2019-08-11 00:00:00
1122	22	1122	2018-02-02 00:00:00
1123	21	1123	2018-08-26 00:00:00
1124	21	1124	2019-06-20 00:00:00
1125	22	1125	2017-12-17 00:00:00
1126	21	1126	2018-03-25 00:00:00
1127	21	1127	2018-10-10 00:00:00
1128	21	1128	2017-10-11 00:00:00
1129	22	1129	2019-01-13 00:00:00
1130	22	1130	2019-06-09 00:00:00
1131	21	1131	2019-09-10 00:00:00
1132	21	1132	2017-12-09 00:00:00
1133	23	1133	2017-02-08 00:00:00
1134	23	1134	2018-02-12 00:00:00
1135	21	1135	2019-02-08 00:00:00
1136	21	1136	2018-04-27 00:00:00
1137	21	1137	2017-09-11 00:00:00
1138	23	1138	2019-11-23 00:00:00
1139	21	1139	2017-03-17 00:00:00
1140	21	1140	2018-12-23 00:00:00
1141	21	1141	2019-08-25 00:00:00
1142	21	1142	2018-06-23 00:00:00
1143	23	1143	2017-04-28 00:00:00
1144	22	1144	2019-01-01 00:00:00
1145	23	1145	2019-07-15 00:00:00
1146	21	1146	2017-04-19 00:00:00
1147	21	1147	2019-02-10 00:00:00
1148	23	1148	2017-10-28 00:00:00
1149	21	1149	2018-08-10 00:00:00
1150	23	1150	2018-01-03 00:00:00
1151	21	1151	2017-01-06 00:00:00
1152	23	1152	2017-12-16 00:00:00
1153	23	1153	2019-03-28 00:00:00
1154	22	1154	2019-04-18 00:00:00
1155	21	1155	2017-09-07 00:00:00
1156	23	1156	2018-07-30 00:00:00
1157	23	1157	2017-02-08 00:00:00
1158	21	1158	2017-09-03 00:00:00
1159	21	1159	2017-08-17 00:00:00
1160	23	1160	2019-09-11 00:00:00
1161	21	1161	2018-09-05 00:00:00
1162	23	1162	2018-03-04 00:00:00
1163	21	1163	2018-12-20 00:00:00
1164	22	1164	2018-09-23 00:00:00
1165	21	1165	2019-02-04 00:00:00
1166	22	1166	2018-09-03 00:00:00
1167	21	1167	2019-12-04 00:00:00
1168	23	1168	2017-02-23 00:00:00
1169	22	1169	2018-09-02 00:00:00
1170	21	1170	2018-07-17 00:00:00
1171	23	1171	2018-08-07 00:00:00
1172	23	1172	2018-08-08 00:00:00
1173	21	1173	2017-12-08 00:00:00
1174	21	1174	2019-10-20 00:00:00
1175	23	1175	2019-02-04 00:00:00
1176	22	1176	2017-01-01 00:00:00
1177	23	1177	2018-02-22 00:00:00
1178	21	1178	2018-04-16 00:00:00
1179	22	1179	2017-03-23 00:00:00
1180	21	1180	2019-10-08 00:00:00
1181	21	1181	2017-02-05 00:00:00
1182	22	1182	2017-04-18 00:00:00
1183	21	1183	2019-09-10 00:00:00
1184	23	1184	2018-06-18 00:00:00
1185	23	1185	2018-03-22 00:00:00
1186	22	1186	2019-03-15 00:00:00
1187	22	1187	2018-07-02 00:00:00
1188	21	1188	2018-04-16 00:00:00
1189	23	1189	2018-04-25 00:00:00
1190	22	1190	2019-10-13 00:00:00
1191	23	1191	2017-02-03 00:00:00
1192	21	1192	2017-11-28 00:00:00
1193	21	1193	2017-08-19 00:00:00
1194	23	1194	2019-07-01 00:00:00
1195	23	1195	2019-04-16 00:00:00
1196	22	1196	2019-01-07 00:00:00
1197	21	1197	2019-11-22 00:00:00
1198	22	1198	2017-01-04 00:00:00
1199	23	1199	2019-07-11 00:00:00
1200	23	1200	2017-04-26 00:00:00
1201	21	1201	2017-07-16 00:00:00
1202	21	1202	2017-10-22 00:00:00
1203	22	1203	2019-09-22 00:00:00
1204	23	1204	2019-11-05 00:00:00
1205	23	1205	2019-12-25 00:00:00
1206	21	1206	2019-11-19 00:00:00
1207	21	1207	2017-12-05 00:00:00
1208	21	1208	2018-01-02 00:00:00
1209	23	1209	2018-05-20 00:00:00
1210	23	1210	2019-12-23 00:00:00
1211	22	1211	2019-01-09 00:00:00
1212	23	1212	2019-11-13 00:00:00
1213	21	1213	2017-12-10 00:00:00
1214	22	1214	2018-06-17 00:00:00
1215	21	1215	2019-08-28 00:00:00
1216	22	1216	2018-10-14 00:00:00
1217	21	1217	2018-03-05 00:00:00
1218	22	1218	2017-08-08 00:00:00
1219	22	1219	2018-06-13 00:00:00
1220	23	1220	2018-07-24 00:00:00
1221	22	1221	2017-01-09 00:00:00
1222	23	1222	2017-04-12 00:00:00
1223	22	1223	2018-01-09 00:00:00
1224	23	1224	2017-01-16 00:00:00
1225	22	1225	2018-12-10 00:00:00
1226	23	1226	2017-05-26 00:00:00
1227	23	1227	2019-11-09 00:00:00
1228	22	1228	2017-05-10 00:00:00
1229	23	1229	2017-02-23 00:00:00
1230	23	1230	2019-05-15 00:00:00
1231	21	1231	2019-04-11 00:00:00
1232	21	1232	2017-01-01 00:00:00
1233	22	1233	2017-08-22 00:00:00
1234	22	1234	2019-05-02 00:00:00
1235	23	1235	2018-01-29 00:00:00
1236	23	1236	2018-10-18 00:00:00
1237	22	1237	2018-12-19 00:00:00
1238	22	1238	2019-11-08 00:00:00
1239	23	1239	2019-07-28 00:00:00
1240	21	1240	2017-05-12 00:00:00
1241	21	1241	2019-02-03 00:00:00
1242	21	1242	2018-09-05 00:00:00
1243	21	1243	2018-04-13 00:00:00
1244	22	1244	2019-09-11 00:00:00
1245	21	1245	2018-01-16 00:00:00
1246	22	1246	2018-10-24 00:00:00
1247	22	1247	2019-05-27 00:00:00
1248	23	1248	2018-11-14 00:00:00
1249	21	1249	2019-04-26 00:00:00
1250	23	1250	2017-05-01 00:00:00
1251	22	1251	2019-07-03 00:00:00
1252	23	1252	2019-07-17 00:00:00
1253	22	1253	2017-05-21 00:00:00
1254	23	1254	2019-10-04 00:00:00
1255	23	1255	2018-10-03 00:00:00
1256	21	1256	2017-08-25 00:00:00
1257	21	1257	2017-11-20 00:00:00
1258	23	1258	2019-10-11 00:00:00
1259	21	1259	2018-12-27 00:00:00
1260	22	1260	2017-04-12 00:00:00
1261	21	1261	2017-02-22 00:00:00
1262	21	1262	2017-09-15 00:00:00
1263	23	1263	2017-01-06 00:00:00
1264	22	1264	2017-03-06 00:00:00
1265	21	1265	2018-03-04 00:00:00
1266	21	1266	2018-10-12 00:00:00
1267	23	1267	2019-04-05 00:00:00
1268	21	1268	2017-02-02 00:00:00
1269	23	1269	2018-06-20 00:00:00
1270	22	1270	2019-05-26 00:00:00
1271	21	1271	2017-06-11 00:00:00
1272	22	1272	2019-09-17 00:00:00
1273	21	1273	2017-10-06 00:00:00
1274	22	1274	2017-10-28 00:00:00
1275	21	1275	2019-08-29 00:00:00
1276	23	1276	2019-10-03 00:00:00
1277	21	1277	2017-02-13 00:00:00
1278	23	1278	2017-05-21 00:00:00
1279	21	1279	2018-04-27 00:00:00
1280	21	1280	2017-06-20 00:00:00
1281	23	1281	2018-12-06 00:00:00
1282	23	1282	2018-10-19 00:00:00
1283	23	1283	2019-03-01 00:00:00
1284	21	1284	2019-03-11 00:00:00
1285	21	1285	2019-11-17 00:00:00
1286	22	1286	2017-05-13 00:00:00
1287	23	1287	2018-01-17 00:00:00
1288	23	1288	2017-05-05 00:00:00
1289	23	1289	2018-09-13 00:00:00
1290	23	1290	2019-12-14 00:00:00
1291	22	1291	2019-07-24 00:00:00
1292	23	1292	2019-03-23 00:00:00
1293	21	1293	2017-05-01 00:00:00
1294	22	1294	2017-11-16 00:00:00
1295	22	1295	2017-09-01 00:00:00
1296	21	1296	2017-05-09 00:00:00
1297	22	1297	2019-10-12 00:00:00
1298	22	1298	2018-07-14 00:00:00
1299	23	1299	2018-01-23 00:00:00
1300	22	1300	2019-06-21 00:00:00
1301	23	1301	2019-12-26 00:00:00
1302	23	1302	2019-01-15 00:00:00
1303	22	1303	2019-11-14 00:00:00
1304	23	1304	2018-04-26 00:00:00
1305	22	1305	2018-06-30 00:00:00
1306	22	1306	2017-04-05 00:00:00
1307	22	1307	2019-12-10 00:00:00
1308	22	1308	2018-11-20 00:00:00
1309	22	1309	2019-04-28 00:00:00
1310	23	1310	2019-08-18 00:00:00
1311	22	1311	2017-06-27 00:00:00
1312	23	1312	2018-10-27 00:00:00
1313	22	1313	2017-10-27 00:00:00
1314	22	1314	2019-10-19 00:00:00
1315	23	1315	2017-02-04 00:00:00
1316	23	1316	2017-03-13 00:00:00
1317	21	1317	2017-09-20 00:00:00
1318	21	1318	2018-02-10 00:00:00
1319	23	1319	2017-10-26 00:00:00
1320	23	1320	2017-01-07 00:00:00
1321	21	1321	2019-09-03 00:00:00
1322	23	1322	2017-09-09 00:00:00
1323	22	1323	2017-12-28 00:00:00
1324	21	1324	2017-10-01 00:00:00
1325	23	1325	2018-08-12 00:00:00
1326	23	1326	2018-04-20 00:00:00
1327	21	1327	2017-01-25 00:00:00
1328	23	1328	2017-03-18 00:00:00
1329	22	1329	2018-03-06 00:00:00
1330	23	1330	2017-12-21 00:00:00
1331	21	1331	2019-09-29 00:00:00
1332	21	1332	2018-09-10 00:00:00
1333	22	1333	2017-02-15 00:00:00
1334	21	1334	2017-07-04 00:00:00
1335	21	1335	2018-10-28 00:00:00
1336	22	1336	2018-07-05 00:00:00
1337	21	1337	2018-07-30 00:00:00
1338	22	1338	2019-01-15 00:00:00
1339	23	1339	2019-10-26 00:00:00
1340	21	1340	2018-11-06 00:00:00
1341	22	1341	2017-08-17 00:00:00
1342	22	1342	2018-03-22 00:00:00
1343	23	1343	2017-09-20 00:00:00
1344	22	1344	2018-02-24 00:00:00
1345	23	1345	2018-04-08 00:00:00
1346	21	1346	2017-07-12 00:00:00
1347	21	1347	2019-01-08 00:00:00
1348	22	1348	2017-10-19 00:00:00
1349	22	1349	2018-07-10 00:00:00
1350	21	1350	2018-09-16 00:00:00
1351	22	1351	2018-07-23 00:00:00
1352	22	1352	2019-05-01 00:00:00
1353	22	1353	2018-08-26 00:00:00
1354	23	1354	2017-06-12 00:00:00
1355	22	1355	2017-01-28 00:00:00
1356	21	1356	2019-02-27 00:00:00
1357	23	1357	2019-03-27 00:00:00
1358	21	1358	2018-11-04 00:00:00
1359	22	1359	2018-09-23 00:00:00
1360	23	1360	2018-03-26 00:00:00
1361	22	1361	2018-04-11 00:00:00
1362	22	1362	2018-04-17 00:00:00
1363	22	1363	2018-07-09 00:00:00
1364	21	1364	2017-12-04 00:00:00
1365	22	1365	2018-11-05 00:00:00
1366	21	1366	2018-02-06 00:00:00
1367	22	1367	2019-10-14 00:00:00
1368	22	1368	2019-04-01 00:00:00
1369	23	1369	2018-05-20 00:00:00
1370	21	1370	2018-02-21 00:00:00
1371	23	1371	2018-06-09 00:00:00
1372	21	1372	2017-10-20 00:00:00
1373	22	1373	2017-08-10 00:00:00
1374	22	1374	2018-08-20 00:00:00
1375	22	1375	2017-08-28 00:00:00
1376	23	1376	2017-08-05 00:00:00
1377	23	1377	2017-02-20 00:00:00
1378	22	1378	2019-03-05 00:00:00
1379	22	1379	2018-05-18 00:00:00
1380	21	1380	2018-03-06 00:00:00
1381	21	1381	2018-07-19 00:00:00
1382	21	1382	2018-05-18 00:00:00
1383	21	1383	2017-06-29 00:00:00
1384	22	1384	2018-07-04 00:00:00
1385	21	1385	2017-12-18 00:00:00
1386	22	1386	2017-11-23 00:00:00
1387	21	1387	2019-10-08 00:00:00
1388	23	1388	2017-11-25 00:00:00
1389	23	1389	2019-07-12 00:00:00
1390	21	1390	2019-03-15 00:00:00
1391	22	1391	2019-03-16 00:00:00
1392	21	1392	2019-06-22 00:00:00
1393	23	1393	2017-10-27 00:00:00
1394	21	1394	2018-04-07 00:00:00
1395	23	1395	2018-11-28 00:00:00
1396	22	1396	2019-07-26 00:00:00
1397	23	1397	2018-09-15 00:00:00
1398	22	1398	2017-09-13 00:00:00
1399	21	1399	2017-05-08 00:00:00
1400	23	1400	2019-12-07 00:00:00
1401	23	1401	2018-01-26 00:00:00
1402	22	1402	2019-01-06 00:00:00
1403	21	1403	2018-03-29 00:00:00
1404	22	1404	2017-11-16 00:00:00
1405	21	1405	2019-07-26 00:00:00
1406	22	1406	2018-05-03 00:00:00
1407	23	1407	2019-11-04 00:00:00
1408	23	1408	2019-04-21 00:00:00
1409	21	1409	2017-02-26 00:00:00
1410	23	1410	2017-06-14 00:00:00
1411	23	1411	2018-10-07 00:00:00
1412	22	1412	2018-10-27 00:00:00
1413	23	1413	2018-06-29 00:00:00
1414	21	1414	2018-10-25 00:00:00
1415	21	1415	2019-02-02 00:00:00
1416	21	1416	2019-01-29 00:00:00
1417	23	1417	2018-05-06 00:00:00
1418	21	1418	2019-07-28 00:00:00
1419	23	1419	2017-06-11 00:00:00
1420	22	1420	2018-12-19 00:00:00
1421	22	1421	2017-07-30 00:00:00
1422	21	1422	2017-11-26 00:00:00
1423	21	1423	2018-10-15 00:00:00
1424	22	1424	2017-10-27 00:00:00
1425	21	1425	2018-07-06 00:00:00
1426	23	1426	2017-05-06 00:00:00
1427	23	1427	2017-02-04 00:00:00
1428	23	1428	2018-03-10 00:00:00
1429	21	1429	2017-03-10 00:00:00
1430	22	1430	2017-08-22 00:00:00
1431	23	1431	2018-04-22 00:00:00
1432	22	1432	2017-08-12 00:00:00
1433	21	1433	2018-09-25 00:00:00
1434	22	1434	2019-01-12 00:00:00
1435	21	1435	2019-05-03 00:00:00
1436	23	1436	2017-07-02 00:00:00
1437	23	1437	2019-01-10 00:00:00
1438	21	1438	2017-10-09 00:00:00
1439	23	1439	2018-01-12 00:00:00
1440	23	1440	2019-03-09 00:00:00
1441	23	1441	2017-02-14 00:00:00
1442	21	1442	2019-06-20 00:00:00
1443	23	1443	2019-12-26 00:00:00
1444	22	1444	2019-10-23 00:00:00
1445	21	1445	2019-12-09 00:00:00
1446	22	1446	2019-04-11 00:00:00
1447	23	1447	2017-09-11 00:00:00
1448	21	1448	2017-04-20 00:00:00
1449	21	1449	2018-08-27 00:00:00
1450	22	1450	2019-09-27 00:00:00
1451	23	1451	2019-07-18 00:00:00
1452	22	1452	2018-10-04 00:00:00
1453	23	1453	2017-10-23 00:00:00
1454	23	1454	2017-02-02 00:00:00
1455	22	1455	2018-05-27 00:00:00
1456	21	1456	2017-08-18 00:00:00
1457	22	1457	2019-12-13 00:00:00
1458	21	1458	2019-09-26 00:00:00
1459	21	1459	2017-07-11 00:00:00
1460	23	1460	2017-01-18 00:00:00
1461	21	1461	2017-12-24 00:00:00
1462	21	1462	2017-12-19 00:00:00
1463	21	1463	2017-06-23 00:00:00
1464	21	1464	2019-02-05 00:00:00
1465	22	1465	2017-03-03 00:00:00
1466	23	1466	2018-09-23 00:00:00
1467	21	1467	2017-09-14 00:00:00
1468	23	1468	2018-07-01 00:00:00
1469	21	1469	2017-11-12 00:00:00
1470	23	1470	2018-06-13 00:00:00
1471	23	1471	2019-10-19 00:00:00
1472	21	1472	2019-09-01 00:00:00
1473	23	1473	2018-11-16 00:00:00
1474	22	1474	2019-05-22 00:00:00
1475	21	1475	2018-02-17 00:00:00
1476	22	1476	2018-01-03 00:00:00
1477	21	1477	2017-04-13 00:00:00
1478	22	1478	2019-12-09 00:00:00
1479	22	1479	2018-10-22 00:00:00
1480	21	1480	2018-12-12 00:00:00
1481	22	1481	2017-02-24 00:00:00
1482	22	1482	2018-05-03 00:00:00
1483	23	1483	2018-02-01 00:00:00
1484	21	1484	2018-08-29 00:00:00
1485	22	1485	2018-06-12 00:00:00
1486	22	1486	2019-02-26 00:00:00
1487	22	1487	2019-03-23 00:00:00
1488	22	1488	2017-08-01 00:00:00
1489	21	1489	2019-11-09 00:00:00
1490	22	1490	2017-12-01 00:00:00
1491	21	1491	2017-07-12 00:00:00
1492	21	1492	2018-01-19 00:00:00
1493	21	1493	2019-07-29 00:00:00
1494	22	1494	2018-12-24 00:00:00
1495	22	1495	2017-05-18 00:00:00
1496	23	1496	2018-09-09 00:00:00
1497	23	1497	2019-07-05 00:00:00
1498	21	1498	2017-09-13 00:00:00
1499	21	1499	2019-01-06 00:00:00
1500	23	1500	2018-06-28 00:00:00
1501	21	1501	2018-06-23 00:00:00
1502	21	1502	2019-12-23 00:00:00
1503	23	1503	2017-12-15 00:00:00
1504	21	1504	2019-06-04 00:00:00
1505	23	1505	2018-12-23 00:00:00
1506	21	1506	2018-02-13 00:00:00
1507	21	1507	2017-07-28 00:00:00
1508	21	1508	2019-01-01 00:00:00
1509	23	1509	2019-05-25 00:00:00
1510	22	1510	2019-07-15 00:00:00
1511	21	1511	2019-11-25 00:00:00
1512	23	1512	2017-06-22 00:00:00
1513	23	1513	2018-09-27 00:00:00
1514	23	1514	2017-02-16 00:00:00
1515	21	1515	2018-07-17 00:00:00
1516	21	1516	2017-02-08 00:00:00
1517	21	1517	2017-06-24 00:00:00
1518	23	1518	2019-04-24 00:00:00
1519	21	1519	2017-05-28 00:00:00
1520	23	1520	2019-09-22 00:00:00
1521	22	1521	2017-08-02 00:00:00
1522	22	1522	2019-08-07 00:00:00
1523	21	1523	2017-10-23 00:00:00
1524	21	1524	2019-01-22 00:00:00
1525	23	1525	2018-07-05 00:00:00
1526	22	1526	2018-07-07 00:00:00
1527	23	1527	2019-12-13 00:00:00
1528	22	1528	2018-12-02 00:00:00
1529	21	1529	2019-11-11 00:00:00
1530	23	1530	2017-07-16 00:00:00
1531	22	1531	2019-04-09 00:00:00
1532	21	1532	2018-04-05 00:00:00
1533	21	1533	2017-03-10 00:00:00
1534	22	1534	2018-11-18 00:00:00
1535	22	1535	2017-07-21 00:00:00
1536	23	1536	2017-05-22 00:00:00
1537	22	1537	2018-04-19 00:00:00
1538	22	1538	2018-12-27 00:00:00
1539	23	1539	2019-06-12 00:00:00
1540	23	1540	2019-03-03 00:00:00
1541	22	1541	2017-03-20 00:00:00
1542	22	1542	2019-04-15 00:00:00
1543	21	1543	2017-08-28 00:00:00
1544	21	1544	2018-10-29 00:00:00
1545	22	1545	2017-12-03 00:00:00
1546	22	1546	2017-01-02 00:00:00
1547	21	1547	2019-07-10 00:00:00
1548	23	1548	2017-08-19 00:00:00
1549	21	1549	2017-11-23 00:00:00
1550	21	1550	2019-12-18 00:00:00
1551	22	1551	2017-09-18 00:00:00
1552	23	1552	2019-06-18 00:00:00
1553	22	1553	2019-02-04 00:00:00
1554	23	1554	2018-07-11 00:00:00
1555	22	1555	2017-11-18 00:00:00
1556	23	1556	2018-08-05 00:00:00
1557	23	1557	2017-09-02 00:00:00
1558	23	1558	2018-11-06 00:00:00
1559	23	1559	2017-09-29 00:00:00
1560	23	1560	2018-09-07 00:00:00
1561	21	1561	2019-06-29 00:00:00
1562	22	1562	2017-09-09 00:00:00
1563	23	1563	2017-03-23 00:00:00
1564	21	1564	2019-03-08 00:00:00
1565	22	1565	2017-11-02 00:00:00
1566	23	1566	2017-03-08 00:00:00
1567	22	1567	2019-10-12 00:00:00
1568	21	1568	2019-07-30 00:00:00
1569	23	1569	2019-10-22 00:00:00
1570	21	1570	2017-01-24 00:00:00
1571	22	1571	2017-08-06 00:00:00
1572	23	1572	2018-11-29 00:00:00
1573	22	1573	2017-04-02 00:00:00
1574	23	1574	2017-11-09 00:00:00
1575	23	1575	2018-06-21 00:00:00
1576	22	1576	2019-01-28 00:00:00
1577	22	1577	2017-09-22 00:00:00
1578	23	1578	2018-10-05 00:00:00
1579	21	1579	2017-12-20 00:00:00
1580	22	1580	2018-06-22 00:00:00
1581	21	1581	2018-11-18 00:00:00
1582	22	1582	2019-06-13 00:00:00
1583	23	1583	2019-09-25 00:00:00
1584	21	1584	2018-09-04 00:00:00
1585	23	1585	2018-07-05 00:00:00
1586	21	1586	2017-10-08 00:00:00
1587	21	1587	2018-09-27 00:00:00
1588	21	1588	2017-05-10 00:00:00
1589	23	1589	2019-08-07 00:00:00
1590	21	1590	2018-05-03 00:00:00
1591	23	1591	2018-11-10 00:00:00
1592	22	1592	2019-10-22 00:00:00
1593	22	1593	2017-09-17 00:00:00
1594	23	1594	2017-07-09 00:00:00
1595	22	1595	2017-03-10 00:00:00
1596	22	1596	2019-10-18 00:00:00
1597	23	1597	2017-04-25 00:00:00
1598	23	1598	2019-11-18 00:00:00
1599	21	1599	2019-11-22 00:00:00
1600	22	1600	2017-01-26 00:00:00
1601	22	1601	2019-10-24 00:00:00
1602	22	1602	2019-11-10 00:00:00
1603	21	1603	2018-10-10 00:00:00
1604	21	1604	2019-02-10 00:00:00
1605	22	1605	2018-12-02 00:00:00
1606	23	1606	2019-03-17 00:00:00
1607	21	1607	2018-11-04 00:00:00
1608	22	1608	2018-08-28 00:00:00
1609	22	1609	2019-06-25 00:00:00
1610	21	1610	2018-06-15 00:00:00
1611	21	1611	2018-04-26 00:00:00
1612	21	1612	2017-02-20 00:00:00
1613	21	1613	2018-11-02 00:00:00
1614	22	1614	2019-11-27 00:00:00
1615	21	1615	2018-08-27 00:00:00
1616	22	1616	2019-06-07 00:00:00
1617	22	1617	2018-06-19 00:00:00
1618	23	1618	2019-07-25 00:00:00
1619	21	1619	2018-04-13 00:00:00
1620	22	1620	2018-10-14 00:00:00
1621	22	1621	2017-05-19 00:00:00
1622	21	1622	2018-01-16 00:00:00
1623	22	1623	2018-11-24 00:00:00
1624	22	1624	2019-06-13 00:00:00
1625	21	1625	2019-09-19 00:00:00
1626	23	1626	2018-12-11 00:00:00
1627	23	1627	2018-07-10 00:00:00
1628	21	1628	2018-09-11 00:00:00
1629	23	1629	2017-12-24 00:00:00
1630	21	1630	2017-05-16 00:00:00
1631	23	1631	2018-12-18 00:00:00
1632	22	1632	2017-12-04 00:00:00
1633	22	1633	2017-03-26 00:00:00
1634	22	1634	2019-07-26 00:00:00
1635	23	1635	2019-11-28 00:00:00
1636	23	1636	2017-09-13 00:00:00
1637	21	1637	2018-12-17 00:00:00
1638	21	1638	2017-05-15 00:00:00
1639	21	1639	2017-01-14 00:00:00
1640	21	1640	2017-07-25 00:00:00
1641	23	1641	2018-06-08 00:00:00
1642	23	1642	2019-01-05 00:00:00
1643	23	1643	2017-02-27 00:00:00
1644	22	1644	2017-12-19 00:00:00
1645	23	1645	2019-07-10 00:00:00
1646	21	1646	2018-01-12 00:00:00
1647	21	1647	2019-02-03 00:00:00
1648	22	1648	2019-03-22 00:00:00
1649	21	1649	2019-10-13 00:00:00
1650	22	1650	2019-08-22 00:00:00
1651	23	1651	2019-03-25 00:00:00
1652	21	1652	2018-11-12 00:00:00
1653	23	1653	2017-08-12 00:00:00
1654	22	1654	2018-03-12 00:00:00
1655	21	1655	2017-10-23 00:00:00
1656	22	1656	2017-03-22 00:00:00
1657	23	1657	2019-09-23 00:00:00
1658	23	1658	2017-08-26 00:00:00
1659	21	1659	2018-06-29 00:00:00
1660	22	1660	2019-01-15 00:00:00
1661	21	1661	2019-03-10 00:00:00
1662	21	1662	2017-09-22 00:00:00
1663	21	1663	2017-06-02 00:00:00
1664	22	1664	2019-06-12 00:00:00
1665	21	1665	2018-03-07 00:00:00
1666	23	1666	2017-12-14 00:00:00
1667	21	1667	2018-05-13 00:00:00
1668	23	1668	2019-02-01 00:00:00
1669	22	1669	2019-07-20 00:00:00
1670	21	1670	2019-02-25 00:00:00
1671	23	1671	2019-12-28 00:00:00
1672	22	1672	2017-04-04 00:00:00
1673	22	1673	2019-02-17 00:00:00
1674	22	1674	2019-03-05 00:00:00
1675	22	1675	2018-03-07 00:00:00
1676	21	1676	2019-11-06 00:00:00
1677	23	1677	2019-02-08 00:00:00
1678	23	1678	2019-09-03 00:00:00
1679	21	1679	2018-02-08 00:00:00
1680	21	1680	2018-03-20 00:00:00
1681	21	1681	2018-07-03 00:00:00
1682	23	1682	2018-01-30 00:00:00
1683	22	1683	2017-06-28 00:00:00
1684	23	1684	2019-04-27 00:00:00
1685	23	1685	2017-05-21 00:00:00
1686	23	1686	2017-01-22 00:00:00
1687	23	1687	2019-11-15 00:00:00
1688	22	1688	2018-12-01 00:00:00
1689	21	1689	2018-05-17 00:00:00
1690	21	1690	2019-09-07 00:00:00
1691	21	1691	2019-09-25 00:00:00
1692	22	1692	2018-12-12 00:00:00
1693	23	1693	2018-01-25 00:00:00
1694	21	1694	2018-02-03 00:00:00
1695	23	1695	2018-04-15 00:00:00
1696	23	1696	2018-11-11 00:00:00
1697	21	1697	2017-12-23 00:00:00
1698	22	1698	2017-06-04 00:00:00
1699	22	1699	2018-07-26 00:00:00
1700	23	1700	2018-08-11 00:00:00
1701	22	1701	2018-02-11 00:00:00
1702	22	1702	2018-02-18 00:00:00
1703	23	1703	2017-02-06 00:00:00
1704	23	1704	2019-07-16 00:00:00
1705	22	1705	2017-03-14 00:00:00
1706	22	1706	2017-11-17 00:00:00
1707	23	1707	2018-11-06 00:00:00
1708	23	1708	2018-02-24 00:00:00
1709	21	1709	2019-10-13 00:00:00
1710	22	1710	2018-10-28 00:00:00
1711	22	1711	2019-06-15 00:00:00
1712	23	1712	2019-08-20 00:00:00
1713	21	1713	2018-03-01 00:00:00
1714	22	1714	2019-05-27 00:00:00
1715	22	1715	2019-04-09 00:00:00
1716	21	1716	2019-02-04 00:00:00
1717	22	1717	2017-02-04 00:00:00
1718	22	1718	2019-06-08 00:00:00
1719	23	1719	2017-09-14 00:00:00
1720	23	1720	2018-02-20 00:00:00
1721	23	1721	2017-04-03 00:00:00
1722	23	1722	2017-12-23 00:00:00
1723	23	1723	2018-08-07 00:00:00
1724	22	1724	2018-08-08 00:00:00
1725	21	1725	2017-02-24 00:00:00
1726	21	1726	2017-02-26 00:00:00
1727	23	1727	2019-03-01 00:00:00
1728	22	1728	2019-12-10 00:00:00
1729	22	1729	2018-11-28 00:00:00
1730	21	1730	2017-03-07 00:00:00
1731	22	1731	2018-05-16 00:00:00
1732	21	1732	2019-01-25 00:00:00
1733	21	1733	2018-10-21 00:00:00
1734	23	1734	2018-09-20 00:00:00
1735	21	1735	2018-05-02 00:00:00
1736	21	1736	2017-10-02 00:00:00
1737	21	1737	2019-12-09 00:00:00
1738	23	1738	2019-07-11 00:00:00
1739	23	1739	2019-10-23 00:00:00
1740	22	1740	2018-04-07 00:00:00
1741	23	1741	2018-02-01 00:00:00
1742	22	1742	2018-01-04 00:00:00
1743	21	1743	2017-08-16 00:00:00
1744	23	1744	2019-07-21 00:00:00
1745	21	1745	2019-01-18 00:00:00
1746	23	1746	2017-04-01 00:00:00
1747	22	1747	2017-07-20 00:00:00
1748	21	1748	2017-11-28 00:00:00
1749	22	1749	2019-03-19 00:00:00
1750	22	1750	2018-01-19 00:00:00
1751	21	1751	2017-10-08 00:00:00
1752	22	1752	2017-03-10 00:00:00
1753	23	1753	2017-03-24 00:00:00
1754	21	1754	2018-01-06 00:00:00
1755	23	1755	2017-01-17 00:00:00
1756	21	1756	2019-01-18 00:00:00
1757	23	1757	2018-09-29 00:00:00
1758	22	1758	2018-08-13 00:00:00
1759	23	1759	2017-10-08 00:00:00
1760	23	1760	2019-04-23 00:00:00
1761	23	1761	2018-09-14 00:00:00
1762	21	1762	2019-07-07 00:00:00
1763	22	1763	2017-01-25 00:00:00
1764	22	1764	2018-10-07 00:00:00
1765	22	1765	2018-06-04 00:00:00
1766	21	1766	2019-12-25 00:00:00
1767	21	1767	2017-07-16 00:00:00
1768	22	1768	2019-12-17 00:00:00
1769	23	1769	2018-10-21 00:00:00
1770	23	1770	2018-05-16 00:00:00
1771	23	1771	2019-11-14 00:00:00
1772	22	1772	2019-12-05 00:00:00
1773	21	1773	2019-06-01 00:00:00
1774	21	1774	2017-02-23 00:00:00
1775	22	1775	2018-09-13 00:00:00
1776	23	1776	2018-05-21 00:00:00
1777	22	1777	2017-04-30 00:00:00
1778	21	1778	2018-11-18 00:00:00
1779	22	1779	2018-06-22 00:00:00
1780	21	1780	2017-03-23 00:00:00
1781	21	1781	2018-02-25 00:00:00
1782	22	1782	2017-02-04 00:00:00
1783	21	1783	2019-12-14 00:00:00
1784	22	1784	2017-12-23 00:00:00
1785	23	1785	2017-01-28 00:00:00
1786	23	1786	2019-08-15 00:00:00
1787	22	1787	2019-05-18 00:00:00
1788	21	1788	2019-10-19 00:00:00
1789	23	1789	2019-11-27 00:00:00
1790	23	1790	2018-03-03 00:00:00
1791	23	1791	2019-11-09 00:00:00
1792	22	1792	2018-02-24 00:00:00
1793	22	1793	2017-02-02 00:00:00
1794	23	1794	2017-11-26 00:00:00
1795	22	1795	2018-02-17 00:00:00
1796	21	1796	2017-12-01 00:00:00
1797	21	1797	2017-12-05 00:00:00
1798	21	1798	2018-03-15 00:00:00
1799	23	1799	2018-07-20 00:00:00
1800	22	1800	2018-02-25 00:00:00
1801	22	1801	2017-01-10 00:00:00
1802	21	1802	2018-09-25 00:00:00
1803	23	1803	2018-01-10 00:00:00
1804	21	1804	2017-05-26 00:00:00
1805	21	1805	2019-09-03 00:00:00
1806	23	1806	2019-03-28 00:00:00
1807	21	1807	2018-04-24 00:00:00
1808	21	1808	2017-07-18 00:00:00
1809	23	1809	2018-09-20 00:00:00
1810	23	1810	2017-05-02 00:00:00
1811	22	1811	2019-04-11 00:00:00
1812	22	1812	2019-10-15 00:00:00
1813	23	1813	2019-10-18 00:00:00
1814	21	1814	2019-02-01 00:00:00
1815	22	1815	2018-06-14 00:00:00
1816	23	1816	2017-08-19 00:00:00
1817	22	1817	2017-01-21 00:00:00
1818	23	1818	2018-12-22 00:00:00
1819	21	1819	2019-04-27 00:00:00
1820	21	1820	2017-05-26 00:00:00
1821	23	1821	2018-01-10 00:00:00
1822	22	1822	2019-12-18 00:00:00
1823	23	1823	2017-12-23 00:00:00
1824	22	1824	2017-09-12 00:00:00
1825	22	1825	2018-08-27 00:00:00
1826	23	1826	2018-06-13 00:00:00
1827	22	1827	2019-04-15 00:00:00
1828	21	1828	2017-09-09 00:00:00
1829	23	1829	2018-04-09 00:00:00
1830	21	1830	2019-02-05 00:00:00
1831	21	1831	2019-12-11 00:00:00
1832	21	1832	2019-04-04 00:00:00
1833	22	1833	2017-06-12 00:00:00
1834	22	1834	2018-01-02 00:00:00
1835	21	1835	2018-01-26 00:00:00
1836	21	1836	2017-06-18 00:00:00
1837	22	1837	2017-07-27 00:00:00
1838	21	1838	2017-09-07 00:00:00
1839	22	1839	2019-06-08 00:00:00
1840	23	1840	2017-02-26 00:00:00
1841	21	1841	2018-02-09 00:00:00
1842	21	1842	2019-12-12 00:00:00
1843	21	1843	2017-09-18 00:00:00
1844	22	1844	2019-01-29 00:00:00
1845	21	1845	2019-03-25 00:00:00
1846	22	1846	2017-07-22 00:00:00
1847	23	1847	2018-03-04 00:00:00
1848	21	1848	2017-05-04 00:00:00
1849	23	1849	2017-08-23 00:00:00
1850	23	1850	2017-01-05 00:00:00
1851	21	1851	2017-10-17 00:00:00
1852	21	1852	2018-08-03 00:00:00
1853	23	1853	2018-03-11 00:00:00
1854	23	1854	2019-09-02 00:00:00
1855	23	1855	2018-11-19 00:00:00
1856	21	1856	2017-02-03 00:00:00
1857	23	1857	2017-12-21 00:00:00
1858	23	1858	2019-05-04 00:00:00
1859	23	1859	2019-05-08 00:00:00
1860	22	1860	2017-08-16 00:00:00
1861	21	1861	2017-03-19 00:00:00
1862	22	1862	2017-02-02 00:00:00
1863	22	1863	2018-01-20 00:00:00
1864	23	1864	2019-07-24 00:00:00
1865	23	1865	2019-07-05 00:00:00
1866	22	1866	2018-07-12 00:00:00
1867	21	1867	2019-09-21 00:00:00
1868	23	1868	2017-02-18 00:00:00
1869	22	1869	2018-06-05 00:00:00
1870	23	1870	2017-06-02 00:00:00
1871	21	1871	2017-10-19 00:00:00
1872	21	1872	2019-06-01 00:00:00
1873	21	1873	2018-10-13 00:00:00
1874	21	1874	2017-07-02 00:00:00
1875	23	1875	2017-12-04 00:00:00
1876	22	1876	2018-07-30 00:00:00
1877	23	1877	2019-01-03 00:00:00
1878	23	1878	2017-12-28 00:00:00
1879	21	1879	2018-01-20 00:00:00
1880	23	1880	2018-01-18 00:00:00
1881	21	1881	2019-02-19 00:00:00
1882	21	1882	2017-05-12 00:00:00
1883	23	1883	2018-11-08 00:00:00
1884	21	1884	2018-12-24 00:00:00
1885	23	1885	2017-08-20 00:00:00
1886	23	1886	2018-01-06 00:00:00
1887	21	1887	2019-04-19 00:00:00
1888	21	1888	2019-09-16 00:00:00
1889	23	1889	2018-07-10 00:00:00
1890	22	1890	2018-04-20 00:00:00
1891	22	1891	2017-04-22 00:00:00
1892	21	1892	2019-02-07 00:00:00
1893	23	1893	2018-10-22 00:00:00
1894	21	1894	2018-09-05 00:00:00
1895	21	1895	2017-05-12 00:00:00
1896	23	1896	2018-03-09 00:00:00
1897	22	1897	2017-11-29 00:00:00
1898	21	1898	2019-04-15 00:00:00
1899	21	1899	2017-11-14 00:00:00
1900	21	1900	2018-06-28 00:00:00
1901	22	1901	2019-09-05 00:00:00
1902	22	1902	2019-01-17 00:00:00
1903	21	1903	2017-11-14 00:00:00
1904	23	1904	2017-11-15 00:00:00
1905	23	1905	2019-07-05 00:00:00
1906	21	1906	2018-02-03 00:00:00
1907	23	1907	2018-09-29 00:00:00
1908	23	1908	2018-02-27 00:00:00
1909	22	1909	2017-02-23 00:00:00
1910	21	1910	2019-01-17 00:00:00
1911	22	1911	2018-03-06 00:00:00
1912	22	1912	2017-03-26 00:00:00
1913	21	1913	2019-09-08 00:00:00
1914	21	1914	2017-04-12 00:00:00
1915	22	1915	2017-11-01 00:00:00
1916	23	1916	2017-04-24 00:00:00
1917	21	1917	2017-12-17 00:00:00
1918	22	1918	2019-11-07 00:00:00
1919	21	1919	2019-11-21 00:00:00
1920	23	1920	2017-06-24 00:00:00
1921	23	1921	2018-01-04 00:00:00
1922	21	1922	2019-01-25 00:00:00
1923	21	1923	2017-10-14 00:00:00
1924	22	1924	2017-06-15 00:00:00
1925	23	1925	2019-11-01 00:00:00
1926	23	1926	2017-04-18 00:00:00
1927	21	1927	2019-07-18 00:00:00
1928	23	1928	2019-10-06 00:00:00
1929	22	1929	2019-04-23 00:00:00
1930	23	1930	2019-01-19 00:00:00
1931	21	1931	2019-08-22 00:00:00
1932	23	1932	2017-06-01 00:00:00
1933	22	1933	2018-10-16 00:00:00
1934	23	1934	2018-06-09 00:00:00
1935	21	1935	2018-06-03 00:00:00
1936	21	1936	2017-08-15 00:00:00
1937	21	1937	2017-06-17 00:00:00
1938	21	1938	2017-06-30 00:00:00
1939	23	1939	2019-09-21 00:00:00
1940	23	1940	2019-05-20 00:00:00
1941	21	1941	2018-03-19 00:00:00
1942	21	1942	2019-09-24 00:00:00
1943	22	1943	2018-01-22 00:00:00
1944	23	1944	2018-07-27 00:00:00
1945	23	1945	2018-04-14 00:00:00
1946	22	1946	2018-01-08 00:00:00
1947	22	1947	2018-05-05 00:00:00
1948	22	1948	2019-05-14 00:00:00
1949	21	1949	2017-06-19 00:00:00
1950	22	1950	2017-09-26 00:00:00
1951	23	1951	2018-09-23 00:00:00
1952	21	1952	2017-08-11 00:00:00
1953	21	1953	2017-07-13 00:00:00
1954	21	1954	2017-06-21 00:00:00
1955	22	1955	2019-11-08 00:00:00
1956	23	1956	2018-10-16 00:00:00
1957	21	1957	2019-01-09 00:00:00
1958	23	1958	2019-12-24 00:00:00
1959	22	1959	2017-10-25 00:00:00
1960	23	1960	2018-11-29 00:00:00
1961	21	1961	2017-03-15 00:00:00
1962	21	1962	2017-03-25 00:00:00
1963	22	1963	2019-05-21 00:00:00
1964	21	1964	2017-07-26 00:00:00
1965	23	1965	2017-04-26 00:00:00
1966	22	1966	2019-09-08 00:00:00
1967	21	1967	2019-11-24 00:00:00
1968	22	1968	2019-08-15 00:00:00
1969	22	1969	2019-05-30 00:00:00
1970	23	1970	2018-12-05 00:00:00
1971	21	1971	2017-01-13 00:00:00
1972	21	1972	2018-07-08 00:00:00
1973	23	1973	2019-09-05 00:00:00
1974	23	1974	2017-01-27 00:00:00
1975	23	1975	2018-10-02 00:00:00
1976	23	1976	2019-06-01 00:00:00
1977	23	1977	2017-10-01 00:00:00
1978	21	1978	2018-12-02 00:00:00
1979	23	1979	2018-03-18 00:00:00
1980	22	1980	2019-07-17 00:00:00
1981	22	1981	2018-10-12 00:00:00
1982	22	1982	2018-12-24 00:00:00
1983	22	1983	2017-10-19 00:00:00
1984	21	1984	2019-11-07 00:00:00
1985	23	1985	2019-11-29 00:00:00
1986	22	1986	2017-11-12 00:00:00
1987	23	1987	2018-04-13 00:00:00
1988	22	1988	2017-02-25 00:00:00
1989	21	1989	2017-10-19 00:00:00
1990	22	1990	2018-01-26 00:00:00
1991	22	1991	2017-06-06 00:00:00
1992	22	1992	2018-01-21 00:00:00
1993	22	1993	2018-12-25 00:00:00
1994	22	1994	2017-08-28 00:00:00
1995	22	1995	2019-01-20 00:00:00
1996	23	1996	2018-10-17 00:00:00
1997	22	1997	2019-04-02 00:00:00
1998	22	1998	2019-11-15 00:00:00
1999	23	1999	2018-06-09 00:00:00
2000	21	2000	2019-01-25 00:00:00
\.


--
-- Data for Name: lessons; Type: TABLE DATA; Schema: driving_school; Owner: stephan
--

COPY driving_school.lessons (lesson, client, instructor, car, start) FROM stdin;
1	1	2	14	2018-11-23 01:15:00
2	1	2	14	2017-07-24 22:30:00
3	1	2	14	2017-08-03 03:45:00
4	2	19	13	2019-07-18 06:00:00
5	2	19	13	2018-12-30 08:15:00
6	2	19	13	2019-05-30 06:30:00
7	2	19	13	2020-04-28 05:45:00
8	2	19	13	2020-04-07 16:00:00
9	2	19	13	2019-03-10 14:00:00
10	2	19	13	2020-05-29 20:00:00
11	2	19	13	2018-09-20 16:45:00
12	2	19	13	2019-10-17 15:45:00
13	2	19	13	2020-08-23 01:15:00
14	2	19	13	2019-08-23 11:00:00
15	2	19	13	2019-04-27 05:30:00
16	3	17	19	2020-02-23 05:45:00
17	3	17	19	2018-07-02 06:00:00
18	3	17	19	2019-02-21 15:15:00
19	3	17	19	2018-03-11 11:45:00
20	3	17	19	2019-03-04 23:15:00
21	3	17	19	2019-11-04 16:00:00
22	4	11	18	2018-11-19 04:00:00
23	4	11	18	2018-11-19 13:45:00
24	4	11	18	2019-09-08 10:00:00
25	4	11	18	2018-10-26 18:30:00
26	4	11	18	2018-06-18 22:30:00
27	4	11	18	2019-11-04 01:30:00
28	5	1	19	2020-07-08 00:30:00
29	5	1	19	2019-11-24 15:45:00
30	5	1	19	2020-10-03 02:45:00
31	6	17	19	2017-04-19 16:45:00
32	6	17	19	2017-05-19 21:15:00
33	6	17	19	2018-01-20 03:00:00
34	6	17	19	2017-03-24 18:30:00
35	6	17	19	2018-10-24 03:15:00
36	6	17	19	2017-06-21 10:30:00
37	6	17	19	2017-05-08 09:30:00
38	7	17	2	2019-06-19 21:45:00
39	7	17	2	2020-01-08 19:45:00
40	7	17	2	2019-08-25 18:00:00
41	7	17	2	2020-03-14 14:15:00
42	7	17	2	2019-05-02 15:30:00
43	8	18	3	2020-01-25 16:00:00
44	8	18	3	2019-09-30 23:45:00
45	8	18	3	2020-02-03 21:00:00
46	8	18	3	2018-08-24 18:15:00
47	8	18	3	2020-05-07 15:00:00
48	9	19	1	2018-12-06 08:00:00
49	9	19	1	2020-02-03 03:00:00
50	9	19	1	2019-05-29 08:00:00
51	10	1	5	2019-02-15 20:30:00
52	10	1	5	2018-08-17 12:45:00
53	10	1	5	2018-05-02 06:30:00
54	10	1	5	2019-08-30 01:15:00
55	10	1	5	2018-06-26 13:00:00
56	10	1	5	2019-12-28 08:30:00
57	10	1	5	2019-09-23 05:30:00
58	10	1	5	2019-12-30 07:15:00
59	11	13	14	2019-09-08 00:00:00
60	12	11	5	2019-05-22 08:15:00
61	12	11	5	2019-06-15 15:30:00
62	12	11	5	2018-08-07 22:30:00
63	12	11	5	2019-08-11 00:00:00
64	12	11	5	2018-01-15 20:15:00
65	12	11	5	2019-02-04 04:30:00
66	12	11	5	2018-02-20 05:00:00
67	12	11	5	2017-11-15 00:15:00
68	12	11	5	2019-07-24 19:15:00
69	12	11	5	2018-04-05 11:30:00
70	12	11	5	2019-07-27 07:30:00
71	12	11	5	2018-11-13 11:30:00
72	12	11	5	2018-11-09 11:00:00
73	12	11	5	2019-06-03 16:45:00
74	12	11	5	2017-09-13 23:15:00
75	13	13	14	2018-08-02 11:45:00
76	13	13	14	2019-09-15 17:15:00
77	13	13	14	2020-04-15 09:15:00
78	13	13	14	2019-05-19 00:30:00
79	13	13	14	2019-10-04 11:45:00
80	13	13	14	2019-02-03 17:30:00
81	14	12	17	2019-09-01 04:00:00
82	14	12	17	2020-08-07 19:15:00
83	14	12	17	2020-06-26 14:15:00
84	14	12	17	2020-06-07 23:45:00
85	14	12	17	2019-11-20 04:30:00
86	14	12	17	2019-12-09 23:45:00
87	14	12	17	2020-01-23 08:00:00
88	15	15	2	2017-09-30 20:45:00
89	16	3	19	2019-07-25 15:15:00
90	17	6	20	2019-04-29 14:15:00
91	17	6	20	2018-05-23 13:30:00
92	17	6	20	2017-10-15 12:45:00
93	17	6	20	2019-05-28 19:00:00
94	17	6	20	2017-10-29 10:00:00
95	17	6	20	2018-11-19 03:30:00
96	17	6	20	2019-04-24 04:45:00
97	17	6	20	2019-03-27 13:15:00
98	18	19	15	2018-11-19 23:15:00
99	18	19	15	2018-11-30 12:30:00
100	18	19	15	2018-10-11 18:15:00
101	18	19	15	2019-03-23 11:30:00
102	18	19	15	2018-01-13 19:15:00
103	18	19	15	2017-11-05 15:15:00
104	18	19	15	2019-03-24 15:00:00
105	18	19	15	2019-06-22 16:45:00
106	18	19	15	2017-07-01 05:15:00
107	18	19	15	2019-01-03 13:30:00
108	18	19	15	2018-09-04 06:45:00
109	19	17	7	2020-05-15 01:00:00
110	19	17	7	2019-09-19 20:45:00
111	19	17	7	2020-10-28 11:15:00
112	19	17	7	2019-11-28 05:30:00
113	20	10	12	2020-08-01 02:45:00
114	20	10	12	2021-05-14 06:30:00
115	20	10	12	2021-07-28 03:00:00
116	20	10	12	2020-10-02 01:30:00
117	20	10	12	2020-11-30 23:00:00
118	20	10	12	2021-03-04 22:15:00
119	20	10	12	2020-06-12 07:45:00
120	20	10	12	2021-04-06 06:00:00
121	20	10	12	2020-01-17 04:30:00
122	21	19	17	2020-09-24 04:00:00
123	21	19	17	2019-11-20 05:30:00
124	21	19	17	2020-04-01 14:15:00
125	21	19	17	2020-05-22 14:15:00
126	21	19	17	2018-10-20 12:00:00
127	21	19	17	2019-04-04 14:00:00
128	21	19	17	2019-11-27 23:15:00
129	21	19	17	2020-03-05 00:45:00
130	21	19	17	2019-08-16 11:00:00
131	21	19	17	2020-02-05 19:30:00
132	21	19	17	2020-01-13 23:30:00
133	21	19	17	2020-05-19 22:45:00
134	21	19	17	2019-07-04 04:30:00
135	22	14	6	2018-12-16 13:15:00
136	22	14	6	2019-12-06 03:00:00
137	22	14	6	2019-06-04 19:15:00
138	22	14	6	2019-12-07 18:15:00
139	22	14	6	2018-10-14 19:30:00
140	22	14	6	2019-03-07 18:00:00
141	22	14	6	2019-06-05 03:45:00
142	22	14	6	2018-11-21 09:45:00
143	22	14	6	2018-11-16 17:45:00
144	22	14	6	2020-07-11 06:15:00
145	22	14	6	2019-12-12 17:00:00
146	22	14	6	2020-02-03 02:15:00
147	22	14	6	2019-12-30 11:00:00
148	22	14	6	2018-12-21 10:15:00
149	22	14	6	2019-07-22 09:45:00
150	23	17	13	2020-03-08 13:45:00
151	23	17	13	2021-03-12 06:15:00
152	23	17	13	2021-03-15 12:00:00
153	23	17	13	2019-12-22 05:30:00
154	23	17	13	2020-04-11 15:00:00
155	23	17	13	2020-12-17 19:00:00
156	23	17	13	2021-06-09 02:30:00
157	23	17	13	2021-05-12 12:30:00
158	23	17	13	2020-01-10 15:00:00
159	23	17	13	2021-10-08 02:45:00
160	23	17	13	2020-11-30 09:45:00
161	23	17	13	2020-12-16 15:00:00
162	23	17	13	2021-04-26 14:00:00
163	23	17	13	2020-02-10 02:15:00
164	24	20	9	2017-09-20 18:00:00
165	24	20	9	2017-10-16 13:00:00
166	24	20	9	2018-03-26 09:00:00
167	24	20	9	2018-02-12 20:15:00
168	24	20	9	2018-08-05 02:15:00
169	24	20	9	2018-10-19 15:30:00
170	24	20	9	2018-10-15 11:15:00
171	24	20	9	2018-12-27 09:30:00
172	24	20	9	2018-03-19 05:00:00
173	25	20	6	2020-10-12 18:15:00
174	25	20	6	2020-09-01 04:30:00
175	25	20	6	2019-07-05 19:45:00
176	25	20	6	2019-09-05 19:00:00
177	25	20	6	2020-12-22 07:00:00
178	26	2	20	2018-10-10 12:15:00
179	26	2	20	2018-05-09 18:15:00
180	26	2	20	2018-04-02 11:15:00
181	26	2	20	2017-06-24 16:00:00
182	26	2	20	2018-07-25 10:45:00
183	26	2	20	2017-10-21 23:00:00
184	27	18	14	2020-12-04 05:30:00
185	27	18	14	2020-07-09 07:15:00
186	27	18	14	2020-02-20 01:00:00
187	27	18	14	2021-03-28 09:15:00
188	27	18	14	2020-02-05 02:15:00
189	27	18	14	2019-12-11 03:45:00
190	27	18	14	2021-02-23 13:00:00
191	27	18	14	2020-05-27 20:15:00
192	27	18	14	2020-12-25 01:30:00
193	27	18	14	2020-04-27 20:00:00
194	27	18	14	2020-03-21 06:30:00
195	27	18	14	2021-06-12 12:15:00
196	27	18	14	2020-05-08 18:00:00
197	28	3	9	2019-03-14 12:30:00
198	28	3	9	2018-09-29 11:45:00
199	28	3	9	2018-01-25 07:30:00
200	28	3	9	2018-12-23 19:00:00
201	28	3	9	2017-11-07 17:00:00
202	28	3	9	2017-12-09 21:45:00
203	28	3	9	2018-12-29 18:00:00
204	28	3	9	2019-05-11 10:15:00
205	28	3	9	2018-02-09 17:45:00
206	28	3	9	2018-09-26 04:00:00
207	28	3	9	2017-10-10 04:00:00
208	29	7	20	2019-11-26 19:30:00
209	29	7	20	2020-09-12 07:45:00
210	29	7	20	2020-10-26 19:30:00
211	29	7	20	2020-04-19 16:30:00
212	29	7	20	2019-10-16 15:00:00
213	29	7	20	2019-04-19 05:15:00
214	29	7	20	2019-05-26 03:15:00
215	29	7	20	2020-05-07 14:15:00
216	29	7	20	2019-04-14 04:30:00
217	29	7	20	2019-11-15 19:15:00
218	30	20	3	2019-04-25 19:15:00
219	30	20	3	2018-11-09 08:30:00
220	30	20	3	2019-04-27 16:45:00
221	30	20	3	2019-11-16 08:30:00
222	30	20	3	2019-11-03 14:30:00
223	30	20	3	2018-10-17 21:15:00
224	31	3	3	2020-04-03 21:30:00
225	31	3	3	2019-05-25 04:15:00
226	31	3	3	2020-10-17 23:45:00
227	31	3	3	2019-09-19 22:00:00
228	31	3	3	2019-10-18 16:00:00
229	31	3	3	2019-12-16 09:45:00
230	31	3	3	2021-04-05 13:15:00
231	31	3	3	2020-10-15 21:15:00
232	31	3	3	2019-07-17 10:45:00
233	31	3	3	2019-09-13 17:45:00
234	31	3	3	2021-01-07 17:45:00
235	31	3	3	2021-01-03 10:15:00
236	31	3	3	2020-03-25 05:15:00
237	32	11	9	2019-10-28 01:30:00
238	32	11	9	2019-08-24 09:15:00
239	32	11	9	2019-03-25 11:15:00
240	32	11	9	2019-02-12 22:45:00
241	32	11	9	2019-02-24 08:15:00
242	32	11	9	2020-02-18 08:15:00
243	32	11	9	2019-04-27 02:30:00
244	32	11	9	2020-06-27 02:15:00
245	32	11	9	2019-01-21 04:15:00
246	32	11	9	2018-12-29 19:15:00
247	32	11	9	2019-10-17 11:00:00
248	32	11	9	2019-01-05 18:15:00
249	33	1	6	2018-02-22 13:00:00
250	33	1	6	2019-07-03 04:30:00
251	33	1	6	2019-04-19 15:30:00
252	34	4	8	2019-12-11 01:00:00
253	34	4	8	2019-06-27 16:30:00
254	34	4	8	2018-08-25 15:00:00
255	34	4	8	2019-10-26 06:30:00
256	34	4	8	2019-04-24 22:30:00
257	34	4	8	2020-01-06 11:45:00
258	34	4	8	2019-11-18 12:15:00
259	34	4	8	2019-11-25 23:15:00
260	35	17	20	2019-08-28 21:00:00
261	35	17	20	2020-06-20 04:30:00
262	35	17	20	2019-07-14 21:45:00
263	35	17	20	2020-05-23 11:30:00
264	35	17	20	2020-01-01 19:45:00
265	35	17	20	2020-01-12 06:45:00
266	35	17	20	2018-11-03 05:45:00
267	35	17	20	2019-01-04 00:15:00
268	35	17	20	2019-06-07 02:15:00
269	35	17	20	2019-03-08 09:15:00
270	35	17	20	2020-02-11 20:00:00
271	35	17	20	2019-11-09 00:15:00
272	35	17	20	2019-11-16 12:45:00
273	35	17	20	2019-01-06 14:30:00
274	36	17	3	2018-10-21 04:30:00
275	36	17	3	2018-05-14 20:30:00
276	36	17	3	2018-05-30 14:15:00
277	36	17	3	2019-05-27 06:30:00
278	36	17	3	2019-11-17 03:00:00
279	36	17	3	2018-05-20 13:00:00
280	36	17	3	2019-02-10 21:00:00
281	37	1	20	2021-03-19 16:45:00
282	37	1	20	2020-09-29 06:30:00
283	37	1	20	2020-12-10 01:15:00
284	37	1	20	2019-08-23 23:00:00
285	37	1	20	2021-05-08 04:00:00
286	37	1	20	2019-07-15 12:45:00
287	37	1	20	2020-12-28 14:00:00
288	37	1	20	2020-04-20 12:30:00
289	38	5	8	2020-03-19 15:15:00
290	38	5	8	2019-08-07 16:00:00
291	38	5	8	2020-05-13 05:15:00
292	38	5	8	2021-03-06 19:30:00
293	38	5	8	2019-07-05 16:45:00
294	38	5	8	2019-12-20 10:00:00
295	38	5	8	2020-02-04 20:45:00
296	38	5	8	2021-01-12 15:00:00
297	38	5	8	2020-08-11 16:45:00
298	38	5	8	2019-08-05 05:15:00
299	38	5	8	2020-11-10 07:45:00
300	38	5	8	2021-06-04 11:45:00
301	38	5	8	2021-03-23 03:15:00
302	38	5	8	2019-11-05 02:15:00
303	38	5	8	2021-06-11 19:30:00
304	39	3	16	2017-08-12 08:00:00
305	39	3	16	2017-11-26 21:00:00
306	39	3	16	2017-10-28 11:15:00
307	39	3	16	2018-03-27 15:15:00
308	39	3	16	2018-02-14 03:30:00
309	39	3	16	2019-02-11 07:00:00
310	39	3	16	2018-08-10 02:45:00
311	39	3	16	2019-04-12 22:15:00
312	39	3	16	2017-11-13 16:45:00
313	40	18	11	2020-09-22 04:45:00
314	40	18	11	2020-01-02 03:15:00
315	40	18	11	2019-05-03 23:15:00
316	40	18	11	2019-08-05 04:00:00
317	40	18	11	2019-02-26 10:30:00
318	40	18	11	2020-07-26 05:45:00
319	40	18	11	2019-03-23 23:45:00
320	41	13	13	2019-12-27 05:45:00
321	41	13	13	2020-10-19 14:45:00
322	41	13	13	2020-10-02 03:30:00
323	41	13	13	2019-10-28 16:30:00
324	41	13	13	2020-08-01 01:30:00
325	42	13	5	2019-07-27 14:30:00
326	42	13	5	2020-07-01 14:15:00
327	42	13	5	2019-12-07 05:45:00
328	42	13	5	2020-01-06 05:30:00
329	42	13	5	2019-02-25 11:30:00
330	42	13	5	2019-04-28 21:45:00
331	43	5	6	2018-10-06 14:30:00
332	43	5	6	2018-08-11 15:30:00
333	43	5	6	2020-03-14 20:30:00
334	43	5	6	2020-05-15 19:45:00
335	43	5	6	2020-04-23 02:15:00
336	43	5	6	2019-02-02 06:45:00
337	43	5	6	2019-04-03 01:30:00
338	43	5	6	2020-01-01 04:45:00
339	43	5	6	2019-08-20 22:30:00
340	44	14	20	2019-01-14 09:45:00
341	44	14	20	2020-02-26 22:45:00
342	45	8	11	2020-06-04 00:00:00
343	45	8	11	2019-06-07 02:00:00
344	45	8	11	2020-05-01 16:00:00
345	45	8	11	2021-03-07 19:30:00
346	45	8	11	2020-02-08 14:00:00
347	45	8	11	2020-10-08 13:15:00
348	45	8	11	2020-08-05 08:45:00
349	45	8	11	2020-09-16 11:45:00
350	46	16	5	2018-08-07 20:00:00
351	47	9	1	2018-07-27 11:30:00
352	47	9	1	2018-03-18 03:00:00
353	47	9	1	2018-06-13 09:45:00
354	47	9	1	2017-10-24 02:30:00
355	47	9	1	2018-02-23 15:45:00
356	47	9	1	2018-10-17 04:15:00
357	47	9	1	2019-01-15 22:15:00
358	47	9	1	2017-02-15 00:00:00
359	47	9	1	2017-09-09 09:30:00
360	47	9	1	2017-10-29 02:00:00
361	47	9	1	2017-12-19 10:30:00
362	47	9	1	2017-06-18 16:30:00
363	47	9	1	2018-03-20 08:30:00
364	47	9	1	2018-01-08 07:45:00
365	48	18	5	2019-02-18 22:15:00
366	48	18	5	2019-06-24 15:15:00
367	48	18	5	2019-09-08 16:15:00
368	48	18	5	2019-10-16 18:15:00
369	48	18	5	2019-04-13 08:15:00
370	48	18	5	2018-12-28 08:00:00
371	49	19	20	2019-05-07 22:15:00
372	49	19	20	2018-08-12 18:15:00
373	49	19	20	2018-10-21 00:15:00
374	49	19	20	2019-07-19 04:00:00
375	49	19	20	2019-06-30 19:45:00
376	49	19	20	2019-06-30 02:00:00
377	49	19	20	2018-10-02 12:45:00
378	50	15	3	2019-06-04 03:45:00
379	50	15	3	2020-05-15 20:30:00
380	50	15	3	2020-02-26 01:00:00
381	50	15	3	2020-10-04 23:15:00
382	50	15	3	2019-09-24 02:30:00
383	50	15	3	2019-04-10 01:45:00
384	50	15	3	2019-11-18 22:30:00
385	50	15	3	2020-12-21 18:00:00
386	50	15	3	2019-05-17 03:15:00
387	50	15	3	2020-06-28 06:45:00
388	50	15	3	2019-03-25 12:30:00
389	50	15	3	2020-01-26 18:00:00
390	51	15	11	2019-02-04 15:15:00
391	51	15	11	2019-09-22 09:00:00
392	51	15	11	2020-04-29 02:45:00
393	51	15	11	2019-02-03 16:00:00
394	51	15	11	2018-12-16 10:30:00
395	51	15	11	2019-03-17 04:00:00
396	51	15	11	2020-10-06 09:45:00
397	51	15	11	2019-05-04 17:45:00
398	51	15	11	2018-12-12 23:30:00
399	51	15	11	2019-03-13 02:15:00
400	52	17	15	2019-06-30 17:15:00
401	52	17	15	2019-01-04 00:45:00
402	53	17	9	2017-11-21 11:00:00
403	53	17	9	2017-07-22 07:45:00
404	53	17	9	2017-04-11 10:15:00
405	53	17	9	2017-05-25 10:30:00
406	53	17	9	2018-03-09 15:45:00
407	53	17	9	2018-11-28 02:00:00
408	53	17	9	2018-09-02 21:00:00
409	53	17	9	2017-09-16 05:30:00
410	53	17	9	2018-06-18 19:45:00
411	53	17	9	2017-06-08 13:15:00
412	53	17	9	2018-08-21 08:00:00
413	53	17	9	2017-03-11 10:45:00
414	53	17	9	2017-05-29 16:45:00
415	53	17	9	2018-02-18 17:00:00
416	53	17	9	2019-01-29 12:30:00
417	54	17	16	2020-07-06 15:45:00
418	54	17	16	2020-04-12 15:00:00
419	55	12	16	2018-08-12 19:15:00
420	55	12	16	2019-03-01 12:15:00
421	55	12	16	2018-11-01 12:15:00
422	55	12	16	2017-07-04 13:45:00
423	55	12	16	2018-04-10 19:15:00
424	55	12	16	2018-09-19 09:15:00
425	55	12	16	2019-01-03 19:30:00
426	55	12	16	2017-07-29 00:30:00
427	55	12	16	2019-06-29 21:00:00
428	55	12	16	2018-07-16 23:15:00
429	55	12	16	2018-12-17 15:15:00
430	55	12	16	2018-01-03 00:00:00
431	56	19	15	2020-06-22 14:45:00
432	56	19	15	2021-08-28 21:30:00
433	56	19	15	2020-06-30 14:00:00
434	56	19	15	2020-04-11 11:00:00
435	56	19	15	2020-01-04 00:15:00
436	56	19	15	2021-10-15 10:45:00
437	56	19	15	2021-08-22 01:45:00
438	56	19	15	2021-09-28 11:45:00
439	56	19	15	2021-11-26 22:15:00
440	56	19	15	2020-07-07 06:00:00
441	56	19	15	2021-11-14 07:30:00
442	56	19	15	2020-07-26 09:45:00
443	56	19	15	2020-08-29 12:00:00
444	56	19	15	2020-03-04 16:30:00
445	56	19	15	2021-11-03 09:15:00
446	57	14	10	2018-10-06 13:30:00
447	57	14	10	2018-11-08 04:30:00
448	57	14	10	2017-08-05 05:15:00
449	57	14	10	2017-07-21 21:15:00
450	57	14	10	2017-12-16 09:45:00
451	58	14	12	2020-05-09 01:45:00
452	58	14	12	2019-08-21 22:30:00
453	58	14	12	2020-08-16 15:00:00
454	58	14	12	2020-07-28 04:30:00
455	58	14	12	2020-02-01 06:30:00
456	58	14	12	2021-02-04 21:30:00
457	58	14	12	2021-04-24 05:15:00
458	58	14	12	2020-05-28 19:45:00
459	58	14	12	2021-01-19 22:00:00
460	58	14	12	2020-04-15 06:45:00
461	58	14	12	2021-01-02 10:45:00
462	58	14	12	2020-05-19 20:00:00
463	59	16	1	2020-05-18 20:00:00
464	59	16	1	2021-05-04 22:00:00
465	59	16	1	2020-02-22 11:30:00
466	59	16	1	2019-06-20 10:30:00
467	59	16	1	2020-08-21 14:00:00
468	59	16	1	2019-07-01 07:30:00
469	59	16	1	2019-09-27 21:15:00
470	59	16	1	2019-09-24 12:15:00
471	59	16	1	2020-12-19 13:45:00
472	59	16	1	2020-06-13 09:30:00
473	59	16	1	2020-05-23 02:30:00
474	59	16	1	2021-02-12 21:15:00
475	59	16	1	2019-07-30 15:00:00
476	59	16	1	2020-07-30 12:30:00
477	59	16	1	2020-09-16 15:45:00
478	60	15	7	2018-09-01 21:15:00
479	60	15	7	2017-10-05 03:45:00
480	60	15	7	2018-12-16 20:15:00
481	60	15	7	2017-12-16 02:00:00
482	60	15	7	2017-09-27 03:45:00
483	60	15	7	2017-11-27 06:00:00
484	60	15	7	2018-12-02 10:00:00
485	60	15	7	2018-01-30 04:00:00
486	60	15	7	2018-12-25 21:00:00
487	60	15	7	2018-11-13 09:00:00
488	61	20	14	2019-07-24 07:15:00
489	61	20	14	2019-05-25 07:15:00
490	61	20	14	2019-09-20 11:45:00
491	61	20	14	2019-08-09 06:45:00
492	61	20	14	2020-01-04 09:00:00
493	61	20	14	2019-11-05 18:15:00
494	61	20	14	2019-05-10 23:30:00
495	61	20	14	2019-05-14 23:45:00
496	61	20	14	2019-08-20 12:15:00
497	61	20	14	2019-03-21 17:00:00
498	61	20	14	2019-08-24 12:45:00
499	62	1	10	2018-12-04 02:45:00
500	62	1	10	2018-09-26 18:30:00
501	62	1	10	2018-02-23 17:15:00
502	62	1	10	2019-02-11 04:45:00
503	63	4	18	2018-02-01 09:30:00
504	63	4	18	2018-02-08 14:15:00
505	63	4	18	2018-12-25 01:15:00
506	63	4	18	2017-08-20 23:15:00
507	63	4	18	2019-05-04 04:30:00
508	63	4	18	2017-08-06 22:45:00
509	63	4	18	2018-03-27 14:30:00
510	63	4	18	2019-02-12 23:45:00
511	63	4	18	2017-12-16 17:15:00
512	63	4	18	2017-12-14 15:45:00
513	63	4	18	2019-01-24 15:00:00
514	63	4	18	2018-07-30 04:30:00
515	63	4	18	2018-03-30 19:30:00
516	63	4	18	2017-10-01 04:30:00
517	63	4	18	2018-11-25 20:45:00
518	64	3	1	2019-07-11 04:00:00
519	64	3	1	2019-01-15 09:45:00
520	64	3	1	2018-11-27 06:00:00
521	64	3	1	2019-04-12 19:00:00
522	64	3	1	2020-06-18 19:15:00
523	64	3	1	2020-08-23 14:30:00
524	64	3	1	2020-07-01 00:30:00
525	64	3	1	2019-06-25 13:45:00
526	64	3	1	2019-06-13 00:30:00
527	64	3	1	2018-10-12 14:30:00
528	64	3	1	2020-01-22 07:45:00
529	64	3	1	2018-10-30 18:45:00
530	65	16	12	2021-07-02 12:45:00
531	65	16	12	2020-08-19 06:00:00
532	66	3	2	2019-06-13 05:00:00
533	66	3	2	2018-09-04 10:45:00
534	67	7	12	2020-07-10 02:15:00
535	67	7	12	2020-07-30 22:30:00
536	67	7	12	2020-02-11 03:00:00
537	67	7	12	2020-10-18 09:15:00
538	68	20	11	2019-02-03 00:00:00
539	68	20	11	2018-08-01 06:30:00
540	68	20	11	2018-12-12 07:15:00
541	68	20	11	2020-06-29 15:45:00
542	68	20	11	2019-03-11 07:15:00
543	68	20	11	2020-02-14 10:30:00
544	68	20	11	2018-09-30 10:45:00
545	68	20	11	2020-02-23 01:45:00
546	68	20	11	2020-06-22 19:15:00
547	68	20	11	2019-11-20 14:45:00
548	68	20	11	2018-09-16 13:45:00
549	69	16	1	2021-07-01 04:00:00
550	70	7	3	2020-07-03 05:15:00
551	70	7	3	2020-03-21 13:15:00
552	70	7	3	2020-09-28 16:45:00
553	70	7	3	2020-02-22 20:15:00
554	70	7	3	2018-12-23 18:15:00
555	70	7	3	2020-02-26 01:30:00
556	70	7	3	2020-06-05 17:30:00
557	70	7	3	2019-06-05 08:15:00
558	70	7	3	2020-09-11 14:30:00
559	71	11	5	2019-09-16 17:45:00
560	71	11	5	2020-02-06 23:00:00
561	71	11	5	2020-05-30 16:15:00
562	71	11	5	2018-11-16 01:30:00
563	71	11	5	2019-10-23 03:45:00
564	71	11	5	2020-01-21 13:30:00
565	71	11	5	2019-06-22 09:00:00
566	71	11	5	2020-03-08 21:30:00
567	71	11	5	2019-04-04 20:15:00
568	72	2	3	2020-06-24 06:15:00
569	72	2	3	2019-08-14 08:45:00
570	72	2	3	2019-08-27 12:30:00
571	72	2	3	2020-12-26 13:00:00
572	72	2	3	2020-08-08 06:45:00
573	72	2	3	2020-12-30 20:15:00
574	72	2	3	2020-12-05 21:45:00
575	73	14	17	2018-02-27 06:15:00
576	73	14	17	2019-07-18 07:30:00
577	73	14	17	2018-12-23 22:30:00
578	73	14	17	2019-02-24 21:00:00
579	73	14	17	2019-01-22 16:15:00
580	73	14	17	2018-11-29 20:15:00
581	73	14	17	2018-09-11 15:00:00
582	73	14	17	2018-01-11 17:30:00
583	73	14	17	2019-06-21 05:15:00
584	74	2	8	2018-03-21 12:45:00
585	74	2	8	2019-12-23 16:00:00
586	74	2	8	2018-11-11 19:00:00
587	74	2	8	2019-12-30 10:00:00
588	74	2	8	2019-02-16 22:45:00
589	74	2	8	2018-02-04 04:15:00
590	75	17	11	2020-02-16 04:30:00
591	75	17	11	2020-09-10 16:30:00
592	75	17	11	2019-09-28 09:30:00
593	75	17	11	2019-11-18 11:15:00
594	75	17	11	2020-05-17 03:15:00
595	75	17	11	2019-02-07 17:00:00
596	76	1	15	2019-05-08 00:00:00
597	76	1	15	2019-01-28 15:15:00
598	76	1	15	2019-11-05 22:45:00
599	77	20	9	2017-10-12 22:45:00
600	77	20	9	2017-05-06 21:15:00
601	77	20	9	2018-01-24 22:45:00
602	77	20	9	2018-01-03 12:30:00
603	77	20	9	2017-05-24 08:00:00
604	77	20	9	2017-07-15 22:30:00
605	77	20	9	2017-09-21 11:30:00
606	77	20	9	2017-07-01 13:30:00
607	77	20	9	2018-09-28 16:30:00
608	78	9	2	2018-03-14 06:00:00
609	78	9	2	2019-03-23 07:00:00
610	78	9	2	2019-01-09 22:15:00
611	78	9	2	2018-07-29 16:00:00
612	78	9	2	2018-01-09 12:15:00
613	78	9	2	2018-01-09 08:00:00
614	78	9	2	2018-05-18 04:45:00
615	78	9	2	2017-10-05 18:15:00
616	78	9	2	2018-10-27 20:00:00
617	78	9	2	2018-06-21 12:30:00
618	78	9	2	2018-05-22 00:30:00
619	78	9	2	2018-09-16 13:00:00
620	78	9	2	2017-08-11 02:00:00
621	78	9	2	2017-10-22 13:30:00
622	79	11	9	2018-12-22 14:00:00
623	79	11	9	2018-11-18 10:15:00
624	79	11	9	2018-07-08 10:30:00
625	79	11	9	2019-09-23 05:15:00
626	80	5	8	2018-08-17 21:30:00
627	80	5	8	2018-12-18 16:30:00
628	80	5	8	2018-01-10 20:45:00
629	80	5	8	2018-10-11 20:30:00
630	80	5	8	2019-05-16 14:30:00
631	80	5	8	2018-09-19 13:45:00
632	81	15	7	2019-03-11 04:30:00
633	81	15	7	2019-02-18 18:00:00
634	81	15	7	2018-04-26 18:30:00
635	81	15	7	2019-11-15 05:30:00
636	81	15	7	2018-05-15 08:00:00
637	82	20	18	2020-07-30 17:00:00
638	82	20	18	2020-05-16 15:30:00
639	82	20	18	2019-12-27 18:00:00
640	82	20	18	2020-02-20 17:00:00
641	82	20	18	2021-04-12 07:15:00
642	82	20	18	2020-11-24 10:15:00
643	82	20	18	2020-08-21 01:15:00
644	82	20	18	2021-03-21 21:00:00
645	82	20	18	2021-05-17 10:15:00
646	82	20	18	2021-07-12 20:30:00
647	82	20	18	2020-12-08 15:00:00
648	82	20	18	2020-09-17 20:45:00
649	83	1	10	2018-04-06 21:45:00
650	83	1	10	2018-04-20 06:45:00
651	83	1	10	2018-03-30 20:00:00
652	83	1	10	2018-04-06 00:15:00
653	83	1	10	2017-07-27 22:15:00
654	83	1	10	2017-10-29 14:45:00
655	83	1	10	2018-10-24 10:00:00
656	83	1	10	2018-10-29 11:45:00
657	83	1	10	2017-08-03 17:45:00
658	83	1	10	2018-04-06 22:30:00
659	83	1	10	2017-10-20 16:30:00
660	83	1	10	2017-04-15 08:45:00
661	83	1	10	2018-01-18 02:45:00
662	83	1	10	2019-02-19 02:45:00
663	84	19	12	2019-01-12 01:30:00
664	84	19	12	2020-01-04 04:45:00
665	84	19	12	2019-09-26 03:00:00
666	84	19	12	2019-08-03 10:00:00
667	84	19	12	2019-08-24 13:30:00
668	84	19	12	2020-06-08 11:00:00
669	85	2	12	2020-03-10 04:45:00
670	85	2	12	2020-08-20 04:30:00
671	85	2	12	2021-04-08 02:45:00
672	85	2	12	2019-10-18 01:15:00
673	85	2	12	2019-09-17 04:30:00
674	86	5	16	2020-04-20 13:00:00
675	87	6	15	2018-08-27 06:00:00
676	87	6	15	2019-05-19 18:00:00
677	87	6	15	2019-06-03 14:30:00
678	87	6	15	2018-04-17 03:45:00
679	87	6	15	2019-04-26 17:30:00
680	87	6	15	2017-07-11 11:45:00
681	87	6	15	2017-10-11 17:15:00
682	87	6	15	2019-05-14 05:15:00
683	87	6	15	2018-03-07 10:45:00
684	87	6	15	2019-04-27 21:00:00
685	87	6	15	2018-04-18 06:15:00
686	87	6	15	2017-10-06 04:15:00
687	87	6	15	2017-08-02 20:45:00
688	87	6	15	2018-04-25 01:45:00
689	88	9	19	2019-10-03 19:45:00
690	88	9	19	2019-01-02 16:15:00
691	88	9	19	2019-08-17 19:15:00
692	88	9	19	2019-12-06 15:15:00
693	88	9	19	2019-11-21 23:15:00
694	88	9	19	2018-12-04 01:45:00
695	88	9	19	2018-07-15 10:45:00
696	88	9	19	2020-02-03 11:15:00
697	88	9	19	2018-08-09 20:30:00
698	88	9	19	2018-08-25 07:15:00
699	88	9	19	2020-01-19 13:30:00
700	88	9	19	2020-01-19 07:00:00
701	88	9	19	2019-12-27 17:15:00
702	88	9	19	2018-12-17 04:45:00
703	89	3	3	2019-06-28 10:15:00
704	89	3	3	2018-09-09 18:15:00
705	89	3	3	2019-07-04 08:15:00
706	89	3	3	2020-01-13 19:30:00
707	89	3	3	2019-10-24 09:45:00
708	89	3	3	2020-03-18 08:00:00
709	90	20	17	2019-11-30 02:30:00
710	90	20	17	2019-05-24 20:15:00
711	90	20	17	2019-08-12 15:00:00
712	90	20	17	2020-08-22 08:45:00
713	90	20	17	2020-06-19 00:00:00
714	90	20	17	2019-05-27 09:00:00
715	90	20	17	2020-05-10 05:15:00
716	90	20	17	2020-07-08 05:30:00
717	90	20	17	2019-11-15 23:45:00
718	90	20	17	2020-08-09 18:45:00
719	90	20	17	2019-05-13 07:15:00
720	90	20	17	2019-05-21 13:30:00
721	91	18	18	2019-02-23 06:45:00
722	91	18	18	2017-10-26 22:15:00
723	91	18	18	2017-10-11 20:00:00
724	91	18	18	2017-04-15 20:30:00
725	91	18	18	2018-11-11 21:00:00
726	91	18	18	2018-03-21 14:15:00
727	91	18	18	2017-10-12 11:00:00
728	91	18	18	2018-10-23 00:45:00
729	91	18	18	2017-03-24 17:00:00
730	91	18	18	2017-03-27 02:45:00
731	91	18	18	2018-12-12 17:00:00
732	91	18	18	2018-10-06 04:45:00
733	91	18	18	2017-05-22 03:30:00
734	91	18	18	2017-11-17 15:30:00
735	92	13	6	2021-01-18 03:15:00
736	92	13	6	2020-03-03 18:45:00
737	92	13	6	2020-03-24 23:30:00
738	93	14	19	2019-09-17 14:15:00
739	93	14	19	2021-01-26 14:15:00
740	93	14	19	2019-09-26 12:45:00
741	93	14	19	2019-12-14 02:30:00
742	93	14	19	2020-06-02 03:00:00
743	93	14	19	2019-09-04 00:45:00
744	93	14	19	2019-09-27 05:30:00
745	93	14	19	2019-10-15 21:30:00
746	93	14	19	2020-10-24 10:00:00
747	93	14	19	2021-05-21 06:45:00
748	94	5	7	2020-08-11 07:15:00
749	94	5	7	2019-11-25 06:00:00
750	94	5	7	2020-11-04 16:00:00
751	94	5	7	2021-02-20 10:00:00
752	94	5	7	2020-08-11 06:00:00
753	94	5	7	2019-05-05 20:00:00
754	94	5	7	2019-08-24 06:00:00
755	94	5	7	2020-07-23 02:15:00
756	94	5	7	2021-01-04 23:00:00
757	95	9	20	2019-06-06 09:45:00
758	95	9	20	2020-01-03 05:45:00
759	95	9	20	2019-09-11 00:30:00
760	95	9	20	2019-10-06 16:30:00
761	95	9	20	2019-06-11 07:30:00
762	95	9	20	2019-01-10 15:00:00
763	95	9	20	2019-09-25 03:00:00
764	95	9	20	2019-05-15 18:00:00
765	95	9	20	2018-11-24 04:00:00
766	95	9	20	2019-11-05 03:45:00
767	95	9	20	2019-01-22 08:45:00
768	95	9	20	2018-12-07 02:00:00
769	95	9	20	2019-04-10 05:15:00
770	95	9	20	2019-01-11 12:00:00
771	96	19	12	2017-12-12 18:30:00
772	96	19	12	2019-01-13 01:30:00
773	96	19	12	2018-09-19 07:45:00
774	96	19	12	2017-08-02 22:45:00
775	97	10	13	2021-06-30 12:15:00
776	97	10	13	2020-10-22 11:00:00
777	97	10	13	2020-06-03 22:15:00
778	97	10	13	2020-11-15 00:45:00
779	97	10	13	2021-05-11 01:15:00
780	97	10	13	2020-10-16 17:00:00
781	97	10	13	2020-09-07 15:15:00
782	97	10	13	2021-07-07 18:00:00
783	97	10	13	2020-07-30 09:45:00
784	98	17	7	2018-06-01 22:45:00
785	98	17	7	2019-01-24 05:00:00
786	98	17	7	2018-05-25 04:30:00
787	98	17	7	2018-04-26 22:00:00
788	98	17	7	2018-10-20 16:15:00
789	99	16	3	2017-11-04 10:45:00
790	99	16	3	2017-12-04 23:00:00
791	99	16	3	2018-05-24 11:00:00
792	99	16	3	2019-02-27 07:45:00
793	99	16	3	2018-01-02 14:00:00
794	99	16	3	2019-04-15 09:15:00
795	99	16	3	2019-09-04 07:30:00
796	99	16	3	2019-07-20 22:30:00
797	99	16	3	2019-01-08 19:15:00
798	99	16	3	2018-03-25 17:00:00
799	100	2	1	2018-07-21 13:30:00
800	100	2	1	2019-11-17 16:15:00
801	100	2	1	2019-05-03 21:15:00
802	100	2	1	2019-09-11 05:45:00
803	100	2	1	2019-11-16 04:00:00
804	100	2	1	2019-10-21 04:30:00
805	100	2	1	2018-12-28 22:45:00
806	100	2	1	2018-07-04 13:15:00
807	100	2	1	2019-02-27 01:00:00
808	100	2	1	2019-10-14 20:00:00
809	100	2	1	2017-12-23 12:30:00
810	100	2	1	2019-08-09 02:45:00
811	100	2	1	2019-09-21 07:00:00
812	101	13	1	2018-02-24 11:15:00
813	101	13	1	2018-12-03 20:30:00
814	102	10	10	2019-05-30 15:45:00
815	102	10	10	2018-05-15 18:00:00
816	102	10	10	2020-02-01 11:30:00
817	102	10	10	2020-01-26 22:00:00
818	102	10	10	2019-02-02 18:00:00
819	102	10	10	2019-03-13 23:00:00
820	102	10	10	2019-06-17 20:45:00
821	102	10	10	2020-01-17 19:00:00
822	103	7	1	2021-02-19 17:30:00
823	103	7	1	2020-01-11 07:00:00
824	103	7	1	2020-09-24 23:15:00
825	103	7	1	2020-03-07 20:45:00
826	103	7	1	2020-11-15 02:45:00
827	103	7	1	2020-01-15 04:15:00
828	104	14	14	2021-03-12 09:15:00
829	104	14	14	2021-04-13 03:30:00
830	104	14	14	2020-04-29 08:15:00
831	104	14	14	2021-01-24 17:45:00
832	104	14	14	2019-08-01 18:45:00
833	104	14	14	2020-08-04 17:45:00
834	105	7	2	2020-02-27 22:45:00
835	105	7	2	2019-10-13 15:30:00
836	105	7	2	2018-09-19 18:00:00
837	105	7	2	2018-09-03 23:30:00
838	105	7	2	2018-06-05 07:00:00
839	106	8	17	2017-10-20 19:45:00
840	106	8	17	2018-07-10 22:30:00
841	106	8	17	2019-03-27 13:45:00
842	106	8	17	2018-03-09 14:15:00
843	106	8	17	2017-11-18 11:15:00
844	107	5	3	2020-01-15 07:30:00
845	107	5	3	2020-02-02 13:15:00
846	107	5	3	2020-11-17 16:45:00
847	107	5	3	2019-07-24 23:00:00
848	107	5	3	2020-08-27 16:45:00
849	107	5	3	2019-02-06 22:15:00
850	107	5	3	2019-07-06 10:15:00
851	107	5	3	2019-06-24 20:45:00
852	107	5	3	2019-04-24 13:00:00
853	107	5	3	2019-10-02 02:00:00
854	108	20	16	2019-05-10 21:45:00
855	108	20	16	2019-04-27 16:30:00
856	109	13	16	2020-03-16 18:15:00
857	109	13	16	2020-08-10 04:15:00
858	110	17	15	2019-06-22 00:45:00
859	111	12	12	2021-04-08 06:00:00
860	111	12	12	2019-12-26 16:30:00
861	111	12	12	2020-03-22 05:45:00
862	111	12	12	2020-02-21 11:15:00
863	111	12	12	2020-02-04 05:30:00
864	111	12	12	2019-10-27 20:15:00
865	111	12	12	2021-03-28 10:45:00
866	111	12	12	2020-12-14 05:45:00
867	111	12	12	2021-03-15 20:45:00
868	111	12	12	2019-09-28 13:15:00
869	111	12	12	2020-02-06 07:15:00
870	111	12	12	2020-01-28 12:30:00
871	111	12	12	2020-05-29 13:45:00
872	111	12	12	2021-05-02 23:45:00
873	112	18	8	2020-02-07 05:15:00
874	112	18	8	2019-06-28 06:15:00
875	112	18	8	2019-12-10 11:00:00
876	112	18	8	2020-03-15 04:00:00
877	112	18	8	2020-01-10 12:30:00
878	112	18	8	2020-05-22 12:30:00
879	112	18	8	2019-12-26 16:30:00
880	113	2	4	2018-10-22 07:45:00
881	113	2	4	2019-07-03 09:30:00
882	113	2	4	2018-08-01 03:00:00
883	113	2	4	2018-09-16 00:30:00
884	113	2	4	2019-08-07 01:30:00
885	113	2	4	2019-05-20 04:00:00
886	113	2	4	2019-02-03 19:00:00
887	113	2	4	2019-04-06 03:45:00
888	113	2	4	2019-11-27 16:45:00
889	113	2	4	2018-07-03 09:30:00
890	113	2	4	2018-07-30 17:30:00
891	113	2	4	2019-10-22 14:15:00
892	114	5	10	2020-05-03 13:45:00
893	114	5	10	2019-06-06 15:30:00
894	114	5	10	2019-07-08 08:30:00
895	114	5	10	2019-04-12 19:30:00
896	114	5	10	2019-12-28 17:30:00
897	114	5	10	2019-01-22 19:15:00
898	114	5	10	2019-09-24 10:00:00
899	115	6	1	2017-12-13 04:30:00
900	115	6	1	2018-07-26 19:15:00
901	115	6	1	2018-11-11 22:30:00
902	115	6	1	2017-11-20 23:45:00
903	115	6	1	2017-09-10 06:45:00
904	115	6	1	2017-03-28 10:15:00
905	115	6	1	2018-01-07 09:30:00
906	115	6	1	2017-05-04 17:15:00
907	115	6	1	2017-09-01 01:15:00
908	116	4	14	2019-03-04 10:30:00
909	116	4	14	2019-10-02 23:00:00
910	116	4	14	2018-07-13 06:30:00
911	116	4	14	2019-12-21 00:15:00
912	116	4	14	2018-02-03 19:45:00
913	116	4	14	2019-05-21 11:30:00
914	116	4	14	2018-07-07 19:15:00
915	116	4	14	2019-05-10 09:45:00
916	116	4	14	2019-10-05 20:15:00
917	116	4	14	2019-01-11 17:30:00
918	116	4	14	2018-12-27 14:00:00
919	116	4	14	2019-10-26 19:45:00
920	116	4	14	2019-03-12 14:30:00
921	116	4	14	2018-11-20 22:15:00
922	117	7	16	2017-03-22 13:00:00
923	117	7	16	2018-09-26 13:15:00
924	117	7	16	2018-07-02 05:30:00
925	117	7	16	2017-09-06 16:15:00
926	117	7	16	2017-11-16 01:15:00
927	117	7	16	2017-10-15 22:45:00
928	117	7	16	2018-02-25 02:00:00
929	117	7	16	2018-07-14 04:00:00
930	117	7	16	2018-08-10 02:15:00
931	117	7	16	2018-04-14 16:45:00
932	118	2	18	2019-12-23 12:45:00
933	118	2	18	2019-01-01 23:30:00
934	118	2	18	2020-02-19 19:30:00
935	118	2	18	2019-06-01 22:45:00
936	118	2	18	2018-10-10 18:00:00
937	118	2	18	2018-10-20 10:45:00
938	118	2	18	2020-01-17 20:15:00
939	118	2	18	2019-06-23 13:00:00
940	118	2	18	2019-05-12 22:30:00
941	119	14	4	2019-07-11 11:45:00
942	119	14	4	2019-08-01 03:00:00
943	119	14	4	2018-05-29 18:00:00
944	120	3	4	2020-09-18 12:15:00
945	120	3	4	2021-07-08 22:45:00
946	120	3	4	2021-06-25 09:45:00
947	120	3	4	2021-01-19 11:30:00
948	120	3	4	2020-09-05 12:45:00
949	120	3	4	2020-03-04 16:00:00
950	121	1	14	2019-03-13 18:15:00
951	121	1	14	2019-11-17 13:45:00
952	121	1	14	2020-07-24 02:15:00
953	121	1	14	2020-12-08 19:00:00
954	121	1	14	2020-12-13 11:00:00
955	121	1	14	2019-09-08 14:30:00
956	121	1	14	2020-06-29 05:00:00
957	121	1	14	2020-10-21 02:00:00
958	121	1	14	2019-08-16 07:30:00
959	121	1	14	2020-04-25 01:45:00
960	121	1	14	2020-06-08 00:30:00
961	121	1	14	2019-09-13 23:00:00
962	122	7	13	2019-08-25 00:15:00
963	122	7	13	2019-05-30 20:00:00
964	122	7	13	2020-02-11 15:30:00
965	122	7	13	2019-09-09 14:00:00
966	122	7	13	2019-08-10 02:45:00
967	122	7	13	2018-10-07 04:30:00
968	122	7	13	2020-04-04 21:15:00
969	122	7	13	2019-06-21 13:30:00
970	122	7	13	2020-04-29 04:15:00
971	122	7	13	2019-10-02 14:45:00
972	122	7	13	2019-09-03 20:30:00
973	122	7	13	2018-11-20 08:45:00
974	122	7	13	2018-08-28 20:00:00
975	122	7	13	2018-12-04 08:15:00
976	123	16	4	2017-12-14 02:00:00
977	123	16	4	2018-03-17 14:30:00
978	123	16	4	2018-04-22 09:00:00
979	123	16	4	2019-06-24 02:15:00
980	123	16	4	2018-01-05 05:00:00
981	123	16	4	2018-12-30 21:45:00
982	123	16	4	2017-08-22 10:15:00
983	123	16	4	2018-06-04 17:15:00
984	123	16	4	2017-09-16 11:15:00
985	123	16	4	2017-09-16 09:30:00
986	123	16	4	2018-04-11 10:15:00
987	124	17	18	2019-06-03 20:00:00
988	124	17	18	2018-10-19 14:00:00
989	124	17	18	2020-01-13 04:00:00
990	124	17	18	2019-08-23 22:15:00
991	124	17	18	2019-06-25 21:30:00
992	124	17	18	2020-01-17 09:45:00
993	124	17	18	2020-02-11 02:00:00
994	125	5	12	2020-08-18 10:30:00
995	125	5	12	2020-04-11 05:00:00
996	125	5	12	2019-08-23 20:00:00
997	125	5	12	2019-07-08 23:00:00
998	125	5	12	2018-09-12 12:15:00
999	125	5	12	2019-06-04 08:00:00
1000	125	5	12	2020-04-01 22:45:00
1001	125	5	12	2019-12-25 03:00:00
1002	125	5	12	2019-10-18 23:45:00
1003	125	5	12	2019-12-03 04:15:00
1004	125	5	12	2019-05-24 01:15:00
1005	126	4	4	2019-05-24 19:30:00
1006	126	4	4	2020-02-17 05:30:00
1007	126	4	4	2020-12-12 09:45:00
1008	126	4	4	2020-09-17 22:45:00
1009	126	4	4	2019-05-19 20:45:00
1010	126	4	4	2020-06-07 13:15:00
1011	126	4	4	2019-05-16 02:30:00
1012	126	4	4	2019-11-07 17:00:00
1013	126	4	4	2020-01-30 02:45:00
1014	127	10	9	2019-02-17 17:30:00
1015	127	10	9	2018-12-20 16:00:00
1016	127	10	9	2018-08-14 15:15:00
1017	127	10	9	2019-02-10 01:15:00
1018	127	10	9	2018-08-12 14:30:00
1019	127	10	9	2018-08-19 06:00:00
1020	127	10	9	2019-07-20 21:30:00
1021	127	10	9	2018-05-26 20:15:00
1022	127	10	9	2018-11-28 02:45:00
1023	127	10	9	2018-06-30 13:15:00
1024	127	10	9	2017-11-11 10:30:00
1025	127	10	9	2018-06-11 17:30:00
1026	127	10	9	2018-05-23 19:00:00
1027	128	20	3	2019-08-13 07:30:00
1028	128	20	3	2019-07-29 00:15:00
1029	128	20	3	2018-02-07 05:30:00
1030	129	10	5	2018-06-21 12:30:00
1031	129	10	5	2019-05-20 03:30:00
1032	129	10	5	2017-10-17 08:00:00
1033	129	10	5	2018-05-07 20:45:00
1034	129	10	5	2019-03-25 10:00:00
1035	129	10	5	2017-07-11 02:15:00
1036	129	10	5	2019-04-04 18:30:00
1037	129	10	5	2019-02-27 06:30:00
1038	129	10	5	2018-12-17 08:45:00
1039	130	1	9	2019-07-19 21:45:00
1040	130	1	9	2020-06-30 07:00:00
1041	130	1	9	2019-06-07 08:30:00
1042	130	1	9	2019-10-13 08:45:00
1043	130	1	9	2019-06-25 01:30:00
1044	130	1	9	2021-01-27 15:30:00
1045	130	1	9	2019-12-03 17:30:00
1046	130	1	9	2020-12-30 09:30:00
1047	130	1	9	2019-07-07 13:15:00
1048	130	1	9	2020-04-06 21:00:00
1049	130	1	9	2020-10-15 14:15:00
1050	130	1	9	2020-09-03 08:45:00
1051	131	1	10	2017-12-06 11:00:00
1052	131	1	10	2017-09-15 09:15:00
1053	131	1	10	2019-03-23 22:30:00
1054	131	1	10	2017-06-20 01:00:00
1055	132	15	1	2021-12-20 07:30:00
1056	132	15	1	2021-10-04 17:00:00
1057	132	15	1	2020-05-10 23:45:00
1058	132	15	1	2021-11-10 13:30:00
1059	132	15	1	2021-09-25 12:15:00
1060	132	15	1	2020-04-14 14:45:00
1061	132	15	1	2020-04-21 11:30:00
1062	133	13	20	2019-06-12 03:30:00
1063	133	13	20	2019-05-30 13:30:00
1064	133	13	20	2019-04-08 14:30:00
1065	133	13	20	2020-01-19 19:00:00
1066	133	13	20	2019-07-17 08:15:00
1067	133	13	20	2020-09-30 13:00:00
1068	134	8	15	2019-07-17 18:30:00
1069	134	8	15	2018-11-20 05:30:00
1070	134	8	15	2019-08-29 17:00:00
1071	134	8	15	2019-07-03 14:15:00
1072	134	8	15	2018-12-10 05:45:00
1073	134	8	15	2018-09-21 12:30:00
1074	134	8	15	2018-06-03 23:30:00
1075	134	8	15	2018-11-18 18:15:00
1076	135	15	11	2017-09-12 17:00:00
1077	135	15	11	2018-01-19 10:30:00
1078	136	17	13	2019-02-02 22:30:00
1079	136	17	13	2018-06-10 19:30:00
1080	136	17	13	2018-07-12 04:00:00
1081	136	17	13	2017-06-13 00:00:00
1082	136	17	13	2019-02-10 14:45:00
1083	136	17	13	2018-12-26 18:45:00
1084	136	17	13	2017-07-08 18:15:00
1085	136	17	13	2017-09-21 03:15:00
1086	136	17	13	2017-08-30 20:45:00
1087	136	17	13	2018-11-09 20:45:00
1088	136	17	13	2018-03-30 15:15:00
1089	137	10	9	2020-11-30 21:30:00
1090	137	10	9	2020-03-16 12:30:00
1091	137	10	9	2020-11-28 14:00:00
1092	137	10	9	2019-10-10 06:30:00
1093	137	10	9	2019-04-26 08:45:00
1094	137	10	9	2019-06-08 15:00:00
1095	137	10	9	2020-03-03 06:00:00
1096	138	5	2	2019-09-12 09:00:00
1097	138	5	2	2019-10-24 09:30:00
1098	138	5	2	2020-03-13 13:45:00
1099	138	5	2	2019-11-16 06:30:00
1100	138	5	2	2019-09-26 20:00:00
1101	138	5	2	2019-12-08 22:15:00
1102	138	5	2	2020-02-22 21:00:00
1103	139	12	16	2020-09-01 00:00:00
1104	140	11	2	2020-08-13 13:00:00
1105	140	11	2	2020-03-04 13:45:00
1106	140	11	2	2019-02-20 00:00:00
1107	140	11	2	2020-02-11 05:45:00
1108	140	11	2	2019-11-30 17:30:00
1109	140	11	2	2019-12-25 01:45:00
1110	140	11	2	2019-04-25 05:00:00
1111	140	11	2	2020-07-04 23:30:00
1112	140	11	2	2020-11-04 21:45:00
1113	141	16	4	2019-03-16 06:45:00
1114	141	16	4	2019-02-17 19:30:00
1115	141	16	4	2018-11-13 17:00:00
1116	142	1	1	2018-07-17 05:00:00
1117	142	1	1	2017-12-29 21:00:00
1118	142	1	1	2017-10-25 04:45:00
1119	142	1	1	2019-08-09 17:00:00
1120	143	7	10	2019-10-03 21:45:00
1121	143	7	10	2020-03-22 14:15:00
1122	143	7	10	2019-10-15 08:30:00
1123	143	7	10	2020-03-16 16:30:00
1124	143	7	10	2020-01-09 13:15:00
1125	143	7	10	2019-12-16 05:15:00
1126	143	7	10	2020-09-22 07:15:00
1127	143	7	10	2021-01-29 13:45:00
1128	143	7	10	2020-03-04 23:15:00
1129	144	10	20	2020-11-27 13:30:00
1130	144	10	20	2021-06-13 10:30:00
1131	144	10	20	2021-01-29 20:15:00
1132	144	10	20	2021-10-12 00:45:00
1133	144	10	20	2021-08-29 16:30:00
1134	144	10	20	2020-03-20 23:00:00
1135	144	10	20	2020-11-04 00:15:00
1136	144	10	20	2020-04-09 00:45:00
1137	144	10	20	2020-06-09 10:00:00
1138	144	10	20	2021-05-03 00:15:00
1139	144	10	20	2021-01-29 22:30:00
1140	144	10	20	2021-08-26 02:30:00
1141	145	6	2	2021-09-09 03:45:00
1142	145	6	2	2020-04-04 20:15:00
1143	145	6	2	2021-05-06 18:15:00
1144	145	6	2	2020-08-07 23:15:00
1145	146	1	2	2019-05-18 11:15:00
1146	146	1	2	2018-06-08 17:30:00
1147	146	1	2	2019-02-19 03:30:00
1148	146	1	2	2018-11-20 18:30:00
1149	146	1	2	2017-07-15 12:45:00
1150	146	1	2	2019-04-07 20:45:00
1151	146	1	2	2018-02-20 02:30:00
1152	146	1	2	2018-03-07 15:30:00
1153	146	1	2	2017-09-27 10:45:00
1154	146	1	2	2018-12-27 01:00:00
1155	147	4	2	2019-05-07 05:45:00
1156	147	4	2	2019-08-08 07:30:00
1157	147	4	2	2019-08-16 04:00:00
1158	147	4	2	2020-02-05 20:30:00
1159	147	4	2	2020-02-07 02:30:00
1160	147	4	2	2020-01-18 15:00:00
1161	147	4	2	2019-11-08 20:30:00
1162	147	4	2	2019-08-08 19:45:00
1163	148	19	18	2020-09-02 05:00:00
1164	148	19	18	2020-06-26 16:30:00
1165	148	19	18	2019-06-25 18:00:00
1166	148	19	18	2020-08-27 18:30:00
1167	148	19	18	2019-05-03 01:00:00
1168	148	19	18	2020-04-10 15:45:00
1169	148	19	18	2021-04-19 01:15:00
1170	149	5	19	2020-04-27 16:15:00
1171	149	5	19	2021-02-14 18:15:00
1172	149	5	19	2020-11-10 03:30:00
1173	149	5	19	2019-08-01 11:30:00
1174	149	5	19	2020-08-03 20:30:00
1175	149	5	19	2021-01-07 03:15:00
1176	149	5	19	2020-10-29 01:15:00
1177	149	5	19	2020-09-21 14:30:00
1178	149	5	19	2019-10-03 21:30:00
1179	150	16	19	2019-11-20 22:00:00
1180	150	16	19	2019-03-19 04:30:00
1181	150	16	19	2020-04-10 16:15:00
1182	150	16	19	2019-07-23 00:45:00
1183	150	16	19	2019-10-21 12:15:00
1184	150	16	19	2018-10-06 18:30:00
1185	150	16	19	2019-06-05 01:45:00
1186	150	16	19	2020-02-07 13:00:00
1187	151	16	16	2018-12-27 06:30:00
1188	151	16	16	2019-08-14 14:00:00
1189	151	16	16	2018-01-02 20:15:00
1190	151	16	16	2018-10-19 23:00:00
1191	151	16	16	2018-09-30 11:45:00
1192	151	16	16	2018-06-13 03:15:00
1193	151	16	16	2019-01-25 08:45:00
1194	151	16	16	2019-04-23 17:30:00
1195	151	16	16	2018-02-27 02:00:00
1196	151	16	16	2019-05-16 08:00:00
1197	151	16	16	2018-09-13 00:30:00
1198	152	2	15	2019-08-13 10:45:00
1199	152	2	15	2018-08-24 08:30:00
1200	152	2	15	2019-12-25 21:00:00
1201	152	2	15	2018-09-14 17:30:00
1202	152	2	15	2018-05-26 17:00:00
1203	153	14	11	2020-07-06 04:30:00
1204	153	14	11	2020-08-11 06:30:00
1205	153	14	11	2019-05-10 15:00:00
1206	153	14	11	2020-08-02 03:00:00
1207	153	14	11	2020-08-03 14:45:00
1208	153	14	11	2019-07-12 04:15:00
1209	153	14	11	2019-08-20 23:45:00
1210	153	14	11	2019-09-20 10:45:00
1211	154	2	5	2019-09-10 19:45:00
1212	154	2	5	2020-06-14 21:30:00
1213	154	2	5	2019-12-14 15:30:00
1214	154	2	5	2019-11-05 21:45:00
1215	154	2	5	2019-11-18 13:15:00
1216	154	2	5	2019-06-28 14:45:00
1217	154	2	5	2019-04-01 23:30:00
1218	154	2	5	2020-10-18 03:30:00
1219	154	2	5	2019-03-20 02:45:00
1220	154	2	5	2020-04-24 20:00:00
1221	154	2	5	2019-11-21 19:30:00
1222	154	2	5	2019-03-18 05:30:00
1223	154	2	5	2019-02-10 08:00:00
1224	155	8	3	2020-07-13 15:00:00
1225	155	8	3	2020-02-02 12:30:00
1226	155	8	3	2021-02-23 18:45:00
1227	155	8	3	2019-10-05 13:30:00
1228	155	8	3	2020-09-05 11:15:00
1229	155	8	3	2020-05-28 13:00:00
1230	155	8	3	2020-05-01 15:00:00
1231	155	8	3	2019-08-23 13:15:00
1232	155	8	3	2019-07-04 04:00:00
1233	156	7	15	2019-06-08 11:30:00
1234	156	7	15	2020-01-11 22:30:00
1235	156	7	15	2020-05-24 14:00:00
1236	157	19	6	2020-06-07 22:15:00
1237	157	19	6	2021-05-18 10:45:00
1238	157	19	6	2020-01-15 09:00:00
1239	157	19	6	2020-12-19 06:45:00
1240	157	19	6	2021-07-29 01:45:00
1241	157	19	6	2019-12-11 19:30:00
1242	157	19	6	2020-08-25 16:00:00
1243	157	19	6	2021-07-24 15:15:00
1244	158	11	15	2021-07-01 16:30:00
1245	158	11	15	2020-01-13 18:15:00
1246	158	11	15	2021-02-25 14:45:00
1247	158	11	15	2020-03-24 08:15:00
1248	158	11	15	2020-10-12 19:15:00
1249	158	11	15	2020-10-07 13:00:00
1250	158	11	15	2021-01-15 13:30:00
1251	158	11	15	2021-05-19 21:00:00
1252	158	11	15	2020-05-02 00:00:00
1253	158	11	15	2021-09-30 04:45:00
1254	158	11	15	2020-12-12 17:45:00
1255	158	11	15	2021-10-30 20:30:00
1256	159	13	12	2018-11-25 16:30:00
1257	159	13	12	2018-05-09 22:45:00
1258	160	8	19	2019-04-16 01:45:00
1259	160	8	19	2018-12-11 15:30:00
1260	160	8	19	2019-03-17 21:30:00
1261	160	8	19	2017-07-12 05:45:00
1262	160	8	19	2018-03-02 04:00:00
1263	160	8	19	2018-09-08 01:15:00
1264	160	8	19	2017-12-15 23:45:00
1265	160	8	19	2018-06-10 08:15:00
1266	160	8	19	2018-08-17 03:00:00
1267	161	10	19	2019-09-15 19:30:00
1268	161	10	19	2019-04-13 04:45:00
1269	161	10	19	2019-07-09 23:15:00
1270	161	10	19	2020-03-24 00:15:00
1271	162	8	6	2017-10-08 17:00:00
1272	162	8	6	2017-09-03 00:15:00
1273	162	8	6	2018-04-10 05:45:00
1274	162	8	6	2019-02-12 15:00:00
1275	163	16	18	2019-08-30 15:45:00
1276	163	16	18	2020-02-22 18:15:00
1277	163	16	18	2019-11-15 14:45:00
1278	163	16	18	2020-03-24 23:15:00
1279	163	16	18	2020-01-17 21:45:00
1280	163	16	18	2020-04-09 10:30:00
1281	163	16	18	2021-02-24 07:30:00
1282	163	16	18	2019-11-13 08:15:00
1283	163	16	18	2020-01-03 08:30:00
1284	163	16	18	2021-04-02 05:15:00
1285	163	16	18	2019-11-14 18:00:00
1286	164	4	6	2020-04-21 10:30:00
1287	164	4	6	2020-12-03 05:45:00
1288	164	4	6	2019-08-22 04:30:00
1289	164	4	6	2020-08-09 11:15:00
1290	164	4	6	2019-12-22 10:30:00
1291	164	4	6	2019-09-02 18:15:00
1292	164	4	6	2021-02-01 14:15:00
1293	164	4	6	2019-09-04 16:00:00
1294	164	4	6	2021-02-15 22:30:00
1295	165	10	6	2018-01-19 14:30:00
1296	165	10	6	2018-11-09 16:00:00
1297	166	7	10	2019-09-05 12:15:00
1298	166	7	10	2018-09-20 05:45:00
1299	166	7	10	2018-12-25 13:30:00
1300	166	7	10	2019-01-25 07:45:00
1301	166	7	10	2018-12-30 09:45:00
1302	166	7	10	2020-01-16 08:15:00
1303	166	7	10	2019-01-23 00:30:00
1304	166	7	10	2018-07-19 11:15:00
1305	166	7	10	2018-10-06 10:30:00
1306	166	7	10	2019-03-20 15:30:00
1307	167	14	3	2017-12-05 22:15:00
1308	167	14	3	2018-02-21 18:30:00
1309	168	19	18	2018-04-26 07:00:00
1310	168	19	18	2019-01-29 17:00:00
1311	168	19	18	2018-12-26 10:00:00
1312	168	19	18	2017-12-27 20:30:00
1313	168	19	18	2018-01-18 02:15:00
1314	168	19	18	2017-03-16 07:00:00
1315	168	19	18	2018-01-06 09:15:00
1316	168	19	18	2017-10-21 15:00:00
1317	168	19	18	2018-06-03 08:45:00
1318	168	19	18	2018-10-08 11:00:00
1319	168	19	18	2017-11-12 12:00:00
1320	168	19	18	2017-06-05 12:15:00
1321	168	19	18	2018-12-08 02:45:00
1322	169	10	20	2020-11-05 08:45:00
1323	169	10	20	2021-04-30 00:45:00
1324	169	10	20	2019-12-20 02:30:00
1325	169	10	20	2019-10-04 08:45:00
1326	169	10	20	2019-12-06 03:45:00
1327	169	10	20	2021-04-21 01:15:00
1328	169	10	20	2020-03-29 03:30:00
1329	169	10	20	2020-08-08 17:45:00
1330	169	10	20	2020-01-04 20:00:00
1331	169	10	20	2020-12-11 07:30:00
1332	169	10	20	2020-09-07 13:30:00
1333	169	10	20	2020-04-30 19:30:00
1334	169	10	20	2020-04-09 02:15:00
1335	169	10	20	2021-07-29 16:30:00
1336	169	10	20	2020-03-06 22:45:00
1337	170	4	8	2019-04-27 10:45:00
1338	170	4	8	2019-08-02 10:15:00
1339	171	4	14	2021-11-09 18:15:00
1340	171	4	14	2021-03-27 13:45:00
1341	171	4	14	2021-07-04 21:30:00
1342	171	4	14	2020-08-15 06:30:00
1343	172	6	1	2020-06-14 03:15:00
1344	172	6	1	2021-02-02 16:15:00
1345	172	6	1	2020-11-20 09:30:00
1346	172	6	1	2019-11-08 21:15:00
1347	172	6	1	2020-04-17 04:45:00
1348	172	6	1	2020-02-19 16:15:00
1349	172	6	1	2020-06-22 07:00:00
1350	172	6	1	2020-06-22 21:45:00
1351	172	6	1	2019-04-23 04:15:00
1352	173	14	20	2020-09-12 02:45:00
1353	173	14	20	2019-08-09 02:45:00
1354	173	14	20	2019-10-28 07:00:00
1355	173	14	20	2019-06-16 04:15:00
1356	173	14	20	2020-11-08 14:30:00
1357	174	5	18	2019-06-11 07:00:00
1358	174	5	18	2018-02-13 00:30:00
1359	174	5	18	2018-08-09 18:30:00
1360	174	5	18	2018-05-13 06:45:00
1361	174	5	18	2019-08-25 11:30:00
1362	174	5	18	2019-04-14 05:45:00
1363	174	5	18	2019-01-17 05:00:00
1364	174	5	18	2018-03-17 19:00:00
1365	174	5	18	2019-06-03 21:15:00
1366	174	5	18	2019-03-30 10:30:00
1367	175	11	16	2019-03-20 10:45:00
1368	175	11	16	2019-05-14 23:00:00
1369	175	11	16	2019-01-08 20:15:00
1370	175	11	16	2018-06-15 14:00:00
1371	176	12	8	2018-09-26 17:00:00
1372	176	12	8	2020-04-08 00:45:00
1373	176	12	8	2018-11-02 02:30:00
1374	176	12	8	2020-02-24 13:30:00
1375	176	12	8	2019-02-02 00:45:00
1376	176	12	8	2018-10-21 22:15:00
1377	176	12	8	2019-01-20 09:00:00
1378	176	12	8	2019-12-24 02:15:00
1379	176	12	8	2019-07-11 14:00:00
1380	176	12	8	2018-06-18 07:15:00
1381	176	12	8	2018-07-13 02:15:00
1382	176	12	8	2020-01-23 04:15:00
1383	176	12	8	2018-06-14 18:00:00
1384	177	19	13	2019-02-09 18:00:00
1385	177	19	13	2020-05-09 09:30:00
1386	177	19	13	2019-11-05 14:45:00
1387	177	19	13	2020-08-01 19:45:00
1388	177	19	13	2019-03-22 21:00:00
1389	178	18	16	2019-10-19 15:15:00
1390	178	18	16	2020-10-06 22:45:00
1391	178	18	16	2021-02-13 00:30:00
1392	178	18	16	2020-01-03 20:45:00
1393	178	18	16	2019-11-21 08:45:00
1394	178	18	16	2020-11-16 18:00:00
1395	178	18	16	2020-11-15 22:30:00
1396	178	18	16	2019-05-06 14:15:00
1397	178	18	16	2020-03-06 10:30:00
1398	178	18	16	2019-08-08 07:15:00
1399	178	18	16	2019-04-23 17:15:00
1400	179	8	7	2019-08-17 23:30:00
1401	179	8	7	2018-12-12 17:45:00
1402	179	8	7	2020-10-19 13:30:00
1403	179	8	7	2019-09-19 06:15:00
1404	179	8	7	2020-08-01 07:15:00
1405	179	8	7	2020-03-26 22:15:00
1406	179	8	7	2019-11-30 15:15:00
1407	179	8	7	2019-04-01 09:30:00
1408	179	8	7	2020-05-10 19:15:00
1409	179	8	7	2020-09-12 08:15:00
1410	180	12	15	2019-03-15 21:45:00
1411	180	12	15	2018-08-09 22:45:00
1412	180	12	15	2019-02-04 19:30:00
1413	180	12	15	2019-02-12 19:00:00
1414	180	12	15	2019-08-25 08:45:00
1415	180	12	15	2018-06-27 09:30:00
1416	180	12	15	2018-05-08 00:00:00
1417	180	12	15	2019-01-20 00:15:00
1418	180	12	15	2019-04-07 14:15:00
1419	180	12	15	2018-10-11 16:00:00
1420	180	12	15	2019-04-12 09:45:00
1421	180	12	15	2019-04-08 12:45:00
1422	180	12	15	2020-03-12 14:30:00
1423	180	12	15	2020-01-05 05:00:00
1424	180	12	15	2019-07-03 12:15:00
1425	181	4	7	2019-08-11 17:30:00
1426	181	4	7	2019-08-11 05:30:00
1427	181	4	7	2020-04-11 15:45:00
1428	181	4	7	2019-10-17 15:00:00
1429	181	4	7	2020-03-28 20:45:00
1430	181	4	7	2019-03-30 14:45:00
1431	181	4	7	2020-04-28 16:30:00
1432	181	4	7	2019-03-19 05:30:00
1433	181	4	7	2019-12-03 05:45:00
1434	181	4	7	2020-05-03 06:30:00
1435	181	4	7	2019-02-10 05:15:00
1436	181	4	7	2019-11-23 05:30:00
1437	182	6	20	2020-07-05 09:15:00
1438	182	6	20	2020-02-23 01:30:00
1439	182	6	20	2020-04-10 13:00:00
1440	182	6	20	2020-09-04 13:30:00
1441	182	6	20	2019-03-30 19:00:00
1442	182	6	20	2020-01-15 06:15:00
1443	183	15	6	2020-04-17 08:45:00
1444	183	15	6	2020-03-04 21:00:00
1445	183	15	6	2019-11-29 04:15:00
1446	183	15	6	2019-12-11 06:00:00
1447	183	15	6	2020-09-17 08:45:00
1448	183	15	6	2019-12-05 19:00:00
1449	183	15	6	2020-02-04 18:15:00
1450	183	15	6	2020-06-12 07:15:00
1451	183	15	6	2021-08-15 17:30:00
1452	184	14	5	2019-06-02 13:30:00
1453	184	14	5	2019-11-04 20:00:00
1454	184	14	5	2019-02-08 00:30:00
1455	184	14	5	2019-10-30 17:00:00
1456	184	14	5	2019-01-05 04:15:00
1457	184	14	5	2020-01-26 10:00:00
1458	184	14	5	2020-07-23 11:30:00
1459	184	14	5	2019-11-14 10:00:00
1460	184	14	5	2019-12-22 01:00:00
1461	184	14	5	2020-03-15 21:00:00
1462	184	14	5	2020-08-10 20:30:00
1463	184	14	5	2020-09-16 15:15:00
1464	184	14	5	2020-06-08 23:45:00
1465	185	15	9	2018-12-02 05:00:00
1466	185	15	9	2017-03-13 15:15:00
1467	185	15	9	2018-10-24 19:15:00
1468	185	15	9	2018-03-06 20:00:00
1469	185	15	9	2019-01-14 09:00:00
1470	185	15	9	2018-12-27 05:30:00
1471	185	15	9	2019-01-15 01:00:00
1472	185	15	9	2017-09-27 10:00:00
1473	186	9	16	2020-01-04 09:15:00
1474	186	9	16	2018-08-14 18:45:00
1475	186	9	16	2018-11-12 02:15:00
1476	186	9	16	2019-09-17 04:30:00
1477	186	9	16	2019-10-18 08:45:00
1478	186	9	16	2018-04-26 13:30:00
1479	186	9	16	2019-12-19 10:15:00
1480	186	9	16	2019-01-15 01:15:00
1481	186	9	16	2019-06-13 00:30:00
1482	186	9	16	2018-02-12 01:45:00
1483	187	20	2	2019-02-02 15:15:00
1484	187	20	2	2017-12-24 12:15:00
1485	187	20	2	2019-01-28 00:00:00
1486	187	20	2	2018-01-16 09:45:00
1487	187	20	2	2018-02-17 01:45:00
1488	187	20	2	2018-07-23 13:15:00
1489	187	20	2	2019-01-15 16:45:00
1490	187	20	2	2019-02-02 06:30:00
1491	187	20	2	2017-07-14 17:45:00
1492	187	20	2	2019-04-30 01:15:00
1493	187	20	2	2018-08-16 06:45:00
1494	187	20	2	2017-12-20 22:15:00
1495	187	20	2	2019-01-30 13:45:00
1496	187	20	2	2019-05-17 15:30:00
1497	187	20	2	2019-01-15 09:45:00
1498	188	10	10	2018-07-29 00:30:00
1499	188	10	10	2018-02-21 22:00:00
1500	188	10	10	2018-07-14 18:30:00
1501	188	10	10	2018-10-27 21:00:00
1502	188	10	10	2019-04-16 06:45:00
1503	188	10	10	2018-06-19 23:30:00
1504	189	3	2	2018-08-25 06:45:00
1505	189	3	2	2019-12-13 10:15:00
1506	189	3	2	2018-06-08 08:00:00
1507	189	3	2	2020-03-11 12:00:00
1508	189	3	2	2019-12-10 04:30:00
1509	189	3	2	2019-09-09 17:45:00
1510	189	3	2	2018-10-17 17:15:00
1511	189	3	2	2019-08-25 09:45:00
1512	189	3	2	2020-02-10 04:45:00
1513	190	5	17	2019-11-17 00:00:00
1514	190	5	17	2019-12-05 19:15:00
1515	190	5	17	2020-04-13 15:00:00
1516	190	5	17	2020-02-27 18:00:00
1517	190	5	17	2020-04-29 01:45:00
1518	190	5	17	2019-12-03 14:00:00
1519	190	5	17	2019-10-20 01:00:00
1520	190	5	17	2019-08-06 14:30:00
1521	190	5	17	2018-11-20 12:00:00
1522	190	5	17	2019-06-04 00:45:00
1523	190	5	17	2019-03-04 04:30:00
1524	190	5	17	2020-04-03 09:15:00
1525	190	5	17	2020-04-19 12:00:00
1526	191	2	7	2019-12-02 02:45:00
1527	191	2	7	2018-08-04 01:15:00
1528	191	2	7	2019-08-19 10:15:00
1529	191	2	7	2019-07-08 21:45:00
1530	191	2	7	2020-02-17 23:45:00
1531	192	8	10	2018-11-24 19:30:00
1532	193	20	18	2020-06-06 23:30:00
1533	193	20	18	2021-06-06 15:15:00
1534	194	4	1	2020-08-26 03:30:00
1535	195	12	10	2019-07-20 18:15:00
1536	195	12	10	2019-05-26 01:00:00
1537	195	12	10	2019-03-28 11:00:00
1538	195	12	10	2019-10-27 08:30:00
1539	195	12	10	2020-06-10 06:00:00
1540	195	12	10	2019-03-20 22:45:00
1541	195	12	10	2020-08-30 14:45:00
1542	195	12	10	2020-07-08 07:00:00
1543	196	13	16	2020-02-13 08:30:00
1544	196	13	16	2019-02-04 08:00:00
1545	196	13	16	2018-09-20 02:30:00
1546	196	13	16	2019-05-03 20:15:00
1547	196	13	16	2019-09-29 16:30:00
1548	196	13	16	2018-10-25 22:45:00
1549	196	13	16	2019-07-20 15:30:00
1550	196	13	16	2020-01-11 11:15:00
1551	196	13	16	2020-01-29 23:15:00
1552	196	13	16	2019-07-09 19:15:00
1553	196	13	16	2018-09-22 22:00:00
1554	196	13	16	2019-04-03 22:45:00
1555	196	13	16	2018-05-07 13:45:00
1556	197	6	4	2021-01-12 20:30:00
1557	197	6	4	2020-11-23 22:30:00
1558	197	6	4	2021-02-05 11:00:00
1559	197	6	4	2019-07-14 00:45:00
1560	197	6	4	2021-02-13 11:15:00
1561	197	6	4	2020-10-06 02:45:00
1562	197	6	4	2020-03-06 04:00:00
1563	197	6	4	2020-11-28 00:00:00
1564	197	6	4	2020-02-11 15:45:00
1565	198	9	14	2018-07-28 18:45:00
1566	198	9	14	2020-01-20 21:00:00
1567	198	9	14	2019-02-24 20:30:00
1568	198	9	14	2020-02-02 04:30:00
1569	198	9	14	2019-04-16 18:30:00
1570	199	4	12	2020-09-08 23:00:00
1571	199	4	12	2020-11-23 08:15:00
1572	199	4	12	2020-09-12 01:15:00
1573	199	4	12	2021-03-27 17:00:00
1574	199	4	12	2020-11-05 17:00:00
1575	199	4	12	2020-12-23 15:45:00
1576	200	16	20	2020-05-16 06:00:00
1577	200	16	20	2020-11-28 13:15:00
1578	200	16	20	2019-05-06 23:30:00
1579	200	16	20	2019-10-04 03:30:00
1580	200	16	20	2019-06-24 12:00:00
1581	201	4	13	2019-09-14 15:30:00
1582	201	4	13	2020-05-09 06:00:00
1583	202	17	20	2019-11-03 21:45:00
1584	202	17	20	2020-08-06 17:45:00
1585	202	17	20	2020-06-23 16:30:00
1586	202	17	20	2020-07-25 08:45:00
1587	202	17	20	2020-01-18 18:00:00
1588	202	17	20	2020-09-17 01:00:00
1589	202	17	20	2020-07-02 04:30:00
1590	202	17	20	2020-02-13 22:15:00
1591	202	17	20	2020-11-08 22:30:00
1592	202	17	20	2019-04-09 16:30:00
1593	202	17	20	2019-11-22 08:00:00
1594	202	17	20	2019-02-24 07:15:00
1595	202	17	20	2019-12-15 04:00:00
1596	202	17	20	2020-04-21 09:45:00
1597	203	12	11	2019-08-15 14:45:00
1598	203	12	11	2019-01-13 00:15:00
1599	203	12	11	2019-12-17 07:30:00
1600	203	12	11	2019-10-11 18:00:00
1601	203	12	11	2019-04-30 19:30:00
1602	203	12	11	2019-02-01 01:00:00
1603	203	12	11	2019-02-13 14:15:00
1604	204	11	8	2019-08-19 04:45:00
1605	204	11	8	2020-01-04 11:45:00
1606	204	11	8	2020-07-09 17:00:00
1607	204	11	8	2020-10-19 14:45:00
1608	204	11	8	2020-09-30 13:45:00
1609	204	11	8	2019-11-23 19:15:00
1610	204	11	8	2020-05-30 17:45:00
1611	204	11	8	2019-06-25 04:30:00
1612	204	11	8	2020-06-08 01:45:00
1613	204	11	8	2020-08-02 15:30:00
1614	204	11	8	2019-05-22 11:00:00
1615	204	11	8	2019-08-21 13:30:00
1616	204	11	8	2019-12-10 14:45:00
1617	204	11	8	2020-01-19 07:00:00
1618	205	5	19	2017-12-14 10:00:00
1619	205	5	19	2018-06-19 03:45:00
1620	205	5	19	2018-09-12 09:45:00
1621	205	5	19	2019-03-19 23:30:00
1622	205	5	19	2018-08-17 22:45:00
1623	205	5	19	2018-07-11 15:30:00
1624	205	5	19	2018-06-21 21:15:00
1625	205	5	19	2018-07-06 10:00:00
1626	205	5	19	2018-04-15 21:30:00
1627	206	20	8	2020-12-28 09:15:00
1628	206	20	8	2020-03-30 06:45:00
1629	206	20	8	2021-02-13 05:00:00
1630	206	20	8	2021-03-01 17:30:00
1631	206	20	8	2021-02-03 01:45:00
1632	206	20	8	2019-10-02 14:00:00
1633	206	20	8	2020-04-11 15:45:00
1634	206	20	8	2020-03-06 21:00:00
1635	207	18	18	2020-06-16 18:30:00
1636	207	18	18	2019-08-08 06:45:00
1637	207	18	18	2019-08-13 02:30:00
1638	207	18	18	2020-11-16 04:30:00
1639	207	18	18	2020-03-15 19:45:00
1640	207	18	18	2020-12-19 00:00:00
1641	207	18	18	2020-04-05 05:00:00
1642	207	18	18	2019-07-30 10:15:00
1643	207	18	18	2020-08-15 01:00:00
1644	207	18	18	2019-09-22 12:00:00
1645	207	18	18	2019-11-18 00:30:00
1646	207	18	18	2020-01-01 19:30:00
1647	207	18	18	2020-07-13 06:15:00
1648	208	17	11	2020-03-10 21:45:00
1649	208	17	11	2020-09-29 18:30:00
1650	208	17	11	2019-12-27 08:30:00
1651	208	17	11	2020-06-09 03:45:00
1652	209	16	17	2019-07-12 21:00:00
1653	209	16	17	2018-08-04 11:30:00
1654	210	20	7	2018-11-02 01:45:00
1655	210	20	7	2017-03-01 12:00:00
1656	210	20	7	2019-01-24 04:45:00
1657	210	20	7	2018-05-15 17:00:00
1658	210	20	7	2017-07-05 14:30:00
1659	210	20	7	2018-02-11 06:30:00
1660	210	20	7	2018-08-10 15:30:00
1661	210	20	7	2017-10-19 22:15:00
1662	210	20	7	2018-02-24 14:30:00
1663	210	20	7	2018-04-15 04:45:00
1664	210	20	7	2018-03-07 08:45:00
1665	210	20	7	2018-01-02 15:30:00
1666	210	20	7	2017-10-25 03:45:00
1667	211	17	18	2018-08-29 03:00:00
1668	211	17	18	2018-12-26 00:30:00
1669	211	17	18	2019-04-03 04:15:00
1670	211	17	18	2018-03-17 21:45:00
1671	212	5	6	2021-09-18 13:00:00
1672	212	5	6	2021-04-24 19:15:00
1673	212	5	6	2021-06-03 23:45:00
1674	212	5	6	2020-01-15 20:15:00
1675	212	5	6	2021-05-10 13:45:00
1676	212	5	6	2021-04-10 04:15:00
1677	212	5	6	2021-09-20 17:00:00
1678	213	5	17	2019-02-03 11:30:00
1679	213	5	17	2019-12-12 22:00:00
1680	213	5	17	2019-02-03 05:00:00
1681	213	5	17	2019-01-07 01:30:00
1682	213	5	17	2019-12-26 17:30:00
1683	213	5	17	2018-12-16 12:45:00
1684	213	5	17	2019-12-04 00:15:00
1685	214	5	4	2020-08-29 13:00:00
1686	214	5	4	2019-02-01 03:30:00
1687	214	5	4	2020-09-10 08:45:00
1688	214	5	4	2019-09-05 06:30:00
1689	215	10	13	2020-11-30 23:45:00
1690	215	10	13	2021-03-28 13:45:00
1691	215	10	13	2021-06-09 08:00:00
1692	215	10	13	2020-08-10 18:45:00
1693	215	10	13	2021-08-28 12:30:00
1694	215	10	13	2021-01-04 10:00:00
1695	215	10	13	2020-06-10 19:15:00
1696	215	10	13	2021-07-11 23:15:00
1697	215	10	13	2021-01-20 00:00:00
1698	215	10	13	2020-06-21 02:15:00
1699	215	10	13	2020-04-07 17:15:00
1700	216	9	1	2018-08-01 02:00:00
1701	216	9	1	2018-08-14 05:00:00
1702	216	9	1	2019-11-14 08:45:00
1703	216	9	1	2018-10-04 06:00:00
1704	216	9	1	2018-11-11 20:15:00
1705	216	9	1	2019-09-23 00:30:00
1706	216	9	1	2019-07-21 05:30:00
1707	216	9	1	2020-05-05 09:45:00
1708	216	9	1	2019-11-10 11:15:00
1709	217	13	18	2018-11-01 23:30:00
1710	217	13	18	2017-08-07 06:00:00
1711	217	13	18	2017-05-27 11:00:00
1712	218	1	4	2018-07-06 18:15:00
1713	218	1	4	2018-05-15 05:30:00
1714	218	1	4	2018-06-19 19:45:00
1715	218	1	4	2018-04-01 09:30:00
1716	218	1	4	2019-05-16 11:30:00
1717	218	1	4	2018-04-06 13:30:00
1718	218	1	4	2019-04-28 21:15:00
1719	218	1	4	2018-04-23 06:00:00
1720	218	1	4	2019-05-02 12:45:00
1721	218	1	4	2018-08-15 21:30:00
1722	218	1	4	2019-04-24 02:15:00
1723	218	1	4	2018-11-15 21:45:00
1724	219	4	6	2019-11-30 12:15:00
1725	220	5	15	2021-03-22 09:15:00
1726	220	5	15	2019-07-07 07:15:00
1727	220	5	15	2019-09-13 21:15:00
1728	220	5	15	2021-02-18 16:00:00
1729	220	5	15	2019-11-21 17:00:00
1730	220	5	15	2020-11-03 06:30:00
1731	220	5	15	2019-12-22 09:15:00
1732	221	9	16	2019-12-20 19:30:00
1733	221	9	16	2019-09-03 23:00:00
1734	221	9	16	2019-03-29 08:00:00
1735	221	9	16	2018-08-24 03:45:00
1736	221	9	16	2019-01-04 02:15:00
1737	221	9	16	2018-03-03 14:30:00
1738	221	9	16	2019-10-09 21:45:00
1739	221	9	16	2019-09-07 14:15:00
1740	221	9	16	2018-03-15 09:30:00
1741	221	9	16	2018-03-19 15:15:00
1742	221	9	16	2019-12-04 15:15:00
1743	222	3	4	2019-01-28 13:00:00
1744	222	3	4	2018-06-29 03:30:00
1745	222	3	4	2018-08-15 07:15:00
1746	222	3	4	2018-03-13 02:00:00
1747	222	3	4	2018-08-30 19:30:00
1748	222	3	4	2017-10-28 05:00:00
1749	222	3	4	2018-01-08 00:00:00
1750	222	3	4	2018-02-24 13:45:00
1751	222	3	4	2018-03-23 09:15:00
1752	222	3	4	2018-07-07 04:30:00
1753	222	3	4	2017-05-25 16:30:00
1754	222	3	4	2018-09-10 00:15:00
1755	223	6	12	2019-01-28 04:45:00
1756	223	6	12	2018-11-05 10:45:00
1757	223	6	12	2020-06-11 01:15:00
1758	223	6	12	2020-05-19 21:30:00
1759	223	6	12	2020-04-02 12:30:00
1760	223	6	12	2020-04-04 12:45:00
1761	223	6	12	2019-02-21 02:00:00
1762	223	6	12	2020-06-29 20:45:00
1763	223	6	12	2020-07-05 08:30:00
1764	223	6	12	2019-08-01 09:45:00
1765	223	6	12	2019-12-05 07:45:00
1766	223	6	12	2018-09-06 17:15:00
1767	223	6	12	2019-01-20 15:30:00
1768	223	6	12	2020-04-15 13:45:00
1769	224	9	11	2018-04-21 20:45:00
1770	224	9	11	2019-01-17 10:30:00
1771	224	9	11	2018-06-05 14:45:00
1772	224	9	11	2019-05-10 08:00:00
1773	224	9	11	2019-03-19 09:30:00
1774	224	9	11	2018-01-28 15:30:00
1775	225	19	14	2020-03-27 02:45:00
1776	225	19	14	2019-11-21 04:45:00
1777	225	19	14	2019-09-24 11:45:00
1778	225	19	14	2020-03-27 09:00:00
1779	225	19	14	2021-02-24 01:00:00
1780	225	19	14	2020-07-03 02:00:00
1781	225	19	14	2020-04-27 11:00:00
1782	225	19	14	2019-12-24 23:45:00
1783	225	19	14	2020-01-22 20:00:00
1784	225	19	14	2020-01-13 12:30:00
1785	225	19	14	2019-10-08 02:45:00
1786	226	10	16	2019-01-07 23:30:00
1787	226	10	16	2018-10-07 03:45:00
1788	226	10	16	2018-11-17 17:00:00
1789	226	10	16	2019-11-27 17:45:00
1790	226	10	16	2020-02-06 01:45:00
1791	226	10	16	2019-08-08 00:00:00
1792	226	10	16	2018-10-21 11:30:00
1793	226	10	16	2020-02-12 00:00:00
1794	226	10	16	2019-10-14 21:30:00
1795	226	10	16	2020-03-25 09:00:00
1796	226	10	16	2019-06-05 16:15:00
1797	226	10	16	2020-01-29 03:15:00
1798	227	7	5	2019-08-12 20:45:00
1799	227	7	5	2019-08-06 04:15:00
1800	227	7	5	2018-07-09 13:30:00
1801	227	7	5	2018-11-26 02:15:00
1802	227	7	5	2018-08-01 21:45:00
1803	227	7	5	2019-08-22 08:15:00
1804	228	5	11	2019-11-14 10:45:00
1805	228	5	11	2019-04-02 03:45:00
1806	228	5	11	2020-03-22 09:30:00
1807	229	9	6	2018-08-04 17:30:00
1808	229	9	6	2018-02-08 06:30:00
1809	229	9	6	2019-04-15 09:30:00
1810	229	9	6	2018-09-06 04:45:00
1811	230	16	6	2019-07-29 16:15:00
1812	230	16	6	2020-03-11 11:30:00
1813	230	16	6	2020-04-12 11:15:00
1814	230	16	6	2020-09-17 12:45:00
1815	230	16	6	2020-05-30 13:30:00
1816	231	7	6	2018-11-03 21:30:00
1817	231	7	6	2019-11-11 13:45:00
1818	231	7	6	2018-02-09 16:30:00
1819	231	7	6	2019-08-23 09:45:00
1820	231	7	6	2019-06-21 03:45:00
1821	231	7	6	2019-12-03 19:00:00
1822	231	7	6	2019-05-10 08:00:00
1823	231	7	6	2019-01-19 09:30:00
1824	231	7	6	2018-06-10 18:45:00
1825	231	7	6	2019-09-28 23:45:00
1826	231	7	6	2018-02-19 15:45:00
1827	231	7	6	2018-10-20 04:00:00
1828	232	8	2	2019-08-16 16:30:00
1829	232	8	2	2019-03-15 14:00:00
1830	233	8	17	2020-09-10 20:45:00
1831	233	8	17	2020-09-27 10:45:00
1832	233	8	17	2019-12-18 02:00:00
1833	233	8	17	2020-04-16 17:15:00
1834	233	8	17	2019-01-27 01:00:00
1835	233	8	17	2020-08-04 22:00:00
1836	233	8	17	2020-06-10 09:15:00
1837	233	8	17	2020-07-11 16:15:00
1838	233	8	17	2018-11-19 04:30:00
1839	233	8	17	2020-03-11 15:45:00
1840	233	8	17	2019-06-07 03:45:00
1841	234	17	3	2019-05-13 04:15:00
1842	235	9	8	2018-10-28 02:30:00
1843	235	9	8	2018-01-30 04:00:00
1844	235	9	8	2018-07-22 23:45:00
1845	235	9	8	2018-12-27 12:15:00
1846	235	9	8	2019-02-13 14:15:00
1847	235	9	8	2019-06-22 14:15:00
1848	235	9	8	2018-01-12 00:15:00
1849	235	9	8	2019-11-26 13:15:00
1850	236	8	4	2018-12-17 03:15:00
1851	236	8	4	2018-01-19 16:45:00
1852	236	8	4	2018-04-03 03:00:00
1853	236	8	4	2018-02-05 00:30:00
1854	236	8	4	2018-01-18 04:45:00
1855	236	8	4	2017-05-09 13:00:00
1856	236	8	4	2017-09-17 13:30:00
1857	236	8	4	2017-03-04 21:00:00
1858	237	14	7	2019-12-27 14:00:00
1859	238	5	2	2019-01-23 07:45:00
1860	238	5	2	2019-01-12 20:15:00
1861	238	5	2	2019-06-27 11:45:00
1862	238	5	2	2019-10-11 04:00:00
1863	238	5	2	2019-07-19 00:45:00
1864	238	5	2	2018-12-25 02:45:00
1865	238	5	2	2019-12-28 11:00:00
1866	238	5	2	2019-03-22 19:45:00
1867	238	5	2	2018-10-25 09:00:00
1868	238	5	2	2020-05-29 10:30:00
1869	238	5	2	2019-01-21 12:15:00
1870	239	12	19	2020-03-13 01:15:00
1871	239	12	19	2019-07-15 15:00:00
1872	239	12	19	2018-10-07 08:00:00
1873	239	12	19	2019-03-15 22:30:00
1874	239	12	19	2018-11-05 10:00:00
1875	239	12	19	2018-08-11 05:00:00
1876	239	12	19	2018-10-23 07:00:00
1877	239	12	19	2018-06-13 23:00:00
1878	239	12	19	2018-08-22 08:30:00
1879	240	2	20	2021-04-07 18:45:00
1880	240	2	20	2020-04-04 02:00:00
1881	240	2	20	2020-01-28 08:15:00
1882	240	2	20	2021-10-10 13:00:00
1883	240	2	20	2020-02-20 21:00:00
1884	240	2	20	2020-02-21 19:15:00
1885	240	2	20	2021-07-11 10:15:00
1886	241	9	12	2018-05-07 01:15:00
1887	241	9	12	2019-09-15 16:15:00
1888	241	9	12	2019-05-20 07:30:00
1889	241	9	12	2018-12-28 08:00:00
1890	241	9	12	2019-07-28 08:45:00
1891	241	9	12	2018-06-03 02:15:00
1892	241	9	12	2018-03-26 22:30:00
1893	241	9	12	2018-07-20 07:30:00
1894	241	9	12	2018-06-26 05:00:00
1895	241	9	12	2018-01-03 05:45:00
1896	241	9	12	2018-02-21 12:30:00
1897	241	9	12	2019-03-27 00:45:00
1898	242	18	19	2021-08-16 15:00:00
1899	242	18	19	2020-03-09 20:45:00
1900	242	18	19	2021-02-13 03:45:00
1901	242	18	19	2020-11-24 13:15:00
1902	242	18	19	2020-12-30 17:30:00
1903	242	18	19	2020-11-04 12:45:00
1904	242	18	19	2019-10-01 21:45:00
1905	242	18	19	2021-06-17 11:15:00
1906	242	18	19	2020-01-24 11:00:00
1907	242	18	19	2020-12-19 13:15:00
1908	242	18	19	2020-02-09 01:00:00
1909	242	18	19	2021-05-03 05:45:00
1910	242	18	19	2021-04-19 07:45:00
1911	242	18	19	2020-04-22 00:15:00
1912	242	18	19	2020-11-16 01:45:00
1913	243	18	6	2018-02-17 20:00:00
1914	243	18	6	2018-08-21 20:30:00
1915	243	18	6	2019-01-09 11:30:00
1916	243	18	6	2018-11-18 06:15:00
1917	243	18	6	2017-09-11 01:45:00
1918	243	18	6	2018-07-03 20:00:00
1919	243	18	6	2017-09-21 21:30:00
1920	243	18	6	2018-08-06 02:15:00
1921	243	18	6	2018-11-10 19:30:00
1922	244	8	16	2019-12-28 05:30:00
1923	244	8	16	2020-06-16 07:45:00
1924	245	9	16	2019-10-07 19:45:00
1925	245	9	16	2020-05-21 08:30:00
1926	245	9	16	2020-10-28 20:45:00
1927	245	9	16	2020-04-13 06:45:00
1928	245	9	16	2019-10-23 09:00:00
1929	245	9	16	2021-06-19 00:00:00
1930	245	9	16	2020-11-27 18:45:00
1931	245	9	16	2020-08-03 12:15:00
1932	245	9	16	2020-06-02 04:45:00
1933	246	19	16	2017-11-05 14:30:00
1934	246	19	16	2018-06-20 17:15:00
1935	247	20	9	2020-01-23 12:45:00
1936	247	20	9	2019-09-13 01:45:00
1937	248	4	8	2019-02-01 21:15:00
1938	248	4	8	2018-04-11 20:00:00
1939	248	4	8	2018-04-30 11:30:00
1940	248	4	8	2018-12-02 12:45:00
1941	248	4	8	2019-05-06 14:15:00
1942	248	4	8	2017-11-19 11:30:00
1943	248	4	8	2018-09-07 16:00:00
1944	248	4	8	2017-12-02 07:30:00
1945	248	4	8	2019-03-15 04:30:00
1946	248	4	8	2018-10-25 19:45:00
1947	248	4	8	2018-06-04 18:30:00
1948	248	4	8	2018-06-08 07:00:00
1949	248	4	8	2017-11-17 19:30:00
1950	248	4	8	2019-03-22 07:30:00
1951	248	4	8	2018-12-20 20:15:00
1952	249	13	6	2020-07-23 11:45:00
1953	249	13	6	2020-07-28 08:45:00
1954	249	13	6	2020-07-02 09:00:00
1955	249	13	6	2020-03-03 11:30:00
1956	249	13	6	2020-09-18 14:00:00
1957	249	13	6	2019-10-24 14:00:00
1958	249	13	6	2020-06-01 04:45:00
1959	249	13	6	2019-03-18 03:30:00
1960	250	12	1	2019-05-29 05:30:00
1961	250	12	1	2019-09-13 10:30:00
1962	250	12	1	2020-08-20 00:30:00
1963	250	12	1	2020-04-21 11:45:00
1964	250	12	1	2019-10-20 21:00:00
1965	250	12	1	2019-09-17 06:30:00
1966	251	2	2	2019-07-16 21:00:00
1967	251	2	2	2017-12-05 03:00:00
1968	251	2	2	2018-11-30 15:15:00
1969	251	2	2	2019-06-01 09:00:00
1970	251	2	2	2018-08-20 05:00:00
1971	251	2	2	2017-11-19 23:45:00
1972	252	13	15	2021-02-17 19:00:00
1973	252	13	15	2019-11-06 00:30:00
1974	252	13	15	2020-03-10 02:45:00
1975	252	13	15	2019-08-26 16:00:00
1976	252	13	15	2019-10-18 05:15:00
1977	253	7	9	2019-03-19 17:15:00
1978	253	7	9	2018-12-07 17:00:00
1979	253	7	9	2019-02-08 23:00:00
1980	253	7	9	2020-03-24 06:00:00
1981	253	7	9	2020-02-05 02:15:00
1982	253	7	9	2018-11-26 05:15:00
1983	253	7	9	2018-12-13 13:30:00
1984	253	7	9	2019-11-19 20:45:00
1985	253	7	9	2019-02-18 06:30:00
1986	253	7	9	2019-12-28 00:15:00
1987	253	7	9	2020-02-20 20:45:00
1988	253	7	9	2018-11-11 00:15:00
1989	253	7	9	2019-10-07 18:00:00
1990	253	7	9	2019-04-24 04:00:00
1991	254	13	1	2017-12-07 22:45:00
1992	254	13	1	2019-01-10 22:15:00
1993	254	13	1	2018-07-09 15:45:00
1994	254	13	1	2018-02-12 11:45:00
1995	254	13	1	2018-01-23 08:00:00
1996	254	13	1	2018-08-23 07:00:00
1997	255	8	20	2018-02-04 18:15:00
1998	255	8	20	2018-04-21 13:30:00
1999	255	8	20	2019-08-22 17:00:00
2000	255	8	20	2018-12-15 15:00:00
2001	255	8	20	2019-05-11 09:15:00
2002	255	8	20	2017-11-21 19:30:00
2003	255	8	20	2018-09-16 16:30:00
2004	255	8	20	2019-09-12 11:45:00
2005	255	8	20	2019-03-20 02:15:00
2006	256	6	20	2020-11-29 06:15:00
2007	256	6	20	2020-04-01 08:45:00
2008	256	6	20	2020-03-20 11:00:00
2009	256	6	20	2020-03-08 19:00:00
2010	256	6	20	2020-02-04 01:45:00
2011	256	6	20	2020-11-20 08:45:00
2012	256	6	20	2020-11-29 02:45:00
2013	257	16	11	2020-01-21 15:15:00
2014	257	16	11	2019-05-26 12:45:00
2015	257	16	11	2020-10-14 02:00:00
2016	257	16	11	2019-12-17 20:30:00
2017	257	16	11	2019-06-09 12:45:00
2018	257	16	11	2020-07-17 09:45:00
2019	257	16	11	2019-10-04 00:30:00
2020	258	1	17	2018-11-05 17:45:00
2021	258	1	17	2019-06-03 16:15:00
2022	258	1	17	2019-09-26 22:15:00
2023	258	1	17	2018-01-20 03:15:00
2024	258	1	17	2018-04-23 11:45:00
2025	258	1	17	2018-01-30 04:30:00
2026	258	1	17	2018-03-08 03:15:00
2027	258	1	17	2018-01-25 14:45:00
2028	258	1	17	2018-05-06 15:00:00
2029	258	1	17	2018-02-20 11:15:00
2030	258	1	17	2019-03-14 08:45:00
2031	258	1	17	2018-12-04 18:15:00
2032	258	1	17	2017-10-15 07:45:00
2033	258	1	17	2018-11-11 21:15:00
2034	258	1	17	2019-06-30 02:45:00
2035	259	15	13	2018-09-08 19:15:00
2036	259	15	13	2019-04-08 01:30:00
2037	259	15	13	2018-12-09 04:45:00
2038	260	16	13	2021-04-09 05:45:00
2039	260	16	13	2020-08-29 06:30:00
2040	260	16	13	2021-06-19 20:15:00
2041	260	16	13	2020-11-28 05:30:00
2042	260	16	13	2019-10-21 05:00:00
2043	260	16	13	2020-03-05 05:15:00
2044	260	16	13	2020-02-03 02:45:00
2045	260	16	13	2021-05-12 19:45:00
2046	261	4	13	2019-02-15 14:15:00
2047	261	4	13	2017-10-12 10:45:00
2048	261	4	13	2018-12-12 14:15:00
2049	261	4	13	2019-03-26 23:15:00
2050	261	4	13	2018-01-16 05:00:00
2051	261	4	13	2018-04-01 22:30:00
2052	261	4	13	2019-06-22 20:15:00
2053	261	4	13	2018-05-22 17:30:00
2054	262	6	6	2020-01-01 00:00:00
2055	262	6	6	2020-05-08 06:45:00
2056	262	6	6	2020-04-12 18:45:00
2057	262	6	6	2020-10-08 23:30:00
2058	263	7	13	2017-06-14 00:00:00
2059	263	7	13	2018-07-18 00:45:00
2060	263	7	13	2017-08-17 06:30:00
2061	263	7	13	2018-01-06 20:15:00
2062	263	7	13	2017-11-24 10:30:00
2063	263	7	13	2017-06-09 14:00:00
2064	263	7	13	2019-01-23 18:00:00
2065	263	7	13	2018-05-29 18:15:00
2066	263	7	13	2017-03-14 19:15:00
2067	263	7	13	2018-02-16 18:00:00
2068	263	7	13	2018-02-11 17:00:00
2069	263	7	13	2019-01-23 16:45:00
2070	264	10	20	2017-09-16 01:15:00
2071	264	10	20	2017-11-27 15:15:00
2072	264	10	20	2018-10-27 05:45:00
2073	264	10	20	2017-03-11 07:00:00
2074	264	10	20	2017-10-25 07:30:00
2075	264	10	20	2018-12-01 14:30:00
2076	265	12	8	2020-02-09 14:15:00
2077	265	12	8	2020-06-02 03:15:00
2078	265	12	8	2019-06-25 12:45:00
2079	265	12	8	2019-10-30 16:45:00
2080	265	12	8	2019-08-21 11:45:00
2081	265	12	8	2019-06-15 19:30:00
2082	265	12	8	2020-01-01 04:15:00
2083	265	12	8	2019-09-10 09:30:00
2084	265	12	8	2019-05-26 21:15:00
2085	265	12	8	2019-07-26 07:45:00
2086	265	12	8	2018-12-28 08:00:00
2087	266	18	8	2019-11-06 00:00:00
2088	266	18	8	2019-12-25 02:30:00
2089	267	20	16	2018-10-24 19:45:00
2090	267	20	16	2020-05-19 00:45:00
2091	267	20	16	2019-05-03 16:00:00
2092	267	20	16	2019-05-16 07:45:00
2093	268	10	16	2017-11-28 07:15:00
2094	268	10	16	2019-01-04 20:45:00
2095	268	10	16	2017-11-28 05:30:00
2096	268	10	16	2018-10-10 16:00:00
2097	268	10	16	2017-12-08 16:00:00
2098	268	10	16	2017-09-07 16:30:00
2099	268	10	16	2017-11-02 05:30:00
2100	268	10	16	2017-07-22 10:30:00
2101	268	10	16	2017-06-21 20:45:00
2102	268	10	16	2018-10-22 01:15:00
2103	268	10	16	2018-12-21 20:00:00
2104	268	10	16	2017-12-13 23:45:00
2105	268	10	16	2017-12-04 08:30:00
2106	269	10	17	2019-12-18 08:00:00
2107	269	10	17	2019-07-05 00:15:00
2108	269	10	17	2020-03-21 17:00:00
2109	269	10	17	2019-02-15 16:15:00
2110	269	10	17	2020-09-30 03:00:00
2111	270	19	4	2020-02-16 03:30:00
2112	270	19	4	2019-11-18 08:45:00
2113	270	19	4	2020-05-15 03:30:00
2114	270	19	4	2019-12-22 17:45:00
2115	270	19	4	2019-09-23 06:30:00
2116	270	19	4	2019-07-08 14:15:00
2117	270	19	4	2019-09-15 07:00:00
2118	270	19	4	2020-04-04 17:45:00
2119	271	1	20	2019-09-09 12:00:00
2120	271	1	20	2020-07-02 00:00:00
2121	271	1	20	2020-12-04 23:30:00
2122	271	1	20	2020-10-04 00:15:00
2123	271	1	20	2019-12-27 22:45:00
2124	271	1	20	2020-10-30 16:45:00
2125	271	1	20	2019-04-17 04:00:00
2126	271	1	20	2019-06-16 16:45:00
2127	271	1	20	2020-12-03 23:00:00
2128	272	18	15	2021-07-13 12:30:00
2129	272	18	15	2019-09-01 16:30:00
2130	272	18	15	2020-04-03 19:30:00
2131	273	12	4	2017-10-09 13:15:00
2132	273	12	4	2019-01-14 21:30:00
2133	273	12	4	2018-08-22 05:00:00
2134	273	12	4	2018-05-16 06:00:00
2135	273	12	4	2017-02-24 15:45:00
2136	273	12	4	2018-03-28 23:45:00
2137	273	12	4	2017-03-11 18:15:00
2138	273	12	4	2017-12-13 18:30:00
2139	273	12	4	2019-01-10 19:15:00
2140	274	19	12	2021-06-04 05:00:00
2141	274	19	12	2020-06-13 06:30:00
2142	274	19	12	2021-01-19 13:00:00
2143	274	19	12	2020-09-17 10:30:00
2144	274	19	12	2020-06-13 11:00:00
2145	274	19	12	2021-01-20 19:30:00
2146	274	19	12	2021-07-21 20:30:00
2147	274	19	12	2020-08-04 03:45:00
2148	274	19	12	2021-07-05 04:15:00
2149	274	19	12	2019-11-01 13:00:00
2150	274	19	12	2020-02-14 16:45:00
2151	275	9	20	2018-05-06 21:45:00
2152	275	9	20	2019-03-16 02:45:00
2153	275	9	20	2019-04-12 19:45:00
2154	275	9	20	2019-07-14 16:00:00
2155	275	9	20	2018-11-01 13:00:00
2156	275	9	20	2018-04-30 18:30:00
2157	275	9	20	2018-06-08 06:15:00
2158	275	9	20	2019-03-21 03:30:00
2159	275	9	20	2017-12-09 15:30:00
2160	275	9	20	2018-10-05 07:00:00
2161	275	9	20	2018-05-20 08:45:00
2162	275	9	20	2018-03-06 16:00:00
2163	275	9	20	2017-10-14 06:00:00
2164	275	9	20	2018-11-28 06:00:00
2165	275	9	20	2019-01-28 00:00:00
2166	276	9	9	2019-02-01 09:45:00
2167	276	9	9	2019-08-07 07:15:00
2168	277	10	14	2021-02-10 05:45:00
2169	277	10	14	2021-05-05 01:30:00
2170	277	10	14	2019-11-30 02:45:00
2171	278	13	8	2021-06-28 04:30:00
2172	278	13	8	2020-11-21 13:45:00
2173	278	13	8	2020-09-28 15:30:00
2174	278	13	8	2020-05-06 19:45:00
2175	278	13	8	2021-02-27 07:00:00
2176	278	13	8	2020-03-04 07:30:00
2177	278	13	8	2020-01-25 12:00:00
2178	278	13	8	2020-10-14 06:15:00
2179	278	13	8	2021-01-15 07:45:00
2180	278	13	8	2021-05-16 23:30:00
2181	279	6	3	2019-05-24 06:00:00
2182	279	6	3	2019-05-19 18:00:00
2183	279	6	3	2019-04-21 15:15:00
2184	279	6	3	2019-04-08 14:45:00
2185	280	1	20	2018-06-09 16:45:00
2186	280	1	20	2017-04-15 13:30:00
2187	280	1	20	2017-12-20 02:00:00
2188	280	1	20	2018-10-28 01:45:00
2189	280	1	20	2017-03-18 22:15:00
2190	280	1	20	2018-10-01 20:00:00
2191	280	1	20	2018-11-21 04:45:00
2192	280	1	20	2018-07-05 16:45:00
2193	280	1	20	2018-08-14 12:45:00
2194	280	1	20	2018-02-10 14:45:00
2195	280	1	20	2018-07-22 09:00:00
2196	280	1	20	2018-06-07 05:30:00
2197	281	4	10	2019-10-13 02:30:00
2198	281	4	10	2019-12-02 18:30:00
2199	281	4	10	2020-01-22 17:15:00
2200	281	4	10	2020-03-30 02:30:00
2201	282	10	3	2018-08-09 19:15:00
2202	282	10	3	2019-04-02 01:45:00
2203	282	10	3	2019-01-13 20:30:00
2204	282	10	3	2017-12-09 17:45:00
2205	282	10	3	2019-07-28 05:45:00
2206	282	10	3	2019-03-25 10:45:00
2207	282	10	3	2018-08-25 03:45:00
2208	282	10	3	2019-08-16 20:15:00
2209	282	10	3	2019-10-26 01:30:00
2210	282	10	3	2018-12-18 21:00:00
2211	283	2	5	2018-01-12 01:00:00
2212	283	2	5	2018-06-30 11:00:00
2213	284	2	1	2019-09-07 21:00:00
2214	284	2	1	2020-09-01 18:30:00
2215	284	2	1	2020-10-22 22:00:00
2216	284	2	1	2019-08-02 06:30:00
2217	284	2	1	2020-10-05 10:00:00
2218	284	2	1	2020-02-15 05:00:00
2219	284	2	1	2020-05-13 23:15:00
2220	284	2	1	2021-02-04 13:15:00
2221	284	2	1	2020-12-01 09:45:00
2222	284	2	1	2019-06-09 13:15:00
2223	284	2	1	2019-05-17 12:45:00
2224	284	2	1	2019-12-23 09:00:00
2225	284	2	1	2019-04-11 08:15:00
2226	285	7	20	2021-03-27 07:45:00
2227	285	7	20	2020-11-11 02:30:00
2228	286	10	13	2020-02-09 08:00:00
2229	286	10	13	2020-04-07 11:30:00
2230	286	10	13	2020-09-30 19:30:00
2231	286	10	13	2020-12-13 14:45:00
2232	286	10	13	2019-11-23 20:30:00
2233	286	10	13	2020-03-25 19:30:00
2234	286	10	13	2020-08-16 08:00:00
2235	286	10	13	2020-08-04 17:45:00
2236	286	10	13	2020-04-14 10:45:00
2237	286	10	13	2020-05-10 11:45:00
2238	286	10	13	2020-02-11 02:30:00
2239	286	10	13	2019-12-25 04:00:00
2240	287	2	20	2018-04-12 03:00:00
2241	287	2	20	2018-03-07 09:00:00
2242	287	2	20	2018-05-12 16:45:00
2243	287	2	20	2019-05-08 01:30:00
2244	287	2	20	2019-03-09 15:15:00
2245	287	2	20	2017-11-07 20:00:00
2246	287	2	20	2018-03-26 15:00:00
2247	287	2	20	2019-03-06 21:30:00
2248	287	2	20	2019-08-09 15:15:00
2249	287	2	20	2018-01-17 00:45:00
2250	287	2	20	2019-08-19 12:45:00
2251	287	2	20	2019-09-21 02:30:00
2252	287	2	20	2019-06-24 11:45:00
2253	288	13	10	2020-10-06 14:15:00
2254	289	7	4	2019-04-15 07:15:00
2255	289	7	4	2020-09-07 02:45:00
2256	289	7	4	2019-02-20 09:30:00
2257	289	7	4	2018-11-21 19:00:00
2258	289	7	4	2018-10-16 10:45:00
2259	289	7	4	2020-04-16 23:00:00
2260	289	7	4	2019-01-21 04:45:00
2261	289	7	4	2020-04-16 05:45:00
2262	289	7	4	2020-08-24 10:15:00
2263	289	7	4	2019-07-20 17:45:00
2264	289	7	4	2018-10-22 06:00:00
2265	289	7	4	2019-10-16 19:00:00
2266	289	7	4	2020-03-06 06:45:00
2267	289	7	4	2019-10-05 18:15:00
2268	290	7	14	2019-06-25 20:00:00
2269	290	7	14	2019-07-11 09:30:00
2270	290	7	14	2019-02-10 09:30:00
2271	290	7	14	2020-01-11 12:15:00
2272	290	7	14	2020-03-21 04:45:00
2273	290	7	14	2019-09-21 09:30:00
2274	290	7	14	2020-10-05 04:15:00
2275	290	7	14	2020-01-30 06:45:00
2276	290	7	14	2020-10-21 23:45:00
2277	290	7	14	2019-03-20 14:45:00
2278	290	7	14	2019-05-22 16:30:00
2279	290	7	14	2020-12-06 22:00:00
2280	291	10	15	2018-12-15 04:30:00
2281	291	10	15	2018-07-07 22:00:00
2282	291	10	15	2019-02-18 16:45:00
2283	291	10	15	2017-03-12 15:30:00
2284	291	10	15	2018-11-30 23:45:00
2285	292	5	17	2021-05-20 08:30:00
2286	292	5	17	2020-03-21 05:00:00
2287	293	10	9	2020-10-10 15:15:00
2288	293	10	9	2020-11-19 19:15:00
2289	293	10	9	2020-05-14 10:15:00
2290	293	10	9	2019-10-17 07:30:00
2291	294	9	18	2020-05-22 05:30:00
2292	294	9	18	2019-11-05 19:15:00
2293	294	9	18	2020-12-27 20:30:00
2294	294	9	18	2021-01-23 20:30:00
2295	294	9	18	2020-05-02 03:45:00
2296	294	9	18	2021-03-07 18:30:00
2297	294	9	18	2021-06-14 13:30:00
2298	294	9	18	2021-03-22 06:15:00
2299	294	9	18	2019-11-21 06:30:00
2300	294	9	18	2020-07-06 15:00:00
2301	294	9	18	2019-11-05 23:00:00
2302	294	9	18	2021-08-27 17:45:00
2303	294	9	18	2020-02-15 00:00:00
2304	294	9	18	2021-07-09 00:30:00
2305	295	7	17	2019-10-23 03:15:00
2306	295	7	17	2020-04-14 23:00:00
2307	295	7	17	2019-12-22 12:15:00
2308	295	7	17	2019-07-13 13:15:00
2309	295	7	17	2020-04-30 08:45:00
2310	295	7	17	2019-10-23 02:15:00
2311	296	6	11	2021-11-16 00:45:00
2312	296	6	11	2021-02-20 16:30:00
2313	296	6	11	2020-06-12 09:45:00
2314	296	6	11	2020-10-22 22:30:00
2315	296	6	11	2021-06-14 01:30:00
2316	296	6	11	2020-01-08 17:00:00
2317	296	6	11	2021-08-30 13:00:00
2318	296	6	11	2020-06-11 01:45:00
2319	296	6	11	2021-07-16 14:15:00
2320	297	18	3	2021-05-08 05:45:00
2321	297	18	3	2021-04-02 01:00:00
2322	297	18	3	2020-08-11 17:30:00
2323	297	18	3	2021-02-03 15:30:00
2324	297	18	3	2020-04-13 19:45:00
2325	297	18	3	2020-05-05 00:15:00
2326	297	18	3	2019-11-24 18:00:00
2327	297	18	3	2021-05-27 06:30:00
2328	297	18	3	2020-09-08 16:30:00
2329	297	18	3	2019-09-22 09:00:00
2330	297	18	3	2020-01-26 00:45:00
2331	297	18	3	2020-04-11 15:00:00
2332	297	18	3	2019-10-27 15:30:00
2333	297	18	3	2021-04-05 09:15:00
2334	298	5	11	2019-11-03 18:30:00
2335	298	5	11	2019-10-01 05:15:00
2336	298	5	11	2020-10-13 08:00:00
2337	298	5	11	2020-11-14 22:00:00
2338	298	5	11	2021-03-12 19:00:00
2339	298	5	11	2020-08-30 19:15:00
2340	298	5	11	2021-03-27 18:00:00
2341	298	5	11	2020-01-28 21:45:00
2342	298	5	11	2020-08-15 03:00:00
2343	298	5	11	2019-07-23 03:45:00
2344	298	5	11	2020-09-18 12:00:00
2345	298	5	11	2020-02-19 21:45:00
2346	299	20	2	2019-04-22 19:00:00
2347	299	20	2	2019-08-17 23:30:00
2348	299	20	2	2019-08-25 03:00:00
2349	299	20	2	2019-04-03 04:00:00
2350	299	20	2	2019-04-05 09:45:00
2351	300	2	4	2019-06-29 15:15:00
2352	300	2	4	2017-08-16 17:00:00
2353	300	2	4	2018-12-18 23:30:00
2354	300	2	4	2019-03-18 15:30:00
2355	300	2	4	2019-01-07 17:15:00
2356	300	2	4	2017-12-18 15:45:00
2357	300	2	4	2019-02-03 11:15:00
2358	300	2	4	2017-09-11 17:30:00
2359	300	2	4	2018-01-12 00:00:00
2360	300	2	4	2018-02-17 02:15:00
2361	300	2	4	2017-11-02 23:30:00
2362	301	8	9	2019-09-14 15:45:00
2363	301	8	9	2019-03-30 12:00:00
2364	301	8	9	2020-05-18 13:15:00
2365	301	8	9	2019-05-19 06:15:00
2366	301	8	9	2019-11-03 14:45:00
2367	301	8	9	2020-06-09 17:45:00
2368	301	8	9	2019-10-21 19:15:00
2369	301	8	9	2018-12-29 19:00:00
2370	301	8	9	2019-04-17 06:30:00
2371	301	8	9	2019-08-07 04:30:00
2372	302	8	11	2021-01-22 17:00:00
2373	302	8	11	2019-05-12 21:00:00
2374	303	9	10	2020-04-15 06:45:00
2375	303	9	10	2019-08-30 10:30:00
2376	303	9	10	2020-08-30 07:15:00
2377	303	9	10	2019-08-08 21:30:00
2378	303	9	10	2020-10-21 11:30:00
2379	304	6	11	2020-01-12 06:15:00
2380	304	6	11	2019-03-05 03:00:00
2381	304	6	11	2019-06-18 06:45:00
2382	304	6	11	2018-06-01 17:30:00
2383	304	6	11	2019-10-26 14:45:00
2384	304	6	11	2018-11-13 01:00:00
2385	304	6	11	2020-01-12 09:30:00
2386	304	6	11	2018-12-09 10:45:00
2387	304	6	11	2018-10-17 11:45:00
2388	304	6	11	2019-05-12 16:15:00
2389	304	6	11	2019-08-28 01:30:00
2390	305	17	11	2020-04-13 13:15:00
2391	305	17	11	2020-11-21 23:45:00
2392	305	17	11	2021-04-27 17:00:00
2393	305	17	11	2021-03-05 16:00:00
2394	306	15	17	2018-05-01 09:15:00
2395	306	15	17	2019-11-11 23:15:00
2396	306	15	17	2019-02-14 11:30:00
2397	306	15	17	2020-03-10 03:45:00
2398	306	15	17	2019-12-23 04:15:00
2399	306	15	17	2018-10-08 13:15:00
2400	306	15	17	2018-04-19 06:30:00
2401	306	15	17	2018-06-03 19:15:00
2402	306	15	17	2018-10-10 05:30:00
2403	306	15	17	2019-01-09 09:00:00
2404	307	5	20	2020-02-18 23:45:00
2405	307	5	20	2018-12-07 04:30:00
2406	307	5	20	2019-12-10 14:45:00
2407	307	5	20	2019-09-01 09:00:00
2408	307	5	20	2019-07-20 18:15:00
2409	307	5	20	2018-11-06 05:15:00
2410	307	5	20	2020-01-17 04:15:00
2411	307	5	20	2020-06-25 22:00:00
2412	307	5	20	2019-03-19 17:15:00
2413	307	5	20	2019-02-06 01:30:00
2414	307	5	20	2019-08-26 14:45:00
2415	307	5	20	2019-03-14 01:30:00
2416	307	5	20	2019-10-04 03:30:00
2417	307	5	20	2018-11-24 08:30:00
2418	307	5	20	2018-11-29 11:30:00
2419	308	1	6	2021-01-14 15:45:00
2420	308	1	6	2020-03-07 09:00:00
2421	308	1	6	2020-12-15 11:15:00
2422	308	1	6	2020-01-27 06:00:00
2423	308	1	6	2021-04-30 07:15:00
2424	308	1	6	2021-04-28 03:30:00
2425	308	1	6	2021-06-06 18:00:00
2426	308	1	6	2020-05-17 08:30:00
2427	308	1	6	2020-03-24 03:00:00
2428	308	1	6	2020-11-22 07:15:00
2429	308	1	6	2020-10-11 08:15:00
2430	308	1	6	2020-02-24 10:00:00
2431	309	6	18	2017-11-24 10:30:00
2432	309	6	18	2018-11-17 07:15:00
2433	309	6	18	2018-05-26 04:45:00
2434	309	6	18	2018-05-29 20:30:00
2435	309	6	18	2018-08-13 18:15:00
2436	309	6	18	2017-10-17 08:45:00
2437	309	6	18	2017-10-24 09:00:00
2438	309	6	18	2019-04-04 00:15:00
2439	309	6	18	2018-04-12 13:30:00
2440	309	6	18	2018-03-16 08:00:00
2441	309	6	18	2017-08-08 02:15:00
2442	309	6	18	2019-04-20 17:45:00
2443	310	8	9	2020-07-16 08:45:00
2444	311	6	9	2020-01-24 14:30:00
2445	311	6	9	2020-09-02 21:45:00
2446	312	1	12	2019-11-23 05:00:00
2447	312	1	12	2020-08-07 16:00:00
2448	312	1	12	2021-04-24 15:30:00
2449	312	1	12	2019-08-04 05:30:00
2450	312	1	12	2019-11-01 23:00:00
2451	312	1	12	2021-05-29 16:00:00
2452	312	1	12	2019-08-14 20:00:00
2453	312	1	12	2020-06-04 10:15:00
2454	312	1	12	2020-01-04 18:15:00
2455	312	1	12	2020-09-06 16:00:00
2456	312	1	12	2019-10-02 22:45:00
2457	312	1	12	2019-10-06 17:30:00
2458	312	1	12	2021-06-25 23:30:00
2459	312	1	12	2020-08-23 16:45:00
2460	312	1	12	2020-09-07 01:15:00
2461	313	6	5	2017-09-24 05:30:00
2462	313	6	5	2017-12-15 13:15:00
2463	314	14	13	2019-12-19 06:30:00
2464	314	14	13	2018-11-01 21:30:00
2465	314	14	13	2018-11-22 18:45:00
2466	314	14	13	2018-12-08 09:00:00
2467	314	14	13	2020-04-27 18:45:00
2468	314	14	13	2019-06-22 18:15:00
2469	314	14	13	2018-12-22 09:00:00
2470	314	14	13	2019-11-11 03:30:00
2471	314	14	13	2019-01-12 17:00:00
2472	314	14	13	2019-12-12 03:45:00
2473	315	11	3	2020-01-02 09:00:00
2474	315	11	3	2020-04-08 12:15:00
2475	315	11	3	2019-08-17 03:15:00
2476	315	11	3	2020-08-27 03:15:00
2477	315	11	3	2020-08-07 07:45:00
2478	315	11	3	2020-03-20 08:30:00
2479	315	11	3	2019-10-05 04:15:00
2480	315	11	3	2019-01-29 18:15:00
2481	315	11	3	2019-01-26 01:45:00
2482	315	11	3	2019-01-27 22:45:00
2483	315	11	3	2019-12-18 03:45:00
2484	315	11	3	2019-09-25 04:00:00
2485	315	11	3	2020-05-03 08:30:00
2486	315	11	3	2019-05-24 10:45:00
2487	315	11	3	2020-07-16 18:15:00
2488	316	18	2	2018-08-29 12:30:00
2489	316	18	2	2019-06-06 23:15:00
2490	316	18	2	2018-11-10 00:45:00
2491	316	18	2	2018-03-04 06:15:00
2492	316	18	2	2019-07-15 15:15:00
2493	316	18	2	2019-07-07 19:00:00
2494	316	18	2	2019-01-28 22:30:00
2495	316	18	2	2018-07-02 20:45:00
2496	316	18	2	2018-03-01 19:00:00
2497	316	18	2	2019-10-01 19:00:00
2498	316	18	2	2019-09-28 21:00:00
2499	316	18	2	2019-10-18 14:00:00
2500	316	18	2	2018-12-11 00:30:00
2501	317	17	17	2017-10-15 18:00:00
2502	317	17	17	2019-01-10 18:15:00
2503	317	17	17	2019-08-18 18:30:00
2504	317	17	17	2018-09-21 20:30:00
2505	317	17	17	2019-07-21 11:30:00
2506	317	17	17	2018-10-27 09:15:00
2507	317	17	17	2018-05-04 20:15:00
2508	317	17	17	2019-09-24 23:00:00
2509	317	17	17	2018-03-06 09:00:00
2510	317	17	17	2019-05-05 21:00:00
2511	318	4	14	2019-05-19 20:30:00
2512	318	4	14	2018-05-08 16:15:00
2513	318	4	14	2018-05-01 19:15:00
2514	318	4	14	2020-01-23 19:00:00
2515	318	4	14	2020-02-05 05:30:00
2516	318	4	14	2019-03-24 07:15:00
2517	318	4	14	2019-04-13 05:45:00
2518	318	4	14	2019-10-04 15:45:00
2519	318	4	14	2019-10-11 01:30:00
2520	319	10	3	2020-12-11 04:30:00
2521	319	10	3	2020-09-07 15:45:00
2522	320	12	9	2021-07-05 19:00:00
2523	321	13	11	2020-10-13 12:45:00
2524	321	13	11	2019-07-06 20:30:00
2525	321	13	11	2021-01-05 13:00:00
2526	322	14	18	2019-03-30 11:45:00
2527	322	14	18	2017-06-28 07:30:00
2528	322	14	18	2017-05-12 08:45:00
2529	322	14	18	2017-06-08 16:45:00
2530	322	14	18	2019-02-08 00:30:00
2531	322	14	18	2018-05-22 23:15:00
2532	322	14	18	2019-01-15 02:30:00
2533	322	14	18	2017-10-12 21:15:00
2534	323	5	14	2019-01-18 03:00:00
2535	323	5	14	2019-07-22 01:00:00
2536	323	5	14	2017-11-29 22:30:00
2537	323	5	14	2017-12-30 21:30:00
2538	323	5	14	2019-07-08 19:00:00
2539	324	5	1	2017-11-26 06:15:00
2540	324	5	1	2019-05-01 22:15:00
2541	324	5	1	2019-03-16 18:15:00
2542	324	5	1	2018-06-11 17:30:00
2543	324	5	1	2018-03-26 09:00:00
2544	325	1	15	2019-02-25 23:00:00
2545	325	1	15	2020-11-27 18:45:00
2546	325	1	15	2019-11-15 07:15:00
2547	325	1	15	2019-03-24 00:00:00
2548	325	1	15	2019-02-04 05:30:00
2549	325	1	15	2019-05-07 04:15:00
2550	325	1	15	2021-01-22 07:00:00
2551	325	1	15	2019-08-15 01:45:00
2552	325	1	15	2019-07-03 02:45:00
2553	325	1	15	2020-09-20 23:30:00
2554	325	1	15	2019-05-10 02:15:00
2555	325	1	15	2019-03-11 13:00:00
2556	325	1	15	2020-04-27 10:00:00
2557	326	15	11	2020-10-28 06:15:00
2558	326	15	11	2020-05-16 22:00:00
2559	326	15	11	2020-02-12 16:30:00
2560	326	15	11	2021-04-27 05:00:00
2561	327	17	8	2019-02-14 22:30:00
2562	327	17	8	2019-05-10 02:15:00
2563	327	17	8	2019-12-21 07:30:00
2564	327	17	8	2020-04-26 14:00:00
2565	327	17	8	2019-09-18 22:00:00
2566	327	17	8	2020-04-08 00:30:00
2567	327	17	8	2020-12-22 10:15:00
2568	328	2	17	2019-03-03 15:45:00
2569	328	2	17	2019-12-19 16:00:00
2570	328	2	17	2019-05-19 05:45:00
2571	328	2	17	2019-07-15 22:15:00
2572	328	2	17	2018-12-20 08:00:00
2573	328	2	17	2020-02-10 19:45:00
2574	328	2	17	2018-05-26 23:45:00
2575	328	2	17	2020-02-08 14:45:00
2576	328	2	17	2018-08-23 16:45:00
2577	329	7	4	2020-03-16 04:45:00
2578	329	7	4	2019-06-11 10:30:00
2579	329	7	4	2019-09-07 22:00:00
2580	329	7	4	2019-11-29 14:15:00
2581	329	7	4	2018-12-03 08:00:00
2582	329	7	4	2018-04-21 11:15:00
2583	329	7	4	2018-08-12 02:30:00
2584	329	7	4	2019-02-23 05:30:00
2585	329	7	4	2018-11-18 21:30:00
2586	329	7	4	2018-10-26 14:15:00
2587	329	7	4	2019-05-25 00:30:00
2588	330	1	10	2018-03-28 09:45:00
2589	330	1	10	2018-03-26 23:30:00
2590	330	1	10	2017-07-16 08:00:00
2591	330	1	10	2017-07-10 08:00:00
2592	330	1	10	2018-04-21 08:45:00
2593	330	1	10	2018-09-22 06:30:00
2594	330	1	10	2018-06-02 08:15:00
2595	330	1	10	2018-06-05 03:00:00
2596	330	1	10	2018-12-01 17:00:00
2597	330	1	10	2017-12-13 19:15:00
2598	330	1	10	2018-05-01 20:15:00
2599	330	1	10	2017-11-14 15:00:00
2600	330	1	10	2018-06-20 09:00:00
2601	330	1	10	2018-09-01 22:30:00
2602	331	12	10	2019-02-23 04:45:00
2603	331	12	10	2018-03-23 05:00:00
2604	331	12	10	2017-12-18 01:00:00
2605	331	12	10	2018-10-04 08:45:00
2606	331	12	10	2018-05-28 00:30:00
2607	331	12	10	2018-12-01 10:00:00
2608	331	12	10	2017-12-14 01:15:00
2609	331	12	10	2017-09-22 13:15:00
2610	331	12	10	2019-05-06 06:30:00
2611	331	12	10	2018-07-24 08:15:00
2612	332	4	1	2021-03-14 08:45:00
2613	332	4	1	2020-09-28 10:45:00
2614	332	4	1	2019-09-16 04:00:00
2615	333	13	2	2019-12-04 16:45:00
2616	333	13	2	2019-08-17 02:15:00
2617	333	13	2	2020-02-14 07:45:00
2618	333	13	2	2019-10-24 02:45:00
2619	333	13	2	2018-09-26 05:45:00
2620	333	13	2	2019-12-17 16:00:00
2621	333	13	2	2019-07-18 23:15:00
2622	333	13	2	2018-11-25 05:45:00
2623	333	13	2	2019-09-25 19:30:00
2624	333	13	2	2020-04-22 01:15:00
2625	333	13	2	2019-12-27 18:45:00
2626	333	13	2	2020-06-20 08:00:00
2627	334	16	12	2017-09-07 22:45:00
2628	334	16	12	2018-05-03 09:15:00
2629	334	16	12	2017-08-25 14:00:00
2630	334	16	12	2018-04-14 01:30:00
2631	334	16	12	2017-06-22 16:00:00
2632	334	16	12	2017-02-21 22:15:00
2633	334	16	12	2017-02-19 00:30:00
2634	334	16	12	2017-08-12 08:00:00
2635	334	16	12	2017-06-13 13:45:00
2636	334	16	12	2019-01-17 04:45:00
2637	335	9	2	2019-05-15 13:30:00
2638	335	9	2	2019-03-28 16:00:00
2639	335	9	2	2018-08-04 03:45:00
2640	335	9	2	2017-10-30 03:15:00
2641	335	9	2	2019-01-08 13:00:00
2642	335	9	2	2019-09-12 11:15:00
2643	335	9	2	2018-09-16 18:15:00
2644	335	9	2	2018-07-07 01:30:00
2645	335	9	2	2018-06-04 10:00:00
2646	335	9	2	2017-12-07 04:00:00
2647	335	9	2	2018-09-03 06:30:00
2648	335	9	2	2018-11-02 16:30:00
2649	335	9	2	2018-11-08 12:45:00
2650	335	9	2	2019-06-16 06:00:00
2651	336	15	1	2018-12-06 15:45:00
2652	336	15	1	2020-01-13 15:15:00
2653	336	15	1	2019-05-14 22:30:00
2654	336	15	1	2020-06-18 02:45:00
2655	336	15	1	2020-02-02 04:00:00
2656	336	15	1	2019-05-12 02:30:00
2657	337	2	4	2019-06-02 16:45:00
2658	337	2	4	2019-10-19 19:00:00
2659	337	2	4	2020-02-10 16:00:00
2660	337	2	4	2019-05-11 05:00:00
2661	337	2	4	2020-05-02 02:45:00
2662	337	2	4	2019-09-05 07:30:00
2663	337	2	4	2020-12-08 08:45:00
2664	337	2	4	2019-11-12 20:00:00
2665	337	2	4	2020-08-09 23:45:00
2666	337	2	4	2019-06-10 22:15:00
2667	337	2	4	2020-06-03 11:45:00
2668	337	2	4	2020-05-25 04:45:00
2669	338	8	5	2020-06-08 01:30:00
2670	338	8	5	2020-01-27 10:30:00
2671	338	8	5	2019-09-19 09:00:00
2672	338	8	5	2018-08-20 07:45:00
2673	338	8	5	2018-11-15 17:00:00
2674	338	8	5	2019-02-22 19:30:00
2675	339	11	11	2017-11-12 16:00:00
2676	339	11	11	2018-02-03 11:30:00
2677	339	11	11	2018-05-16 17:00:00
2678	339	11	11	2017-12-09 00:30:00
2679	339	11	11	2018-05-14 07:45:00
2680	339	11	11	2018-01-28 08:15:00
2681	339	11	11	2018-08-14 07:30:00
2682	339	11	11	2019-01-22 10:00:00
2683	339	11	11	2017-10-27 04:15:00
2684	340	2	17	2018-12-03 01:15:00
2685	340	2	17	2019-04-27 17:30:00
2686	340	2	17	2019-04-11 15:00:00
2687	340	2	17	2019-02-22 23:15:00
2688	340	2	17	2019-02-06 03:30:00
2689	340	2	17	2020-02-15 07:00:00
2690	340	2	17	2018-05-18 08:30:00
2691	340	2	17	2019-05-10 07:15:00
2692	340	2	17	2018-03-22 05:00:00
2693	340	2	17	2019-09-11 18:45:00
2694	341	18	14	2019-11-05 23:30:00
2695	341	18	14	2019-06-05 20:15:00
2696	341	18	14	2017-12-28 18:30:00
2697	342	16	10	2020-06-10 10:45:00
2698	342	16	10	2021-08-07 01:15:00
2699	342	16	10	2020-12-07 14:15:00
2700	342	16	10	2021-04-16 14:15:00
2701	342	16	10	2021-10-22 21:15:00
2702	342	16	10	2019-12-16 14:45:00
2703	342	16	10	2021-04-12 23:30:00
2704	343	20	8	2018-09-29 23:00:00
2705	344	13	6	2020-12-19 11:00:00
2706	345	5	12	2019-02-01 23:00:00
2707	345	5	12	2019-12-02 04:30:00
2708	345	5	12	2019-04-14 04:30:00
2709	345	5	12	2020-11-08 11:15:00
2710	345	5	12	2020-06-12 08:45:00
2711	346	7	16	2019-12-16 22:45:00
2712	346	7	16	2019-01-18 12:00:00
2713	347	14	18	2018-11-12 23:15:00
2714	347	14	18	2019-02-25 02:15:00
2715	347	14	18	2020-05-16 12:45:00
2716	347	14	18	2019-03-04 01:00:00
2717	347	14	18	2019-12-25 16:45:00
2718	347	14	18	2019-01-14 19:30:00
2719	347	14	18	2019-01-21 19:30:00
2720	347	14	18	2019-10-29 08:45:00
2721	347	14	18	2019-02-11 01:45:00
2722	348	20	20	2020-03-19 17:15:00
2723	348	20	20	2018-12-17 23:15:00
2724	348	20	20	2019-01-03 12:45:00
2725	348	20	20	2019-02-08 15:45:00
2726	348	20	20	2019-02-19 15:45:00
2727	348	20	20	2019-01-11 19:30:00
2728	349	7	2	2020-10-20 14:45:00
2729	350	6	14	2019-04-17 20:30:00
2730	350	6	14	2017-07-11 00:00:00
2731	350	6	14	2018-09-20 19:15:00
2732	350	6	14	2019-04-11 16:30:00
2733	350	6	14	2017-07-20 03:15:00
2734	350	6	14	2018-08-01 13:45:00
2735	350	6	14	2017-10-10 23:30:00
2736	351	1	4	2018-12-11 18:30:00
2737	351	1	4	2019-08-19 15:30:00
2738	351	1	4	2019-04-11 11:00:00
2739	351	1	4	2019-06-13 04:45:00
2740	351	1	4	2018-12-13 07:30:00
2741	351	1	4	2019-04-10 15:15:00
2742	351	1	4	2018-10-19 05:00:00
2743	351	1	4	2018-11-13 22:15:00
2744	351	1	4	2019-02-26 07:30:00
2745	351	1	4	2019-03-11 21:00:00
2746	352	5	13	2020-12-25 09:00:00
2747	352	5	13	2021-06-27 01:15:00
2748	352	5	13	2020-12-17 15:15:00
2749	352	5	13	2020-11-02 01:15:00
2750	352	5	13	2019-08-26 15:15:00
2751	352	5	13	2020-04-25 23:30:00
2752	352	5	13	2019-08-08 06:30:00
2753	352	5	13	2019-09-15 04:00:00
2754	352	5	13	2020-05-12 03:45:00
2755	352	5	13	2021-04-21 08:15:00
2756	352	5	13	2020-04-27 12:30:00
2757	352	5	13	2021-02-05 14:15:00
2758	352	5	13	2020-02-20 21:00:00
2759	352	5	13	2020-07-10 20:15:00
2760	352	5	13	2019-10-30 05:00:00
2761	353	9	16	2018-02-09 04:00:00
2762	353	9	16	2019-08-04 22:00:00
2763	353	9	16	2018-12-27 06:45:00
2764	353	9	16	2019-05-02 10:30:00
2765	353	9	16	2019-06-28 15:45:00
2766	353	9	16	2018-05-05 04:30:00
2767	353	9	16	2017-12-01 04:00:00
2768	353	9	16	2019-03-16 06:45:00
2769	353	9	16	2019-07-08 09:30:00
2770	353	9	16	2018-09-06 09:00:00
2771	353	9	16	2018-11-04 22:45:00
2772	353	9	16	2018-05-23 00:45:00
2773	353	9	16	2018-12-25 19:30:00
2774	354	14	16	2017-06-13 09:00:00
2775	354	14	16	2018-06-04 06:15:00
2776	355	11	11	2017-08-09 07:00:00
2777	355	11	11	2017-05-09 09:45:00
2778	355	11	11	2018-06-07 14:45:00
2779	355	11	11	2017-12-23 05:30:00
2780	355	11	11	2017-03-18 21:45:00
2781	355	11	11	2017-12-27 14:30:00
2782	355	11	11	2018-04-23 06:15:00
2783	355	11	11	2018-10-23 03:45:00
2784	355	11	11	2017-12-01 12:00:00
2785	355	11	11	2019-01-10 00:45:00
2786	355	11	11	2017-07-23 02:15:00
2787	355	11	11	2018-10-14 01:00:00
2788	355	11	11	2017-05-16 05:00:00
2789	356	4	4	2019-04-07 03:45:00
2790	356	4	4	2019-01-15 20:45:00
2791	356	4	4	2019-08-17 04:45:00
2792	356	4	4	2018-07-13 13:15:00
2793	356	4	4	2019-10-07 02:30:00
2794	356	4	4	2019-01-01 05:15:00
2795	356	4	4	2019-07-10 06:45:00
2796	357	5	8	2019-12-12 11:45:00
2797	357	5	8	2021-05-06 21:45:00
2798	357	5	8	2021-05-05 06:15:00
2799	357	5	8	2019-12-07 22:45:00
2800	357	5	8	2019-12-30 18:45:00
2801	357	5	8	2020-04-22 13:15:00
2802	357	5	8	2021-08-02 16:00:00
2803	357	5	8	2021-03-04 02:30:00
2804	357	5	8	2020-08-11 08:45:00
2805	357	5	8	2020-10-01 16:30:00
2806	357	5	8	2021-01-21 15:00:00
2807	357	5	8	2019-11-23 02:30:00
2808	357	5	8	2021-07-23 13:15:00
2809	357	5	8	2021-01-01 04:00:00
2810	358	19	13	2019-04-28 01:15:00
2811	358	19	13	2019-09-06 00:30:00
2812	359	16	17	2018-02-21 12:30:00
2813	359	16	17	2019-01-18 12:15:00
2814	359	16	17	2017-02-20 05:30:00
2815	359	16	17	2017-04-22 13:45:00
2816	359	16	17	2018-02-08 12:30:00
2817	359	16	17	2017-06-30 11:30:00
2818	359	16	17	2017-04-11 12:45:00
2819	359	16	17	2017-06-20 20:15:00
2820	359	16	17	2018-01-27 07:30:00
2821	359	16	17	2018-04-24 23:45:00
2822	359	16	17	2018-12-02 11:15:00
2823	359	16	17	2018-04-23 07:45:00
2824	359	16	17	2018-03-04 17:30:00
2825	359	16	17	2018-07-13 11:30:00
2826	360	4	7	2019-02-02 03:45:00
2827	360	4	7	2017-03-29 20:30:00
2828	360	4	7	2019-02-17 06:00:00
2829	360	4	7	2018-07-12 09:30:00
2830	360	4	7	2018-04-23 00:15:00
2831	360	4	7	2018-11-15 07:30:00
2832	360	4	7	2017-05-19 01:30:00
2833	360	4	7	2018-05-22 15:15:00
2834	360	4	7	2018-01-18 12:15:00
2835	361	5	10	2019-12-23 05:45:00
2836	361	5	10	2018-12-14 17:15:00
2837	361	5	10	2018-11-16 09:00:00
2838	361	5	10	2019-12-05 07:15:00
2839	361	5	10	2020-06-17 14:00:00
2840	361	5	10	2018-11-02 08:30:00
2841	361	5	10	2018-08-30 14:00:00
2842	361	5	10	2019-05-21 03:00:00
2843	361	5	10	2019-01-17 18:15:00
2844	361	5	10	2019-05-09 04:00:00
2845	362	16	7	2020-01-17 14:45:00
2846	362	16	7	2019-11-08 23:45:00
2847	362	16	7	2019-04-14 14:00:00
2848	362	16	7	2019-07-03 09:30:00
2849	362	16	7	2019-09-17 19:00:00
2850	363	1	9	2019-07-21 14:45:00
2851	363	1	9	2020-11-07 19:45:00
2852	363	1	9	2020-03-14 23:15:00
2853	363	1	9	2020-09-03 14:15:00
2854	363	1	9	2020-10-13 23:15:00
2855	363	1	9	2020-10-16 06:30:00
2856	363	1	9	2020-05-03 06:45:00
2857	363	1	9	2020-03-03 09:45:00
2858	363	1	9	2020-01-14 00:15:00
2859	363	1	9	2020-11-20 03:45:00
2860	363	1	9	2019-03-12 06:30:00
2861	364	15	3	2021-04-21 14:15:00
2862	364	15	3	2020-09-02 06:45:00
2863	364	15	3	2019-07-04 07:45:00
2864	364	15	3	2020-02-09 08:45:00
2865	364	15	3	2020-04-18 15:30:00
2866	364	15	3	2019-12-01 13:30:00
2867	364	15	3	2020-10-26 02:45:00
2868	364	15	3	2021-01-23 02:00:00
2869	364	15	3	2020-03-24 22:45:00
2870	364	15	3	2020-02-04 18:45:00
2871	365	12	13	2019-09-26 14:45:00
2872	365	12	13	2020-11-23 17:15:00
2873	365	12	13	2019-08-05 17:30:00
2874	365	12	13	2019-07-19 22:45:00
2875	365	12	13	2021-03-26 00:15:00
2876	365	12	13	2021-05-08 12:45:00
2877	365	12	13	2021-05-07 13:00:00
2878	365	12	13	2020-10-18 13:45:00
2879	366	7	3	2018-04-08 18:30:00
2880	367	18	1	2017-04-29 18:00:00
2881	367	18	1	2017-07-01 16:00:00
2882	367	18	1	2018-07-05 23:45:00
2883	367	18	1	2017-10-29 04:00:00
2884	367	18	1	2019-02-17 18:45:00
2885	367	18	1	2018-08-09 02:30:00
2886	367	18	1	2017-08-18 18:30:00
2887	367	18	1	2017-06-27 04:45:00
2888	367	18	1	2017-12-11 16:30:00
2889	367	18	1	2018-09-29 07:30:00
2890	368	12	11	2019-01-25 11:30:00
2891	368	12	11	2018-10-12 20:45:00
2892	368	12	11	2018-11-17 19:00:00
2893	368	12	11	2018-11-24 03:30:00
2894	368	12	11	2017-12-19 13:00:00
2895	368	12	11	2018-12-25 08:30:00
2896	368	12	11	2018-01-09 00:30:00
2897	368	12	11	2018-01-27 05:15:00
2898	369	17	10	2021-06-08 13:30:00
2899	369	17	10	2021-04-25 16:45:00
2900	369	17	10	2020-02-04 14:00:00
2901	369	17	10	2020-08-06 22:15:00
2902	369	17	10	2020-05-27 16:30:00
2903	369	17	10	2021-06-16 06:30:00
2904	369	17	10	2021-01-23 10:00:00
2905	369	17	10	2019-07-21 11:30:00
2906	369	17	10	2020-03-03 10:45:00
2907	369	17	10	2021-01-03 13:00:00
2908	369	17	10	2020-05-11 22:00:00
2909	369	17	10	2020-01-02 05:15:00
2910	369	17	10	2021-05-12 12:45:00
2911	369	17	10	2021-04-07 21:15:00
2912	370	2	18	2019-09-04 09:45:00
2913	370	2	18	2020-08-15 15:00:00
2914	370	2	18	2020-09-19 03:45:00
2915	370	2	18	2020-03-17 09:00:00
2916	370	2	18	2019-09-30 13:30:00
2917	370	2	18	2019-10-20 04:45:00
2918	370	2	18	2020-04-07 04:45:00
2919	371	3	1	2019-06-15 06:45:00
2920	371	3	1	2018-12-26 04:30:00
2921	371	3	1	2017-10-21 20:00:00
2922	371	3	1	2017-12-24 12:45:00
2923	371	3	1	2017-11-24 00:30:00
2924	371	3	1	2017-10-29 07:30:00
2925	371	3	1	2018-04-27 00:45:00
2926	371	3	1	2018-03-20 09:45:00
2927	371	3	1	2017-07-18 20:30:00
2928	372	20	3	2020-07-21 20:30:00
2929	372	20	3	2020-11-11 05:30:00
2930	372	20	3	2020-01-02 13:00:00
2931	372	20	3	2020-01-30 18:30:00
2932	372	20	3	2019-11-04 17:15:00
2933	372	20	3	2020-01-17 07:00:00
2934	372	20	3	2020-09-26 02:00:00
2935	372	20	3	2020-12-13 07:00:00
2936	372	20	3	2021-08-20 04:45:00
2937	372	20	3	2020-10-06 20:00:00
2938	372	20	3	2020-12-29 09:30:00
2939	372	20	3	2020-02-11 16:15:00
2940	372	20	3	2021-04-15 02:15:00
2941	372	20	3	2020-07-16 13:45:00
2942	372	20	3	2021-03-25 00:30:00
2943	373	6	13	2019-12-15 08:00:00
2944	373	6	13	2020-11-13 11:45:00
2945	373	6	13	2019-11-30 02:30:00
2946	373	6	13	2020-12-19 02:30:00
2947	373	6	13	2020-08-19 06:30:00
2948	373	6	13	2019-12-01 11:15:00
2949	373	6	13	2020-02-03 11:15:00
2950	373	6	13	2020-03-14 02:45:00
2951	373	6	13	2020-08-30 14:45:00
2952	374	6	4	2020-03-29 17:15:00
2953	374	6	4	2019-10-15 07:15:00
2954	374	6	4	2020-04-12 05:00:00
2955	375	6	14	2020-05-17 21:45:00
2956	375	6	14	2020-12-16 08:15:00
2957	375	6	14	2020-06-01 10:00:00
2958	375	6	14	2021-01-30 18:15:00
2959	375	6	14	2019-06-04 10:00:00
2960	375	6	14	2020-11-26 22:45:00
2961	375	6	14	2020-10-25 12:15:00
2962	375	6	14	2019-11-18 09:30:00
2963	375	6	14	2020-04-21 10:15:00
2964	375	6	14	2021-02-15 05:00:00
2965	376	4	6	2019-04-30 20:30:00
2966	376	4	6	2019-11-24 12:00:00
2967	376	4	6	2019-06-18 20:30:00
2968	376	4	6	2018-04-11 05:45:00
2969	376	4	6	2019-08-06 20:00:00
2970	376	4	6	2018-04-02 22:30:00
2971	376	4	6	2018-10-02 09:30:00
2972	376	4	6	2018-07-30 22:00:00
2973	376	4	6	2019-07-29 10:30:00
2974	377	7	5	2020-10-12 17:45:00
2975	377	7	5	2019-09-08 00:15:00
2976	377	7	5	2020-06-22 10:30:00
2977	377	7	5	2021-02-14 09:00:00
2978	377	7	5	2019-06-17 00:45:00
2979	377	7	5	2019-06-19 08:45:00
2980	377	7	5	2021-02-11 08:15:00
2981	377	7	5	2020-02-05 12:00:00
2982	377	7	5	2020-06-24 17:45:00
2983	378	11	3	2019-04-20 08:00:00
2984	378	11	3	2019-09-30 12:15:00
2985	378	11	3	2019-05-10 02:15:00
2986	378	11	3	2018-10-12 21:15:00
2987	378	11	3	2020-04-27 05:30:00
2988	378	11	3	2019-12-19 16:00:00
2989	378	11	3	2020-01-02 16:45:00
2990	378	11	3	2020-02-21 10:30:00
2991	378	11	3	2019-08-11 09:45:00
2992	379	14	20	2021-01-25 14:00:00
2993	379	14	20	2020-09-05 07:00:00
2994	379	14	20	2021-04-26 09:00:00
2995	379	14	20	2020-12-09 01:45:00
2996	379	14	20	2021-12-02 18:00:00
2997	380	15	3	2019-07-01 19:45:00
2998	380	15	3	2021-05-29 09:00:00
2999	380	15	3	2019-07-27 17:30:00
3000	380	15	3	2021-01-05 07:45:00
3001	380	15	3	2020-05-27 13:45:00
3002	380	15	3	2020-06-15 20:30:00
3003	380	15	3	2021-01-11 13:15:00
3004	380	15	3	2021-01-05 12:45:00
3005	380	15	3	2020-06-19 09:00:00
3006	380	15	3	2020-12-10 11:45:00
3007	380	15	3	2020-05-28 06:30:00
3008	381	12	9	2017-11-29 17:45:00
3009	381	12	9	2017-09-19 09:15:00
3010	382	9	17	2020-07-14 09:15:00
3011	382	9	17	2019-12-11 04:45:00
3012	382	9	17	2021-08-25 00:45:00
3013	382	9	17	2020-11-05 07:15:00
3014	382	9	17	2021-11-30 05:00:00
3015	382	9	17	2020-08-26 23:00:00
3016	382	9	17	2020-07-29 12:30:00
3017	382	9	17	2020-06-04 06:00:00
3018	382	9	17	2021-10-02 20:45:00
3019	382	9	17	2020-05-12 01:00:00
3020	383	4	18	2019-10-04 22:15:00
3021	383	4	18	2019-04-22 07:30:00
3022	383	4	18	2020-01-11 11:00:00
3023	383	4	18	2020-07-06 11:45:00
3024	383	4	18	2019-10-02 19:00:00
3025	383	4	18	2020-07-22 12:30:00
3026	383	4	18	2019-01-11 17:30:00
3027	383	4	18	2019-03-05 02:45:00
3028	383	4	18	2020-04-21 04:45:00
3029	384	8	17	2019-01-04 15:45:00
3030	384	8	17	2019-08-28 01:45:00
3031	384	8	17	2018-03-02 18:00:00
3032	384	8	17	2017-11-28 15:00:00
3033	384	8	17	2019-02-13 06:00:00
3034	385	16	19	2019-05-21 08:30:00
3035	385	16	19	2018-05-30 06:00:00
3036	385	16	19	2020-02-06 02:45:00
3037	385	16	19	2019-06-18 21:15:00
3038	385	16	19	2019-05-01 22:15:00
3039	385	16	19	2020-01-01 09:30:00
3040	385	16	19	2018-10-24 06:30:00
3041	385	16	19	2019-03-10 20:30:00
3042	385	16	19	2018-08-03 14:45:00
3043	385	16	19	2018-05-08 15:15:00
3044	385	16	19	2018-07-29 07:15:00
3045	385	16	19	2019-03-15 03:45:00
3046	385	16	19	2019-10-07 05:30:00
3047	385	16	19	2018-10-07 12:30:00
3048	385	16	19	2018-07-17 20:00:00
3049	386	1	5	2020-06-23 12:30:00
3050	386	1	5	2021-03-07 06:30:00
3051	386	1	5	2020-10-01 16:00:00
3052	386	1	5	2020-10-19 17:00:00
3053	386	1	5	2019-12-03 16:45:00
3054	386	1	5	2020-12-02 13:45:00
3055	386	1	5	2019-10-30 14:15:00
3056	386	1	5	2021-02-03 04:00:00
3057	386	1	5	2020-03-07 07:00:00
3058	386	1	5	2021-09-09 13:15:00
3059	386	1	5	2020-11-08 11:30:00
3060	386	1	5	2021-09-02 14:30:00
3061	387	8	14	2019-09-06 10:45:00
3062	387	8	14	2018-07-19 03:00:00
3063	387	8	14	2019-12-17 05:30:00
3064	387	8	14	2019-03-14 23:45:00
3065	387	8	14	2018-04-08 06:15:00
3066	387	8	14	2019-07-09 07:00:00
3067	387	8	14	2019-11-26 14:30:00
3068	387	8	14	2019-08-21 17:30:00
3069	387	8	14	2019-08-23 09:15:00
3070	387	8	14	2019-09-11 22:15:00
3071	388	20	3	2020-07-16 21:15:00
3072	388	20	3	2019-05-18 09:00:00
3073	388	20	3	2020-04-27 21:45:00
3074	388	20	3	2020-10-18 21:30:00
3075	389	6	9	2018-04-16 08:45:00
3076	389	6	9	2019-05-01 06:00:00
3077	389	6	9	2020-01-24 17:30:00
3078	389	6	9	2018-10-15 21:30:00
3079	389	6	9	2020-01-27 07:45:00
3080	389	6	9	2019-03-28 22:00:00
3081	389	6	9	2018-10-12 08:15:00
3082	389	6	9	2019-01-06 06:30:00
3083	389	6	9	2018-08-01 06:30:00
3084	389	6	9	2018-05-19 01:00:00
3085	389	6	9	2019-06-26 19:00:00
3086	389	6	9	2019-07-04 06:30:00
3087	389	6	9	2018-12-21 05:00:00
3088	389	6	9	2018-09-01 15:00:00
3089	390	15	2	2019-05-19 15:15:00
3090	390	15	2	2019-07-22 00:30:00
3091	390	15	2	2019-08-07 08:00:00
3092	390	15	2	2020-05-15 19:15:00
3093	390	15	2	2020-04-07 20:45:00
3094	390	15	2	2018-08-05 20:15:00
3095	390	15	2	2018-09-02 11:45:00
3096	390	15	2	2018-07-23 22:45:00
3097	391	5	6	2020-02-16 13:15:00
3098	391	5	6	2019-02-16 23:30:00
3099	391	5	6	2020-05-27 14:30:00
3100	391	5	6	2019-07-26 19:00:00
3101	391	5	6	2020-07-13 17:45:00
3102	392	12	2	2019-04-12 12:15:00
3103	392	12	2	2018-10-02 03:30:00
3104	392	12	2	2020-03-24 10:00:00
3105	392	12	2	2018-11-30 07:00:00
3106	392	12	2	2020-02-03 02:15:00
3107	392	12	2	2020-03-14 09:45:00
3108	392	12	2	2019-12-04 23:00:00
3109	392	12	2	2019-05-28 04:45:00
3110	392	12	2	2020-06-01 01:00:00
3111	393	7	6	2019-05-17 00:45:00
3112	393	7	6	2020-03-15 06:00:00
3113	393	7	6	2020-01-02 00:30:00
3114	393	7	6	2020-05-01 02:00:00
3115	393	7	6	2020-06-20 00:30:00
3116	393	7	6	2019-10-27 02:45:00
3117	393	7	6	2019-12-14 03:45:00
3118	393	7	6	2019-11-17 09:15:00
3119	393	7	6	2020-06-28 17:45:00
3120	393	7	6	2019-10-10 10:30:00
3121	393	7	6	2019-12-02 15:30:00
3122	393	7	6	2018-08-16 00:00:00
3123	394	12	12	2018-06-05 18:00:00
3124	395	1	15	2020-04-26 23:15:00
3125	395	1	15	2019-04-09 16:00:00
3126	395	1	15	2019-06-24 10:00:00
3127	395	1	15	2019-10-12 03:15:00
3128	395	1	15	2018-12-28 02:45:00
3129	395	1	15	2018-07-29 14:00:00
3130	395	1	15	2020-02-10 19:45:00
3131	395	1	15	2019-10-26 07:45:00
3132	395	1	15	2018-09-19 00:00:00
3133	395	1	15	2019-01-21 04:00:00
3134	395	1	15	2018-08-30 14:15:00
3135	395	1	15	2019-12-29 19:00:00
3136	395	1	15	2019-08-19 09:45:00
3137	395	1	15	2020-03-03 09:30:00
3138	395	1	15	2018-07-26 18:15:00
3139	396	19	20	2020-01-10 08:00:00
3140	396	19	20	2019-11-17 13:00:00
3141	396	19	20	2018-08-22 23:15:00
3142	397	12	13	2018-02-23 01:30:00
3143	397	12	13	2018-05-01 05:15:00
3144	398	8	19	2021-09-29 14:15:00
3145	398	8	19	2021-05-13 09:00:00
3146	398	8	19	2020-01-30 19:45:00
3147	399	19	19	2018-09-13 18:30:00
3148	399	19	19	2017-09-07 08:45:00
3149	399	19	19	2018-11-18 18:45:00
3150	399	19	19	2017-04-08 14:00:00
3151	399	19	19	2018-04-26 11:15:00
3152	399	19	19	2017-06-24 10:30:00
3153	399	19	19	2018-10-08 18:45:00
3154	399	19	19	2017-12-22 12:45:00
3155	399	19	19	2018-08-06 17:00:00
3156	399	19	19	2017-06-26 04:30:00
3157	399	19	19	2017-09-21 14:15:00
3158	399	19	19	2018-11-21 20:15:00
3159	399	19	19	2017-12-11 06:45:00
3160	399	19	19	2018-08-30 20:30:00
3161	399	19	19	2017-07-15 06:00:00
3162	400	19	8	2019-01-03 01:45:00
3163	400	19	8	2018-10-30 03:45:00
3164	400	19	8	2019-01-27 05:45:00
3165	401	3	20	2021-03-09 15:45:00
3166	402	14	1	2019-08-07 19:00:00
3167	402	14	1	2020-01-17 05:30:00
3168	402	14	1	2018-05-30 06:30:00
3169	402	14	1	2018-05-17 04:30:00
3170	402	14	1	2018-12-23 04:30:00
3171	402	14	1	2020-02-27 21:00:00
3172	402	14	1	2019-07-18 21:00:00
3173	402	14	1	2019-06-05 11:15:00
3174	402	14	1	2019-07-12 11:15:00
3175	403	17	11	2020-05-28 03:45:00
3176	403	17	11	2021-06-11 05:15:00
3177	403	17	11	2020-01-28 00:30:00
3178	403	17	11	2020-12-03 19:45:00
3179	403	17	11	2020-07-03 15:15:00
3180	403	17	11	2020-06-25 13:45:00
3181	403	17	11	2020-05-28 11:00:00
3182	403	17	11	2020-07-05 05:30:00
3183	404	16	12	2020-09-05 23:30:00
3184	404	16	12	2020-02-20 22:15:00
3185	404	16	12	2020-10-12 01:45:00
3186	404	16	12	2020-02-01 04:30:00
3187	404	16	12	2020-03-18 16:45:00
3188	405	15	13	2020-01-21 08:30:00
3189	406	1	20	2017-12-10 09:00:00
3190	406	1	20	2017-03-18 21:30:00
3191	406	1	20	2017-05-20 20:45:00
3192	406	1	20	2017-07-08 21:30:00
3193	406	1	20	2017-06-29 05:00:00
3194	406	1	20	2018-04-01 23:00:00
3195	407	14	16	2019-03-06 16:30:00
3196	407	14	16	2018-06-12 16:30:00
3197	407	14	16	2019-09-30 08:15:00
3198	407	14	16	2019-02-19 14:45:00
3199	407	14	16	2018-05-06 18:15:00
3200	408	20	20	2021-08-09 16:30:00
3201	408	20	20	2021-06-26 10:30:00
3202	408	20	20	2020-06-22 17:30:00
3203	408	20	20	2021-06-11 01:45:00
3204	408	20	20	2021-09-17 18:45:00
3205	408	20	20	2020-03-02 21:45:00
3206	408	20	20	2021-09-04 09:15:00
3207	408	20	20	2020-01-09 05:30:00
3208	409	3	13	2017-07-28 22:00:00
3209	409	3	13	2017-08-03 12:00:00
3210	409	3	13	2018-04-06 10:00:00
3211	409	3	13	2019-02-02 20:15:00
3212	409	3	13	2018-06-29 00:15:00
3213	409	3	13	2017-06-22 19:45:00
3214	409	3	13	2018-07-03 07:15:00
3215	409	3	13	2017-06-11 14:45:00
3216	409	3	13	2017-07-11 19:00:00
3217	409	3	13	2019-02-11 11:00:00
3218	409	3	13	2017-08-09 16:30:00
3219	410	1	20	2019-02-13 15:30:00
3220	410	1	20	2018-05-03 14:30:00
3221	410	1	20	2018-05-01 20:30:00
3222	410	1	20	2018-10-20 23:15:00
3223	410	1	20	2018-11-12 10:00:00
3224	410	1	20	2018-05-24 20:30:00
3225	410	1	20	2019-07-20 03:15:00
3226	410	1	20	2018-04-23 12:00:00
3227	411	20	19	2021-04-27 20:45:00
3228	411	20	19	2021-10-09 07:15:00
3229	411	20	19	2020-12-19 22:15:00
3230	411	20	19	2020-11-04 22:15:00
3231	411	20	19	2021-12-22 14:00:00
3232	411	20	19	2020-09-15 15:00:00
3233	412	6	10	2019-08-06 05:45:00
3234	412	6	10	2018-02-02 21:00:00
3235	412	6	10	2018-04-04 10:15:00
3236	412	6	10	2018-01-22 13:00:00
3237	412	6	10	2019-07-21 06:30:00
3238	412	6	10	2019-04-20 02:30:00
3239	412	6	10	2019-07-19 08:30:00
3240	413	20	9	2021-04-16 04:30:00
3241	413	20	9	2021-09-29 04:30:00
3242	413	20	9	2021-09-02 11:45:00
3243	413	20	9	2020-01-06 07:45:00
3244	413	20	9	2021-03-04 05:45:00
3245	413	20	9	2021-04-24 05:45:00
3246	413	20	9	2020-08-28 01:15:00
3247	413	20	9	2021-01-09 08:00:00
3248	413	20	9	2021-08-23 20:30:00
3249	414	14	5	2018-05-03 10:30:00
3250	414	14	5	2018-07-21 10:45:00
3251	414	14	5	2018-04-14 09:15:00
3252	414	14	5	2017-12-03 13:15:00
3253	414	14	5	2017-07-30 06:30:00
3254	414	14	5	2017-07-09 04:00:00
3255	414	14	5	2017-08-24 04:45:00
3256	414	14	5	2017-08-03 01:15:00
3257	414	14	5	2018-03-11 07:30:00
3258	414	14	5	2019-03-20 08:30:00
3259	414	14	5	2018-03-28 08:00:00
3260	415	6	20	2020-01-28 02:00:00
3261	415	6	20	2019-07-05 00:00:00
3262	415	6	20	2019-12-20 15:45:00
3263	415	6	20	2019-01-26 12:30:00
3264	416	17	14	2020-05-08 22:30:00
3265	416	17	14	2019-10-09 06:45:00
3266	417	10	16	2019-10-25 07:45:00
3267	417	10	16	2019-02-03 08:30:00
3268	417	10	16	2019-12-22 07:45:00
3269	417	10	16	2020-01-21 15:45:00
3270	417	10	16	2019-05-13 03:30:00
3271	417	10	16	2018-11-29 18:30:00
3272	417	10	16	2018-12-23 01:30:00
3273	417	10	16	2018-10-14 16:00:00
3274	417	10	16	2019-04-14 02:15:00
3275	417	10	16	2019-01-07 11:30:00
3276	417	10	16	2019-03-04 01:15:00
3277	417	10	16	2019-03-26 00:00:00
3278	417	10	16	2019-10-21 23:15:00
3279	417	10	16	2019-09-18 15:45:00
3280	417	10	16	2019-12-24 19:45:00
3281	418	13	7	2019-08-15 15:00:00
3282	418	13	7	2018-08-10 20:45:00
3283	418	13	7	2018-10-19 12:45:00
3284	418	13	7	2019-02-06 15:00:00
3285	418	13	7	2018-05-24 03:30:00
3286	418	13	7	2019-02-15 08:45:00
3287	419	2	2	2019-08-27 19:15:00
3288	419	2	2	2019-10-08 07:45:00
3289	419	2	2	2019-10-02 19:45:00
3290	419	2	2	2019-07-11 17:45:00
3291	419	2	2	2019-01-14 18:00:00
3292	419	2	2	2019-05-22 11:00:00
3293	419	2	2	2019-09-11 20:30:00
3294	419	2	2	2018-12-18 19:45:00
3295	419	2	2	2020-05-09 16:15:00
3296	419	2	2	2019-09-29 18:00:00
3297	419	2	2	2020-05-23 00:15:00
3298	419	2	2	2020-10-03 17:30:00
3299	419	2	2	2019-07-08 12:00:00
3300	419	2	2	2019-08-25 03:15:00
3301	420	15	15	2021-06-23 22:00:00
3302	420	15	15	2019-07-10 01:15:00
3303	420	15	15	2021-04-11 12:30:00
3304	420	15	15	2020-10-18 10:30:00
3305	420	15	15	2020-10-09 09:00:00
3306	421	15	6	2019-04-03 12:15:00
3307	421	15	6	2018-11-30 04:15:00
3308	421	15	6	2019-03-05 23:15:00
3309	421	15	6	2019-01-25 13:30:00
3310	422	12	9	2018-05-23 12:15:00
3311	422	12	9	2018-03-30 10:45:00
3312	422	12	9	2018-06-05 11:30:00
3313	422	12	9	2018-11-14 02:45:00
3314	423	2	7	2017-12-03 06:30:00
3315	423	2	7	2018-11-21 06:45:00
3316	423	2	7	2018-12-23 14:30:00
3317	423	2	7	2018-12-25 07:00:00
3318	423	2	7	2018-05-25 02:15:00
3319	423	2	7	2018-02-06 04:45:00
3320	423	2	7	2018-06-18 08:45:00
3321	423	2	7	2019-04-16 03:45:00
3322	423	2	7	2018-01-29 03:45:00
3323	423	2	7	2018-01-11 13:15:00
3324	423	2	7	2018-12-12 22:30:00
3325	424	16	5	2019-01-16 01:45:00
3326	424	16	5	2018-05-19 19:00:00
3327	424	16	5	2019-02-26 12:00:00
3328	424	16	5	2019-04-06 13:45:00
3329	424	16	5	2019-11-18 07:30:00
3330	424	16	5	2020-03-15 13:30:00
3331	424	16	5	2018-08-25 02:15:00
3332	424	16	5	2019-01-07 23:00:00
3333	425	3	17	2019-10-01 03:00:00
3334	425	3	17	2019-10-25 21:00:00
3335	425	3	17	2019-05-29 11:30:00
3336	425	3	17	2019-01-09 21:15:00
3337	425	3	17	2020-03-13 06:30:00
3338	425	3	17	2019-08-18 09:00:00
3339	425	3	17	2018-12-08 00:15:00
3340	425	3	17	2018-11-13 20:00:00
3341	425	3	17	2019-05-22 13:00:00
3342	425	3	17	2020-06-15 23:30:00
3343	426	9	14	2020-07-15 21:45:00
3344	426	9	14	2019-02-12 19:45:00
3345	426	9	14	2020-11-30 08:45:00
3346	426	9	14	2019-10-14 19:15:00
3347	426	9	14	2018-12-05 00:15:00
3348	426	9	14	2020-08-05 15:15:00
3349	426	9	14	2020-11-22 21:30:00
3350	426	9	14	2019-03-03 13:45:00
3351	426	9	14	2020-07-02 18:00:00
3352	426	9	14	2020-11-21 19:00:00
3353	426	9	14	2020-08-03 05:45:00
3354	426	9	14	2020-11-17 18:00:00
3355	426	9	14	2019-04-02 01:00:00
3356	427	5	14	2020-09-19 13:45:00
3357	427	5	14	2019-11-26 17:45:00
3358	427	5	14	2020-03-21 16:00:00
3359	427	5	14	2019-11-30 14:15:00
3360	427	5	14	2020-05-27 10:30:00
3361	427	5	14	2019-09-03 15:15:00
3362	427	5	14	2019-05-13 05:45:00
3363	427	5	14	2018-10-14 13:45:00
3364	428	7	19	2019-05-03 01:45:00
3365	428	7	19	2020-02-02 11:30:00
3366	428	7	19	2019-09-26 07:15:00
3367	428	7	19	2019-02-11 09:30:00
3368	428	7	19	2019-02-16 15:30:00
3369	428	7	19	2019-07-01 22:45:00
3370	428	7	19	2020-04-13 13:00:00
3371	428	7	19	2020-03-23 23:30:00
3372	428	7	19	2019-12-22 16:15:00
3373	429	8	1	2019-12-13 18:45:00
3374	429	8	1	2018-03-01 13:30:00
3375	429	8	1	2019-10-02 22:00:00
3376	429	8	1	2018-06-25 12:45:00
3377	429	8	1	2018-11-13 18:45:00
3378	429	8	1	2019-08-26 05:00:00
3379	429	8	1	2019-12-05 13:15:00
3380	429	8	1	2019-07-25 08:15:00
3381	429	8	1	2018-10-30 07:30:00
3382	429	8	1	2019-12-16 08:00:00
3383	430	11	20	2019-03-06 17:15:00
3384	430	11	20	2020-03-05 22:00:00
3385	430	11	20	2020-02-15 01:00:00
3386	430	11	20	2020-09-30 16:30:00
3387	430	11	20	2020-09-13 08:30:00
3388	430	11	20	2019-11-04 23:45:00
3389	431	8	17	2020-03-23 01:45:00
3390	431	8	17	2020-04-28 16:15:00
3391	432	12	12	2021-02-23 06:00:00
3392	432	12	12	2019-06-22 01:30:00
3393	432	12	12	2019-06-23 08:00:00
3394	432	12	12	2019-09-06 17:30:00
3395	432	12	12	2020-09-20 00:45:00
3396	432	12	12	2020-07-21 23:15:00
3397	432	12	12	2019-12-18 22:30:00
3398	432	12	12	2019-11-23 11:00:00
3399	432	12	12	2019-12-25 03:30:00
3400	432	12	12	2020-05-17 01:00:00
3401	432	12	12	2021-02-13 10:00:00
3402	433	13	12	2018-01-21 22:30:00
3403	433	13	12	2018-11-19 17:00:00
3404	433	13	12	2018-01-07 03:30:00
3405	433	13	12	2018-04-15 06:15:00
3406	433	13	12	2017-11-29 14:45:00
3407	433	13	12	2018-03-09 00:30:00
3408	433	13	12	2017-08-20 01:45:00
3409	433	13	12	2018-05-26 10:30:00
3410	434	3	12	2018-12-10 12:15:00
3411	434	3	12	2018-11-08 15:45:00
3412	434	3	12	2018-10-15 21:45:00
3413	434	3	12	2019-10-07 08:15:00
3414	434	3	12	2018-04-10 08:15:00
3415	434	3	12	2019-12-14 06:45:00
3416	434	3	12	2018-09-15 07:30:00
3417	434	3	12	2020-01-14 22:00:00
3418	434	3	12	2019-05-25 06:45:00
3419	434	3	12	2019-01-15 01:30:00
3420	434	3	12	2019-02-26 11:45:00
3421	434	3	12	2019-11-25 18:45:00
3422	434	3	12	2018-08-07 02:45:00
3423	434	3	12	2018-10-01 19:45:00
3424	434	3	12	2019-04-18 21:15:00
3425	435	8	17	2017-09-20 00:30:00
3426	435	8	17	2018-04-01 13:30:00
3427	435	8	17	2017-10-13 20:15:00
3428	436	12	5	2018-09-04 18:15:00
3429	436	12	5	2018-12-23 23:15:00
3430	436	12	5	2020-02-12 02:00:00
3431	436	12	5	2019-11-25 23:45:00
3432	436	12	5	2018-03-13 21:00:00
3433	436	12	5	2020-02-13 06:45:00
3434	436	12	5	2019-01-04 00:15:00
3435	436	12	5	2019-07-11 08:00:00
3436	436	12	5	2019-12-23 19:15:00
3437	436	12	5	2019-05-24 03:15:00
3438	436	12	5	2019-07-20 09:15:00
3439	436	12	5	2019-12-03 22:15:00
3440	436	12	5	2019-06-28 00:15:00
3441	436	12	5	2018-11-03 05:45:00
3442	437	1	10	2019-08-20 19:00:00
3443	437	1	10	2019-02-12 18:15:00
3444	437	1	10	2020-07-20 10:45:00
3445	437	1	10	2019-02-07 17:15:00
3446	437	1	10	2019-10-12 15:15:00
3447	437	1	10	2020-02-02 01:15:00
3448	437	1	10	2019-10-05 21:15:00
3449	437	1	10	2019-08-12 13:00:00
3450	437	1	10	2019-06-29 10:00:00
3451	437	1	10	2020-06-17 21:30:00
3452	437	1	10	2019-02-21 05:00:00
3453	437	1	10	2019-07-03 01:45:00
3454	437	1	10	2019-06-01 21:15:00
3455	437	1	10	2019-05-26 20:30:00
3456	437	1	10	2019-11-17 10:30:00
3457	438	1	2	2020-07-21 20:00:00
3458	438	1	2	2019-03-09 19:15:00
3459	439	14	7	2020-01-17 23:30:00
3460	439	14	7	2020-05-22 09:00:00
3461	439	14	7	2020-06-10 06:30:00
3462	439	14	7	2020-04-29 09:00:00
3463	439	14	7	2020-12-06 03:45:00
3464	439	14	7	2019-09-27 11:45:00
3465	439	14	7	2020-06-27 12:15:00
3466	439	14	7	2019-06-07 01:00:00
3467	439	14	7	2019-09-01 16:00:00
3468	440	7	4	2018-11-13 10:45:00
3469	440	7	4	2019-04-29 07:45:00
3470	440	7	4	2020-08-27 00:45:00
3471	440	7	4	2020-06-03 19:00:00
3472	440	7	4	2019-04-13 11:45:00
3473	440	7	4	2020-02-24 04:15:00
3474	440	7	4	2018-10-07 12:15:00
3475	440	7	4	2018-12-21 14:30:00
3476	440	7	4	2019-08-06 23:15:00
3477	440	7	4	2019-06-14 02:15:00
3478	440	7	4	2019-04-17 03:45:00
3479	440	7	4	2019-02-11 06:45:00
3480	440	7	4	2020-04-23 07:45:00
3481	440	7	4	2020-09-01 05:15:00
3482	440	7	4	2020-03-18 06:00:00
3483	441	14	9	2019-12-30 10:45:00
3484	441	14	9	2021-06-28 22:15:00
3485	442	9	16	2019-11-07 03:15:00
3486	442	9	16	2019-08-22 16:00:00
3487	442	9	16	2019-10-04 18:00:00
3488	442	9	16	2019-06-28 21:30:00
3489	443	1	3	2020-08-15 14:45:00
3490	443	1	3	2021-03-22 01:15:00
3491	443	1	3	2019-10-26 18:30:00
3492	443	1	3	2020-10-29 03:30:00
3493	443	1	3	2020-09-13 17:30:00
3494	443	1	3	2020-11-11 21:30:00
3495	443	1	3	2020-05-22 06:00:00
3496	443	1	3	2020-01-05 01:45:00
3497	443	1	3	2021-01-06 03:00:00
3498	443	1	3	2019-09-04 11:45:00
3499	443	1	3	2020-06-28 10:30:00
3500	443	1	3	2021-01-24 19:15:00
3501	443	1	3	2020-06-14 04:15:00
3502	443	1	3	2020-05-25 15:00:00
3503	444	6	11	2019-01-30 22:45:00
3504	444	6	11	2019-01-03 19:30:00
3505	444	6	11	2018-09-17 19:00:00
3506	444	6	11	2019-01-26 01:30:00
3507	444	6	11	2019-09-28 20:45:00
3508	444	6	11	2018-01-16 08:30:00
3509	444	6	11	2018-05-26 07:00:00
3510	444	6	11	2018-05-28 11:45:00
3511	444	6	11	2019-07-22 00:00:00
3512	444	6	11	2018-06-19 12:00:00
3513	444	6	11	2018-12-25 02:15:00
3514	444	6	11	2019-02-01 18:30:00
3515	444	6	11	2019-03-11 23:15:00
3516	445	17	1	2018-02-01 21:15:00
3517	445	17	1	2018-01-03 15:00:00
3518	445	17	1	2019-02-18 11:30:00
3519	445	17	1	2018-08-22 03:45:00
3520	445	17	1	2018-05-29 14:45:00
3521	445	17	1	2019-05-18 10:30:00
3522	445	17	1	2018-12-04 12:00:00
3523	445	17	1	2018-01-14 14:15:00
3524	445	17	1	2018-12-13 11:45:00
3525	445	17	1	2018-07-18 10:00:00
3526	446	2	3	2018-04-17 17:00:00
3527	447	13	18	2018-01-24 13:30:00
3528	447	13	18	2018-08-14 10:15:00
3529	447	13	18	2019-04-25 08:30:00
3530	447	13	18	2019-07-27 03:45:00
3531	447	13	18	2019-07-13 15:45:00
3532	447	13	18	2019-05-29 22:00:00
3533	448	16	4	2018-07-11 20:45:00
3534	448	16	4	2019-02-07 04:45:00
3535	448	16	4	2020-05-19 00:15:00
3536	448	16	4	2019-09-23 08:45:00
3537	448	16	4	2019-10-28 19:30:00
3538	448	16	4	2019-09-24 05:30:00
3539	448	16	4	2018-08-24 16:00:00
3540	448	16	4	2019-09-05 12:15:00
3541	448	16	4	2019-06-28 13:00:00
3542	449	1	10	2018-09-07 10:00:00
3543	449	1	10	2018-09-24 07:30:00
3544	449	1	10	2018-01-24 17:15:00
3545	449	1	10	2019-05-21 09:45:00
3546	449	1	10	2018-10-19 15:15:00
3547	449	1	10	2018-12-29 11:30:00
3548	449	1	10	2019-02-24 08:00:00
3549	449	1	10	2019-02-21 16:15:00
3550	449	1	10	2019-03-02 20:45:00
3551	450	17	7	2019-07-17 00:30:00
3552	450	17	7	2018-07-15 08:00:00
3553	450	17	7	2019-11-29 00:45:00
3554	450	17	7	2019-03-28 23:30:00
3555	450	17	7	2019-01-13 02:30:00
3556	450	17	7	2019-07-08 01:15:00
3557	450	17	7	2019-07-11 12:15:00
3558	450	17	7	2019-09-27 12:45:00
3559	450	17	7	2018-06-23 22:15:00
3560	450	17	7	2019-06-09 17:00:00
3561	451	13	14	2020-09-19 01:15:00
3562	451	13	14	2020-05-30 23:30:00
3563	451	13	14	2020-05-25 10:00:00
3564	451	13	14	2021-03-08 03:15:00
3565	451	13	14	2021-08-09 09:15:00
3566	451	13	14	2020-02-10 20:00:00
3567	451	13	14	2019-10-13 23:15:00
3568	451	13	14	2020-09-17 05:45:00
3569	451	13	14	2020-11-22 01:45:00
3570	451	13	14	2021-07-06 09:45:00
3571	451	13	14	2021-04-28 20:00:00
3572	451	13	14	2019-10-06 15:30:00
3573	451	13	14	2021-07-29 14:15:00
3574	451	13	14	2020-12-18 21:00:00
3575	452	16	6	2021-04-01 09:15:00
3576	452	16	6	2019-10-05 14:45:00
3577	452	16	6	2021-03-12 04:45:00
3578	452	16	6	2021-01-07 14:45:00
3579	452	16	6	2019-11-18 02:30:00
3580	452	16	6	2019-12-09 07:15:00
3581	453	17	5	2020-05-25 10:45:00
3582	453	17	5	2020-02-04 21:15:00
3583	453	17	5	2021-06-19 17:15:00
3584	454	20	11	2018-07-13 14:45:00
3585	454	20	11	2019-07-06 11:00:00
3586	454	20	11	2018-09-15 15:30:00
3587	454	20	11	2019-06-01 10:00:00
3588	454	20	11	2018-03-16 15:15:00
3589	454	20	11	2018-05-12 17:30:00
3590	454	20	11	2018-09-27 15:45:00
3591	454	20	11	2018-10-27 21:30:00
3592	454	20	11	2018-12-29 17:00:00
3593	454	20	11	2017-10-21 06:45:00
3594	455	7	18	2020-05-27 13:45:00
3595	455	7	18	2021-02-08 18:00:00
3596	455	7	18	2020-09-16 07:00:00
3597	456	1	15	2020-04-25 10:15:00
3598	456	1	15	2021-02-23 07:45:00
3599	456	1	15	2020-12-30 11:30:00
3600	456	1	15	2020-01-14 22:45:00
3601	456	1	15	2021-02-27 16:30:00
3602	456	1	15	2019-11-26 22:30:00
3603	456	1	15	2021-04-25 20:30:00
3604	456	1	15	2019-10-23 20:00:00
3605	456	1	15	2020-06-07 18:15:00
3606	456	1	15	2021-04-22 16:45:00
3607	457	10	4	2018-06-18 09:30:00
3608	457	10	4	2019-05-09 16:15:00
3609	457	10	4	2018-06-05 10:00:00
3610	457	10	4	2018-05-24 04:00:00
3611	457	10	4	2018-05-08 00:15:00
3612	457	10	4	2018-07-29 07:45:00
3613	458	13	7	2019-08-22 00:15:00
3614	458	13	7	2019-07-13 03:30:00
3615	458	13	7	2018-12-25 23:30:00
3616	458	13	7	2018-06-14 16:15:00
3617	458	13	7	2019-10-25 08:00:00
3618	458	13	7	2019-10-01 08:45:00
3619	459	17	7	2019-10-03 16:00:00
3620	459	17	7	2019-08-01 04:45:00
3621	459	17	7	2019-09-26 15:30:00
3622	459	17	7	2018-12-05 05:30:00
3623	459	17	7	2018-10-21 00:15:00
3624	459	17	7	2018-10-08 02:45:00
3625	459	17	7	2018-09-02 13:15:00
3626	459	17	7	2019-11-10 06:15:00
3627	459	17	7	2018-07-26 16:00:00
3628	459	17	7	2019-08-18 05:45:00
3629	459	17	7	2018-07-26 08:30:00
3630	459	17	7	2018-11-06 12:00:00
3631	459	17	7	2019-12-26 01:30:00
3632	460	6	11	2019-08-07 10:00:00
3633	460	6	11	2018-03-21 11:00:00
3634	460	6	11	2018-11-10 07:15:00
3635	460	6	11	2019-02-19 07:00:00
3636	460	6	11	2018-05-27 11:15:00
3637	460	6	11	2019-11-05 02:00:00
3638	460	6	11	2019-08-05 15:30:00
3639	460	6	11	2020-02-05 05:15:00
3640	461	8	2	2018-04-05 12:15:00
3641	461	8	2	2018-01-01 07:15:00
3642	461	8	2	2018-12-08 15:30:00
3643	461	8	2	2018-04-01 19:15:00
3644	461	8	2	2018-03-08 18:00:00
3645	461	8	2	2018-12-22 06:30:00
3646	461	8	2	2018-08-26 03:00:00
3647	461	8	2	2018-12-10 11:30:00
3648	461	8	2	2018-02-02 00:45:00
3649	461	8	2	2018-09-04 12:30:00
3650	461	8	2	2017-07-14 01:45:00
3651	461	8	2	2018-10-12 06:00:00
3652	462	18	2	2020-08-07 05:45:00
3653	463	9	15	2018-02-07 08:30:00
3654	463	9	15	2018-11-18 12:15:00
3655	463	9	15	2018-01-13 00:00:00
3656	463	9	15	2017-07-20 16:00:00
3657	463	9	15	2019-01-20 12:30:00
3658	463	9	15	2017-11-16 23:00:00
3659	463	9	15	2018-01-24 15:30:00
3660	463	9	15	2018-07-03 00:30:00
3661	463	9	15	2018-11-08 07:30:00
3662	463	9	15	2018-09-28 21:15:00
3663	463	9	15	2018-12-05 14:15:00
3664	463	9	15	2018-03-12 03:00:00
3665	463	9	15	2018-03-15 17:30:00
3666	464	4	14	2018-11-05 02:45:00
3667	464	4	14	2018-11-13 16:15:00
3668	464	4	14	2019-04-17 22:15:00
3669	464	4	14	2019-05-17 07:45:00
3670	465	18	17	2019-07-30 20:15:00
3671	465	18	17	2018-11-22 04:45:00
3672	465	18	17	2018-10-08 21:15:00
3673	465	18	17	2019-04-07 02:15:00
3674	465	18	17	2019-02-03 06:00:00
3675	466	8	10	2020-05-03 16:15:00
3676	466	8	10	2020-07-04 20:15:00
3677	466	8	10	2020-06-06 08:00:00
3678	466	8	10	2019-03-15 12:00:00
3679	466	8	10	2019-09-10 12:30:00
3680	467	15	15	2017-07-27 22:15:00
3681	467	15	15	2018-03-16 16:15:00
3682	467	15	15	2019-03-07 10:30:00
3683	467	15	15	2018-03-13 10:45:00
3684	467	15	15	2018-05-02 18:00:00
3685	467	15	15	2018-11-29 10:15:00
3686	468	14	19	2020-06-01 01:45:00
3687	468	14	19	2020-02-20 20:15:00
3688	468	14	19	2020-06-17 16:45:00
3689	468	14	19	2020-06-21 19:00:00
3690	468	14	19	2019-10-17 08:45:00
3691	468	14	19	2020-11-30 05:00:00
3692	468	14	19	2020-11-06 10:30:00
3693	468	14	19	2020-01-15 21:45:00
3694	468	14	19	2020-10-27 04:30:00
3695	468	14	19	2019-12-25 02:15:00
3696	468	14	19	2021-04-03 13:15:00
3697	468	14	19	2020-07-23 09:30:00
3698	468	14	19	2019-07-13 18:15:00
3699	468	14	19	2021-03-23 20:45:00
3700	469	9	1	2018-10-27 21:30:00
3701	469	9	1	2019-08-25 07:30:00
3702	469	9	1	2017-09-24 08:45:00
3703	469	9	1	2017-10-18 09:00:00
3704	469	9	1	2019-05-01 16:45:00
3705	469	9	1	2018-07-28 07:15:00
3706	470	2	7	2021-03-02 23:15:00
3707	470	2	7	2021-07-14 02:00:00
3708	470	2	7	2019-12-01 17:30:00
3709	471	12	18	2020-02-02 12:45:00
3710	471	12	18	2020-02-14 13:00:00
3711	471	12	18	2020-11-27 20:15:00
3712	471	12	18	2021-01-27 10:45:00
3713	471	12	18	2020-05-28 14:30:00
3714	471	12	18	2020-04-30 07:00:00
3715	471	12	18	2019-09-12 18:45:00
3716	471	12	18	2020-01-11 21:30:00
3717	471	12	18	2021-05-18 03:30:00
3718	472	1	3	2019-06-07 03:00:00
3719	472	1	3	2019-04-02 22:45:00
3720	472	1	3	2021-01-28 00:45:00
3721	472	1	3	2020-06-06 03:30:00
3722	472	1	3	2020-08-04 18:30:00
3723	473	12	7	2020-10-07 14:15:00
3724	473	12	7	2020-07-15 00:15:00
3725	473	12	7	2021-01-30 09:00:00
3726	473	12	7	2020-03-30 19:30:00
3727	473	12	7	2021-07-18 15:30:00
3728	473	12	7	2021-05-05 07:45:00
3729	473	12	7	2020-04-22 16:30:00
3730	473	12	7	2020-02-14 02:30:00
3731	473	12	7	2019-09-21 01:15:00
3732	473	12	7	2021-02-11 13:30:00
3733	473	12	7	2021-03-07 17:00:00
3734	473	12	7	2020-11-25 10:30:00
3735	473	12	7	2020-02-04 02:00:00
3736	473	12	7	2019-09-13 21:30:00
3737	474	20	5	2017-10-05 04:45:00
3738	474	20	5	2019-09-25 19:15:00
3739	474	20	5	2019-03-30 13:30:00
3740	474	20	5	2018-11-01 23:00:00
3741	474	20	5	2018-07-02 01:00:00
3742	474	20	5	2018-05-11 10:45:00
3743	474	20	5	2019-04-30 09:30:00
3744	474	20	5	2019-06-29 21:15:00
3745	474	20	5	2018-05-04 05:00:00
3746	475	4	13	2020-01-20 08:15:00
3747	475	4	13	2020-12-09 02:00:00
3748	475	4	13	2020-06-27 06:15:00
3749	475	4	13	2020-04-17 11:15:00
3750	475	4	13	2020-03-03 16:00:00
3751	476	15	2	2018-11-25 16:45:00
3752	476	15	2	2019-04-24 08:15:00
3753	476	15	2	2017-09-03 03:15:00
3754	477	9	4	2019-01-03 11:00:00
3755	477	9	4	2019-02-15 04:30:00
3756	477	9	4	2019-06-26 07:45:00
3757	477	9	4	2019-01-03 00:15:00
3758	477	9	4	2020-03-23 18:00:00
3759	477	9	4	2019-12-09 20:30:00
3760	477	9	4	2020-07-30 18:15:00
3761	477	9	4	2018-10-16 21:15:00
3762	477	9	4	2019-07-15 16:45:00
3763	477	9	4	2020-07-10 15:15:00
3764	478	4	7	2020-01-06 10:15:00
3765	478	4	7	2019-12-02 11:30:00
3766	478	4	7	2020-08-19 03:45:00
3767	479	17	12	2017-10-06 02:15:00
3768	479	17	12	2018-09-08 11:45:00
3769	479	17	12	2017-08-11 21:30:00
3770	479	17	12	2017-10-08 08:00:00
3771	479	17	12	2019-01-30 07:00:00
3772	479	17	12	2019-06-05 06:30:00
3773	479	17	12	2017-10-18 21:45:00
3774	479	17	12	2019-01-27 18:00:00
3775	479	17	12	2019-03-06 00:30:00
3776	479	17	12	2017-07-14 22:15:00
3777	479	17	12	2019-02-01 10:45:00
3778	480	4	9	2019-02-16 12:30:00
3779	480	4	9	2019-06-10 11:00:00
3780	480	4	9	2020-04-26 12:00:00
3781	480	4	9	2020-01-15 02:30:00
3782	480	4	9	2019-12-12 03:15:00
3783	480	4	9	2019-11-16 19:45:00
3784	480	4	9	2019-02-25 09:00:00
3785	480	4	9	2020-05-08 16:45:00
3786	480	4	9	2019-02-16 05:30:00
3787	480	4	9	2018-12-09 15:00:00
3788	480	4	9	2019-05-23 21:30:00
3789	480	4	9	2019-08-19 09:15:00
3790	480	4	9	2019-11-19 14:45:00
3791	481	20	10	2020-02-04 00:45:00
3792	481	20	10	2020-07-09 00:45:00
3793	481	20	10	2018-12-15 07:30:00
3794	481	20	10	2018-12-16 20:15:00
3795	481	20	10	2019-08-07 15:15:00
3796	481	20	10	2019-10-22 14:30:00
3797	481	20	10	2019-12-02 17:30:00
3798	481	20	10	2019-12-21 20:45:00
3799	481	20	10	2020-02-04 23:15:00
3800	481	20	10	2020-07-04 14:15:00
3801	481	20	10	2019-12-23 06:15:00
3802	481	20	10	2019-01-03 09:30:00
3803	481	20	10	2019-04-18 07:45:00
3804	482	19	14	2021-04-01 01:45:00
3805	482	19	14	2021-01-01 19:45:00
3806	482	19	14	2020-07-10 16:00:00
3807	482	19	14	2020-11-24 03:30:00
3808	482	19	14	2019-07-17 21:45:00
3809	482	19	14	2019-12-26 10:15:00
3810	482	19	14	2019-12-17 07:00:00
3811	482	19	14	2019-06-07 17:15:00
3812	482	19	14	2020-04-16 01:30:00
3813	482	19	14	2020-06-28 18:30:00
3814	483	9	5	2018-03-17 12:00:00
3815	483	9	5	2018-09-24 19:00:00
3816	483	9	5	2019-03-26 12:45:00
3817	483	9	5	2017-12-23 02:45:00
3818	483	9	5	2017-07-04 17:45:00
3819	483	9	5	2017-11-14 16:45:00
3820	483	9	5	2017-05-12 01:00:00
3821	483	9	5	2018-05-23 12:15:00
3822	483	9	5	2018-04-24 06:00:00
3823	484	18	4	2018-07-14 21:45:00
3824	484	18	4	2019-05-21 07:45:00
3825	484	18	4	2018-10-27 13:30:00
3826	484	18	4	2019-09-17 21:30:00
3827	484	18	4	2018-12-13 17:00:00
3828	484	18	4	2020-05-08 04:30:00
3829	484	18	4	2018-12-20 07:00:00
3830	484	18	4	2018-06-15 20:00:00
3831	484	18	4	2019-10-14 00:00:00
3832	484	18	4	2020-02-09 05:15:00
3833	484	18	4	2020-04-06 13:15:00
3834	484	18	4	2019-06-13 11:30:00
3835	484	18	4	2018-08-11 23:00:00
3836	485	18	18	2020-12-29 16:30:00
3837	485	18	18	2019-10-18 00:45:00
3838	485	18	18	2020-04-24 04:30:00
3839	485	18	18	2020-06-04 08:15:00
3840	485	18	18	2019-12-18 09:15:00
3841	485	18	18	2019-08-20 23:15:00
3842	485	18	18	2019-03-02 05:45:00
3843	485	18	18	2019-12-04 08:30:00
3844	485	18	18	2020-12-24 16:00:00
3845	486	14	17	2019-07-24 17:00:00
3846	487	19	5	2020-11-07 21:45:00
3847	487	19	5	2020-12-20 22:45:00
3848	487	19	5	2020-12-10 13:30:00
3849	488	9	11	2021-01-25 07:15:00
3850	488	9	11	2019-11-12 14:00:00
3851	488	9	11	2019-07-11 01:15:00
3852	488	9	11	2020-03-24 21:30:00
3853	488	9	11	2021-03-26 14:30:00
3854	488	9	11	2020-01-14 22:15:00
3855	488	9	11	2020-09-15 17:45:00
3856	488	9	11	2019-10-05 11:15:00
3857	488	9	11	2019-11-04 03:30:00
3858	488	9	11	2019-08-11 14:45:00
3859	488	9	11	2020-01-13 11:00:00
3860	489	19	18	2020-04-24 06:15:00
3861	489	19	18	2021-02-18 20:30:00
3862	489	19	18	2020-07-03 05:45:00
3863	489	19	18	2020-07-28 07:00:00
3864	490	6	15	2019-07-05 02:00:00
3865	490	6	15	2019-08-15 18:00:00
3866	490	6	15	2018-04-16 13:00:00
3867	490	6	15	2018-12-20 14:45:00
3868	490	6	15	2019-10-07 06:00:00
3869	490	6	15	2018-10-04 20:30:00
3870	491	5	15	2019-05-08 18:30:00
3871	491	5	15	2019-02-02 00:15:00
3872	491	5	15	2019-04-21 18:00:00
3873	491	5	15	2019-02-11 23:45:00
3874	491	5	15	2020-05-30 19:15:00
3875	491	5	15	2019-08-21 15:00:00
3876	491	5	15	2020-05-02 01:45:00
3877	491	5	15	2019-12-29 18:15:00
3878	491	5	15	2018-10-09 19:30:00
3879	491	5	15	2019-05-08 17:15:00
3880	491	5	15	2019-09-05 04:30:00
3881	491	5	15	2019-04-18 23:45:00
3882	491	5	15	2018-10-28 11:15:00
3883	491	5	15	2020-06-28 01:30:00
3884	492	19	7	2019-02-19 21:15:00
3885	493	13	10	2020-09-26 01:00:00
3886	493	13	10	2020-11-23 01:00:00
3887	493	13	10	2021-01-03 14:30:00
3888	493	13	10	2020-08-27 01:15:00
3889	493	13	10	2020-08-15 05:45:00
3890	493	13	10	2020-11-11 02:45:00
3891	493	13	10	2020-09-20 01:30:00
3892	494	20	20	2020-11-25 15:00:00
3893	494	20	20	2021-04-22 14:00:00
3894	494	20	20	2021-03-02 14:45:00
3895	495	5	14	2019-07-28 01:30:00
3896	495	5	14	2019-06-06 05:45:00
3897	495	5	14	2019-11-22 15:30:00
3898	496	1	5	2021-03-14 10:00:00
3899	496	1	5	2020-08-27 12:00:00
3900	496	1	5	2020-12-04 01:45:00
3901	496	1	5	2020-02-07 01:15:00
3902	496	1	5	2020-02-27 12:00:00
3903	496	1	5	2019-12-19 08:45:00
3904	496	1	5	2019-04-18 16:30:00
3905	496	1	5	2019-09-27 03:30:00
3906	496	1	5	2020-08-28 09:30:00
3907	496	1	5	2019-05-15 07:45:00
3908	496	1	5	2019-10-19 11:45:00
3909	496	1	5	2020-12-05 20:00:00
3910	497	7	18	2018-09-14 04:30:00
3911	497	7	18	2018-11-28 03:30:00
3912	497	7	18	2019-04-03 14:00:00
3913	497	7	18	2019-05-04 03:00:00
3914	497	7	18	2020-04-02 09:45:00
3915	497	7	18	2020-02-24 13:30:00
3916	497	7	18	2018-07-11 19:30:00
3917	497	7	18	2020-03-26 20:00:00
3918	498	17	3	2019-07-24 10:30:00
3919	498	17	3	2018-11-29 15:15:00
3920	498	17	3	2018-11-28 12:15:00
3921	498	17	3	2018-12-13 20:45:00
3922	498	17	3	2018-03-23 08:00:00
3923	498	17	3	2018-02-14 08:45:00
3924	498	17	3	2019-02-16 01:15:00
3925	498	17	3	2019-04-30 23:00:00
3926	498	17	3	2019-07-25 20:15:00
3927	498	17	3	2018-09-13 20:30:00
3928	498	17	3	2017-11-02 06:00:00
3929	498	17	3	2019-04-08 03:15:00
3930	498	17	3	2019-02-15 18:00:00
3931	498	17	3	2017-10-01 17:15:00
3932	498	17	3	2019-02-05 21:30:00
3933	499	9	10	2019-08-23 19:00:00
3934	499	9	10	2020-03-26 02:15:00
3935	499	9	10	2019-02-08 00:30:00
3936	499	9	10	2020-07-21 17:30:00
3937	499	9	10	2019-11-29 08:30:00
3938	499	9	10	2020-11-03 14:45:00
3939	499	9	10	2020-02-13 13:15:00
3940	499	9	10	2020-07-29 14:45:00
3941	499	9	10	2019-12-23 01:30:00
3942	500	4	3	2019-09-25 23:30:00
3943	500	4	3	2019-08-06 00:45:00
3944	500	4	3	2018-10-17 17:15:00
3945	500	4	3	2020-04-25 00:00:00
3946	500	4	3	2019-10-03 07:45:00
3947	501	8	3	2019-09-14 02:45:00
3948	501	8	3	2020-07-04 10:30:00
3949	501	8	3	2020-01-10 08:15:00
3950	501	8	3	2019-12-04 05:15:00
3951	501	8	3	2019-07-30 12:00:00
3952	501	8	3	2018-12-18 05:45:00
3953	501	8	3	2020-04-22 12:45:00
3954	501	8	3	2020-01-02 10:30:00
3955	501	8	3	2019-04-26 17:45:00
3956	501	8	3	2019-02-03 09:30:00
3957	501	8	3	2019-03-15 03:00:00
3958	501	8	3	2019-04-18 10:45:00
3959	501	8	3	2020-10-13 00:15:00
3960	501	8	3	2020-09-28 06:30:00
3961	501	8	3	2020-08-01 18:00:00
3962	502	2	11	2019-10-26 18:00:00
3963	503	18	3	2020-06-06 22:00:00
3964	503	18	3	2020-11-13 21:45:00
3965	503	18	3	2020-03-16 04:45:00
3966	503	18	3	2019-10-20 00:00:00
3967	503	18	3	2021-02-15 17:00:00
3968	504	14	7	2019-08-19 07:30:00
3969	504	14	7	2019-10-12 22:15:00
3970	504	14	7	2020-07-05 07:00:00
3971	504	14	7	2019-08-14 23:45:00
3972	505	12	18	2020-06-27 00:00:00
3973	505	12	18	2019-08-28 19:45:00
3974	505	12	18	2020-08-08 09:30:00
3975	505	12	18	2020-08-12 23:30:00
3976	505	12	18	2019-05-06 01:00:00
3977	505	12	18	2019-04-22 03:00:00
3978	505	12	18	2019-05-21 08:15:00
3979	506	16	9	2021-06-14 09:00:00
3980	506	16	9	2020-10-04 16:15:00
3981	506	16	9	2019-11-25 11:30:00
3982	506	16	9	2019-11-15 18:15:00
3983	506	16	9	2019-12-25 20:15:00
3984	506	16	9	2021-05-13 18:45:00
3985	507	18	19	2018-08-04 12:15:00
3986	507	18	19	2020-03-15 21:15:00
3987	507	18	19	2019-01-12 15:45:00
3988	507	18	19	2020-05-18 15:30:00
3989	508	11	12	2021-09-15 00:15:00
3990	508	11	12	2021-05-17 19:00:00
3991	508	11	12	2021-03-11 09:45:00
3992	508	11	12	2021-06-26 22:45:00
3993	508	11	12	2020-12-26 09:45:00
3994	508	11	12	2021-09-24 11:30:00
3995	508	11	12	2020-06-17 15:15:00
3996	508	11	12	2021-12-10 17:45:00
3997	508	11	12	2020-02-27 04:00:00
3998	509	5	6	2019-07-25 00:00:00
3999	509	5	6	2020-10-05 23:15:00
4000	509	5	6	2020-09-19 06:45:00
4001	509	5	6	2019-09-14 19:45:00
4002	509	5	6	2020-07-08 06:30:00
4003	510	12	17	2017-10-13 13:00:00
4004	510	12	17	2018-09-10 13:15:00
4005	511	11	5	2019-01-08 20:30:00
4006	511	11	5	2017-11-20 07:45:00
4007	511	11	5	2018-06-01 15:15:00
4008	511	11	5	2018-08-26 07:15:00
4009	511	11	5	2019-02-09 05:00:00
4010	511	11	5	2017-08-07 05:00:00
4011	512	11	16	2019-08-05 11:45:00
4012	512	11	16	2020-06-01 10:00:00
4013	512	11	16	2020-11-24 16:00:00
4014	512	11	16	2021-02-17 12:30:00
4015	512	11	16	2019-08-19 00:45:00
4016	512	11	16	2019-05-04 16:15:00
4017	512	11	16	2021-04-28 19:15:00
4018	512	11	16	2021-04-17 05:15:00
4019	512	11	16	2019-08-01 08:15:00
4020	512	11	16	2021-01-13 04:00:00
4021	512	11	16	2020-06-22 12:30:00
4022	512	11	16	2019-12-08 10:00:00
4023	512	11	16	2020-04-13 09:45:00
4024	512	11	16	2019-08-20 15:15:00
4025	512	11	16	2021-01-09 00:30:00
4026	513	3	3	2020-10-30 15:15:00
4027	513	3	3	2021-11-03 04:00:00
4028	513	3	3	2020-03-17 19:30:00
4029	513	3	3	2021-10-28 07:30:00
4030	513	3	3	2020-09-09 14:45:00
4031	513	3	3	2020-08-28 21:15:00
4032	513	3	3	2021-07-12 11:30:00
4033	513	3	3	2020-07-15 06:45:00
4034	513	3	3	2020-03-26 13:00:00
4035	513	3	3	2021-09-23 17:15:00
4036	513	3	3	2020-01-20 19:45:00
4037	513	3	3	2020-10-04 07:00:00
4038	513	3	3	2021-06-30 14:30:00
4039	514	9	13	2017-12-10 00:15:00
4040	514	9	13	2018-12-02 00:15:00
4041	515	2	20	2018-03-08 06:15:00
4042	515	2	20	2017-09-14 22:30:00
4043	515	2	20	2018-09-19 18:15:00
4044	515	2	20	2018-10-29 18:30:00
4045	516	8	10	2017-11-22 12:30:00
4046	516	8	10	2017-03-06 20:30:00
4047	516	8	10	2017-04-12 02:30:00
4048	516	8	10	2018-05-03 08:00:00
4049	516	8	10	2018-06-10 06:00:00
4050	516	8	10	2018-10-20 21:30:00
4051	517	9	7	2020-05-17 12:45:00
4052	518	16	4	2021-02-04 00:30:00
4053	518	16	4	2020-10-09 01:00:00
4054	518	16	4	2020-07-18 13:00:00
4055	518	16	4	2019-10-11 21:00:00
4056	518	16	4	2019-12-22 00:15:00
4057	518	16	4	2020-05-21 21:45:00
4058	518	16	4	2019-10-17 23:00:00
4059	519	18	2	2018-02-16 00:00:00
4060	519	18	2	2018-03-16 09:30:00
4061	519	18	2	2017-10-23 08:30:00
4062	519	18	2	2018-07-14 10:15:00
4063	519	18	2	2017-11-15 03:15:00
4064	519	18	2	2017-07-06 00:45:00
4065	519	18	2	2017-09-13 12:00:00
4066	520	3	7	2018-04-03 17:30:00
4067	520	3	7	2017-05-17 10:00:00
4068	520	3	7	2018-03-03 19:15:00
4069	520	3	7	2018-06-01 11:00:00
4070	520	3	7	2018-12-22 10:45:00
4071	520	3	7	2017-06-09 14:15:00
4072	520	3	7	2017-08-17 22:15:00
4073	520	3	7	2018-01-22 21:00:00
4074	521	11	5	2020-02-18 12:00:00
4075	521	11	5	2020-01-10 08:15:00
4076	521	11	5	2020-07-23 17:45:00
4077	521	11	5	2021-03-22 03:15:00
4078	521	11	5	2020-04-05 08:45:00
4079	521	11	5	2020-10-05 07:45:00
4080	521	11	5	2020-08-21 18:00:00
4081	521	11	5	2021-04-19 05:45:00
4082	521	11	5	2021-01-07 01:00:00
4083	521	11	5	2021-07-28 11:15:00
4084	521	11	5	2020-08-23 10:00:00
4085	521	11	5	2021-04-07 04:00:00
4086	521	11	5	2020-07-21 23:30:00
4087	521	11	5	2021-04-05 15:30:00
4088	522	17	19	2021-02-08 10:15:00
4089	522	17	19	2021-07-08 05:00:00
4090	522	17	19	2020-03-24 07:30:00
4091	522	17	19	2020-08-07 03:30:00
4092	523	16	6	2019-10-15 23:15:00
4093	523	16	6	2020-07-01 03:30:00
4094	523	16	6	2020-06-25 01:45:00
4095	523	16	6	2020-06-06 12:00:00
4096	523	16	6	2020-05-12 14:45:00
4097	523	16	6	2018-09-27 13:00:00
4098	523	16	6	2020-03-25 08:15:00
4099	523	16	6	2019-12-23 10:00:00
4100	523	16	6	2019-02-06 20:00:00
4101	523	16	6	2019-05-02 23:45:00
4102	523	16	6	2018-10-28 12:15:00
4103	523	16	6	2020-04-20 04:45:00
4104	523	16	6	2018-12-09 05:00:00
4105	523	16	6	2018-10-28 11:30:00
4106	523	16	6	2018-11-04 03:45:00
4107	524	1	3	2018-06-21 22:30:00
4108	524	1	3	2017-11-25 22:15:00
4109	524	1	3	2018-08-11 17:00:00
4110	524	1	3	2018-04-02 21:00:00
4111	524	1	3	2018-09-08 10:00:00
4112	524	1	3	2018-05-06 22:15:00
4113	524	1	3	2017-10-18 01:15:00
4114	525	11	7	2020-09-17 12:45:00
4115	525	11	7	2020-02-19 10:15:00
4116	525	11	7	2020-02-16 05:15:00
4117	525	11	7	2019-11-02 08:15:00
4118	525	11	7	2020-04-11 14:00:00
4119	525	11	7	2019-02-17 05:45:00
4120	525	11	7	2018-12-10 17:15:00
4121	525	11	7	2020-08-01 04:45:00
4122	525	11	7	2018-12-25 11:15:00
4123	525	11	7	2018-11-13 20:45:00
4124	525	11	7	2019-05-08 15:45:00
4125	525	11	7	2019-02-21 21:30:00
4126	525	11	7	2019-02-04 12:30:00
4127	525	11	7	2019-02-19 11:45:00
4128	525	11	7	2020-02-18 17:15:00
4129	526	7	8	2018-07-14 11:30:00
4130	526	7	8	2018-04-06 03:15:00
4131	526	7	8	2018-05-05 06:45:00
4132	526	7	8	2017-09-10 04:45:00
4133	526	7	8	2018-04-29 16:15:00
4134	526	7	8	2019-03-15 12:45:00
4135	526	7	8	2018-11-28 16:45:00
4136	526	7	8	2017-08-04 13:30:00
4137	526	7	8	2018-08-13 13:30:00
4138	526	7	8	2019-02-02 16:45:00
4139	526	7	8	2017-08-01 03:00:00
4140	526	7	8	2018-04-08 16:00:00
4141	527	18	6	2020-05-28 16:00:00
4142	527	18	6	2019-09-16 05:45:00
4143	527	18	6	2020-03-25 08:15:00
4144	528	16	11	2019-03-07 01:00:00
4145	528	16	11	2019-02-05 00:30:00
4146	528	16	11	2019-06-25 05:00:00
4147	528	16	11	2019-10-12 22:30:00
4148	528	16	11	2019-06-15 12:45:00
4149	529	19	17	2018-10-05 23:15:00
4150	529	19	17	2018-11-13 11:30:00
4151	529	19	17	2018-07-20 18:00:00
4152	529	19	17	2017-12-18 14:30:00
4153	529	19	17	2018-08-06 04:30:00
4154	529	19	17	2018-08-27 12:15:00
4155	529	19	17	2017-10-08 04:45:00
4156	529	19	17	2017-12-03 11:15:00
4157	529	19	17	2018-09-26 22:45:00
4158	529	19	17	2017-09-25 18:00:00
4159	529	19	17	2018-11-19 16:30:00
4160	529	19	17	2017-07-25 08:45:00
4161	530	19	7	2020-06-24 15:30:00
4162	530	19	7	2020-11-20 23:00:00
4163	530	19	7	2019-09-06 21:00:00
4164	530	19	7	2020-07-20 05:30:00
4165	530	19	7	2020-03-28 07:30:00
4166	530	19	7	2020-04-09 05:00:00
4167	530	19	7	2019-06-04 09:30:00
4168	531	16	11	2019-11-23 21:15:00
4169	531	16	11	2020-11-29 13:45:00
4170	532	14	15	2019-09-27 09:00:00
4171	532	14	15	2021-01-26 01:30:00
4172	532	14	15	2021-05-29 23:30:00
4173	532	14	15	2020-08-01 11:45:00
4174	532	14	15	2020-05-04 18:00:00
4175	532	14	15	2020-08-22 02:00:00
4176	533	16	12	2019-02-04 23:00:00
4177	533	16	12	2017-08-21 00:00:00
4178	533	16	12	2018-03-14 01:30:00
4179	533	16	12	2018-05-13 19:15:00
4180	533	16	12	2018-03-01 22:45:00
4181	533	16	12	2018-10-04 20:30:00
4182	533	16	12	2018-04-22 15:45:00
4183	534	8	18	2020-07-27 10:00:00
4184	534	8	18	2019-08-16 15:30:00
4185	534	8	18	2021-04-27 00:45:00
4186	534	8	18	2019-11-23 13:45:00
4187	534	8	18	2019-11-29 11:15:00
4188	534	8	18	2020-04-10 05:30:00
4189	534	8	18	2021-03-02 09:30:00
4190	534	8	18	2020-04-09 00:00:00
4191	534	8	18	2019-09-22 10:15:00
4192	534	8	18	2019-08-23 11:45:00
4193	534	8	18	2020-06-23 13:00:00
4194	535	4	20	2019-09-14 20:15:00
4195	535	4	20	2020-04-01 10:00:00
4196	535	4	20	2020-04-30 20:30:00
4197	535	4	20	2020-06-06 02:15:00
4198	535	4	20	2019-09-04 13:15:00
4199	535	4	20	2020-09-10 05:00:00
4200	535	4	20	2020-03-07 09:45:00
4201	535	4	20	2020-07-05 20:45:00
4202	535	4	20	2019-02-02 10:30:00
4203	535	4	20	2019-02-03 19:30:00
4204	536	10	13	2019-08-02 23:00:00
4205	536	10	13	2020-01-10 06:45:00
4206	536	10	13	2021-06-26 11:00:00
4207	536	10	13	2020-12-15 23:45:00
4208	536	10	13	2021-05-09 16:00:00
4209	536	10	13	2019-08-27 05:45:00
4210	536	10	13	2021-04-23 12:30:00
4211	536	10	13	2020-01-28 13:45:00
4212	536	10	13	2019-07-25 17:15:00
4213	536	10	13	2021-01-04 00:15:00
4214	536	10	13	2020-10-27 15:15:00
4215	537	10	8	2019-01-12 00:30:00
4216	537	10	8	2020-06-28 08:15:00
4217	537	10	8	2020-03-28 20:30:00
4218	538	9	17	2019-04-04 06:00:00
4219	538	9	17	2017-12-24 08:30:00
4220	538	9	17	2018-07-01 07:30:00
4221	538	9	17	2019-01-25 19:45:00
4222	538	9	17	2018-08-26 22:45:00
4223	538	9	17	2019-04-01 08:15:00
4224	538	9	17	2018-05-29 18:45:00
4225	539	9	13	2018-12-08 04:00:00
4226	539	9	13	2018-04-06 07:45:00
4227	539	9	13	2018-10-27 21:30:00
4228	539	9	13	2018-10-05 15:00:00
4229	539	9	13	2017-10-13 13:30:00
4230	539	9	13	2019-04-12 02:30:00
4231	539	9	13	2019-05-15 15:15:00
4232	539	9	13	2017-11-05 00:00:00
4233	539	9	13	2019-05-23 05:15:00
4234	539	9	13	2019-02-10 23:00:00
4235	539	9	13	2018-10-15 04:45:00
4236	539	9	13	2019-01-08 21:00:00
4237	540	4	3	2018-10-17 22:15:00
4238	540	4	3	2019-03-24 11:30:00
4239	540	4	3	2018-04-21 12:45:00
4240	540	4	3	2018-06-09 05:15:00
4241	540	4	3	2018-02-06 10:45:00
4242	540	4	3	2018-09-17 07:00:00
4243	540	4	3	2019-02-04 03:30:00
4244	540	4	3	2018-06-09 02:45:00
4245	540	4	3	2019-04-12 21:45:00
4246	540	4	3	2017-12-25 14:15:00
4247	541	12	17	2019-10-03 07:45:00
4248	541	12	17	2019-09-01 19:45:00
4249	541	12	17	2019-02-08 23:45:00
4250	541	12	17	2018-12-06 10:45:00
4251	541	12	17	2020-06-06 14:45:00
4252	541	12	17	2019-11-21 13:00:00
4253	541	12	17	2019-12-15 05:15:00
4254	541	12	17	2020-02-06 13:45:00
4255	541	12	17	2020-08-26 17:00:00
4256	542	4	2	2019-09-08 09:30:00
4257	542	4	2	2020-03-04 06:00:00
4258	542	4	2	2019-12-23 07:15:00
4259	542	4	2	2020-04-06 23:30:00
4260	542	4	2	2020-10-04 18:00:00
4261	542	4	2	2020-01-18 02:30:00
4262	542	4	2	2019-08-04 20:00:00
4263	542	4	2	2019-04-28 04:15:00
4264	542	4	2	2020-03-26 22:45:00
4265	542	4	2	2020-05-11 04:45:00
4266	542	4	2	2020-09-24 09:00:00
4267	542	4	2	2020-04-21 05:30:00
4268	542	4	2	2020-05-29 21:45:00
4269	542	4	2	2019-09-15 18:15:00
4270	543	14	2	2020-09-18 15:15:00
4271	543	14	2	2021-04-26 04:30:00
4272	543	14	2	2020-12-24 05:15:00
4273	543	14	2	2019-09-03 10:00:00
4274	543	14	2	2019-07-21 20:45:00
4275	543	14	2	2020-08-22 00:15:00
4276	543	14	2	2020-05-15 22:45:00
4277	543	14	2	2020-08-30 01:30:00
4278	543	14	2	2019-12-06 20:00:00
4279	543	14	2	2020-07-06 15:30:00
4280	544	4	19	2019-10-29 08:30:00
4281	544	4	19	2020-08-01 00:45:00
4282	544	4	19	2020-07-23 18:45:00
4283	544	4	19	2019-12-12 19:30:00
4284	544	4	19	2021-03-14 22:45:00
4285	544	4	19	2020-08-25 22:15:00
4286	544	4	19	2019-12-29 07:45:00
4287	545	11	10	2018-04-05 10:30:00
4288	545	11	10	2018-04-07 11:00:00
4289	545	11	10	2019-02-04 01:00:00
4290	545	11	10	2019-05-30 02:15:00
4291	545	11	10	2019-11-15 01:45:00
4292	546	13	8	2019-04-21 22:15:00
4293	546	13	8	2018-09-10 03:45:00
4294	546	13	8	2018-10-05 01:00:00
4295	546	13	8	2019-09-10 20:45:00
4296	546	13	8	2018-05-21 00:30:00
4297	546	13	8	2019-03-24 21:15:00
4298	546	13	8	2018-09-21 22:15:00
4299	546	13	8	2020-03-05 16:15:00
4300	547	17	20	2017-11-04 01:15:00
4301	547	17	20	2018-05-18 18:15:00
4302	547	17	20	2019-04-02 04:45:00
4303	547	17	20	2019-09-27 14:00:00
4304	547	17	20	2019-09-26 15:15:00
4305	547	17	20	2018-05-02 12:15:00
4306	547	17	20	2018-03-14 21:00:00
4307	548	19	12	2020-01-01 01:30:00
4308	548	19	12	2020-01-28 19:15:00
4309	548	19	12	2018-07-25 08:15:00
4310	548	19	12	2019-07-20 00:30:00
4311	548	19	12	2019-10-03 13:45:00
4312	548	19	12	2018-07-24 04:00:00
4313	548	19	12	2019-11-29 10:15:00
4314	548	19	12	2018-07-08 03:45:00
4315	548	19	12	2019-03-18 09:30:00
4316	549	16	15	2019-03-30 14:30:00
4317	549	16	15	2019-04-19 19:45:00
4318	549	16	15	2017-10-18 12:45:00
4319	549	16	15	2017-07-28 21:00:00
4320	549	16	15	2017-08-25 07:30:00
4321	549	16	15	2019-03-26 12:45:00
4322	549	16	15	2017-07-11 18:30:00
4323	549	16	15	2017-07-26 01:15:00
4324	549	16	15	2018-02-23 12:30:00
4325	549	16	15	2019-01-23 03:45:00
4326	549	16	15	2017-08-25 12:45:00
4327	550	14	18	2018-11-15 00:30:00
4328	550	14	18	2018-08-20 07:00:00
4329	550	14	18	2019-01-25 22:30:00
4330	550	14	18	2018-07-07 02:15:00
4331	550	14	18	2020-02-04 09:00:00
4332	550	14	18	2019-08-08 17:45:00
4333	550	14	18	2019-05-23 23:30:00
4334	550	14	18	2018-11-16 23:45:00
4335	551	1	11	2017-08-28 23:00:00
4336	551	1	11	2018-07-22 00:30:00
4337	551	1	11	2018-05-12 04:45:00
4338	551	1	11	2017-11-24 17:45:00
4339	551	1	11	2019-07-12 21:30:00
4340	551	1	11	2018-01-13 16:45:00
4341	551	1	11	2019-04-27 03:45:00
4342	552	18	2	2019-05-13 19:30:00
4343	552	18	2	2019-09-20 07:15:00
4344	552	18	2	2019-08-19 06:45:00
4345	552	18	2	2018-09-05 10:00:00
4346	552	18	2	2018-10-24 13:45:00
4347	552	18	2	2018-01-21 06:15:00
4348	552	18	2	2019-05-19 23:00:00
4349	552	18	2	2019-01-12 11:15:00
4350	552	18	2	2019-09-05 11:15:00
4351	552	18	2	2017-10-14 20:45:00
4352	552	18	2	2018-12-17 20:45:00
4353	553	20	5	2020-03-30 07:15:00
4354	553	20	5	2020-09-10 16:30:00
4355	553	20	5	2021-07-16 08:45:00
4356	553	20	5	2020-07-09 13:45:00
4357	553	20	5	2019-10-25 11:15:00
4358	553	20	5	2020-12-10 19:45:00
4359	553	20	5	2020-09-29 00:15:00
4360	553	20	5	2020-02-05 22:15:00
4361	553	20	5	2020-03-25 19:45:00
4362	553	20	5	2019-12-16 12:15:00
4363	553	20	5	2019-11-24 12:00:00
4364	553	20	5	2020-01-01 21:45:00
4365	553	20	5	2021-03-26 22:15:00
4366	554	16	9	2018-10-11 22:30:00
4367	554	16	9	2018-07-11 06:00:00
4368	554	16	9	2018-04-03 12:30:00
4369	554	16	9	2019-06-12 04:30:00
4370	554	16	9	2018-08-16 10:30:00
4371	554	16	9	2019-03-18 22:45:00
4372	555	8	10	2019-04-28 15:30:00
4373	555	8	10	2019-08-23 15:30:00
4374	555	8	10	2018-11-14 07:45:00
4375	555	8	10	2018-08-26 21:45:00
4376	556	3	16	2019-04-08 10:00:00
4377	556	3	16	2019-02-02 21:30:00
4378	556	3	16	2019-08-11 04:45:00
4379	556	3	16	2019-07-07 19:45:00
4380	556	3	16	2018-05-02 08:30:00
4381	556	3	16	2018-10-24 23:45:00
4382	556	3	16	2020-03-20 21:45:00
4383	556	3	16	2019-07-11 23:30:00
4384	556	3	16	2019-01-15 18:45:00
4385	556	3	16	2019-08-23 14:30:00
4386	557	1	5	2020-12-23 02:00:00
4387	557	1	5	2020-08-18 20:15:00
4388	557	1	5	2020-10-20 05:00:00
4389	557	1	5	2020-06-27 12:45:00
4390	557	1	5	2021-08-29 11:45:00
4391	557	1	5	2019-10-13 19:45:00
4392	557	1	5	2021-04-04 20:00:00
4393	557	1	5	2021-03-18 14:15:00
4394	557	1	5	2020-11-25 19:45:00
4395	558	9	11	2020-09-25 03:45:00
4396	558	9	11	2020-09-30 02:15:00
4397	558	9	11	2020-11-11 07:45:00
4398	558	9	11	2021-04-17 21:00:00
4399	558	9	11	2020-12-06 11:30:00
4400	558	9	11	2021-04-08 12:15:00
4401	558	9	11	2020-10-10 09:15:00
4402	558	9	11	2021-09-14 04:15:00
4403	558	9	11	2020-06-30 04:30:00
4404	558	9	11	2021-12-22 05:15:00
4405	558	9	11	2020-05-06 02:00:00
4406	558	9	11	2021-05-26 04:00:00
4407	559	9	3	2019-04-01 22:15:00
4408	559	9	3	2019-01-11 02:15:00
4409	559	9	3	2018-01-02 12:45:00
4410	559	9	3	2019-11-02 06:45:00
4411	559	9	3	2018-04-29 15:30:00
4412	559	9	3	2019-07-11 07:45:00
4413	559	9	3	2018-03-26 19:30:00
4414	559	9	3	2018-02-19 13:45:00
4415	560	16	13	2019-09-29 02:45:00
4416	560	16	13	2018-06-27 23:30:00
4417	560	16	13	2020-04-22 00:15:00
4418	560	16	13	2019-12-23 00:45:00
4419	560	16	13	2019-01-29 02:30:00
4420	560	16	13	2019-05-25 20:15:00
4421	560	16	13	2019-02-01 10:45:00
4422	560	16	13	2020-04-25 03:45:00
4423	560	16	13	2019-10-30 04:00:00
4424	561	6	5	2020-05-21 01:45:00
4425	561	6	5	2019-10-05 20:30:00
4426	561	6	5	2019-08-20 03:30:00
4427	561	6	5	2020-03-19 04:45:00
4428	561	6	5	2020-11-16 00:15:00
4429	561	6	5	2019-02-12 16:45:00
4430	561	6	5	2019-12-21 01:45:00
4431	561	6	5	2019-04-26 21:45:00
4432	561	6	5	2019-03-24 03:15:00
4433	561	6	5	2019-04-13 10:00:00
4434	561	6	5	2020-02-25 11:30:00
4435	562	15	11	2019-11-27 15:30:00
4436	562	15	11	2019-02-14 06:30:00
4437	562	15	11	2020-07-16 23:45:00
4438	562	15	11	2019-04-21 12:30:00
4439	562	15	11	2019-08-12 11:30:00
4440	562	15	11	2020-08-28 12:45:00
4441	562	15	11	2018-11-19 04:30:00
4442	562	15	11	2019-01-19 17:30:00
4443	562	15	11	2019-05-28 10:15:00
4444	562	15	11	2019-08-12 19:45:00
4445	562	15	11	2020-04-03 05:15:00
4446	562	15	11	2020-08-23 15:45:00
4447	562	15	11	2019-02-20 10:15:00
4448	562	15	11	2019-12-16 19:15:00
4449	563	7	11	2020-12-03 04:00:00
4450	563	7	11	2020-10-27 00:30:00
4451	563	7	11	2019-08-14 19:15:00
4452	563	7	11	2020-04-16 01:15:00
4453	563	7	11	2021-03-12 12:15:00
4454	563	7	11	2020-01-05 23:30:00
4455	563	7	11	2020-01-23 19:00:00
4456	563	7	11	2019-04-26 08:45:00
4457	563	7	11	2020-02-05 15:45:00
4458	563	7	11	2020-09-16 14:15:00
4459	563	7	11	2021-02-27 17:00:00
4460	563	7	11	2021-01-08 05:30:00
4461	563	7	11	2020-10-01 17:30:00
4462	563	7	11	2020-02-09 08:45:00
4463	564	4	18	2021-01-17 08:00:00
4464	564	4	18	2020-07-10 21:00:00
4465	564	4	18	2021-02-25 00:45:00
4466	564	4	18	2020-07-21 04:30:00
4467	564	4	18	2021-06-22 02:15:00
4468	564	4	18	2020-12-08 22:30:00
4469	564	4	18	2020-05-14 22:15:00
4470	564	4	18	2020-09-05 20:45:00
4471	564	4	18	2020-08-15 19:15:00
4472	564	4	18	2019-11-29 19:30:00
4473	564	4	18	2020-07-04 03:45:00
4474	565	9	1	2019-02-04 01:45:00
4475	565	9	1	2019-10-18 14:15:00
4476	565	9	1	2018-06-20 22:00:00
4477	565	9	1	2020-03-19 20:30:00
4478	565	9	1	2018-08-05 07:30:00
4479	565	9	1	2020-01-27 03:45:00
4480	565	9	1	2020-01-25 07:15:00
4481	565	9	1	2018-05-23 09:00:00
4482	565	9	1	2018-06-30 18:00:00
4483	565	9	1	2019-02-21 19:30:00
4484	566	2	18	2019-04-08 20:15:00
4485	566	2	18	2019-09-10 18:45:00
4486	566	2	18	2020-06-19 17:45:00
4487	566	2	18	2020-06-30 02:45:00
4488	566	2	18	2020-05-20 04:30:00
4489	566	2	18	2020-09-21 19:45:00
4490	566	2	18	2019-08-30 14:30:00
4491	566	2	18	2020-07-18 00:15:00
4492	566	2	18	2020-10-05 05:00:00
4493	566	2	18	2020-07-26 08:00:00
4494	566	2	18	2019-12-14 16:30:00
4495	567	14	9	2019-09-22 14:30:00
4496	567	14	9	2020-09-10 11:30:00
4497	567	14	9	2020-06-12 02:45:00
4498	567	14	9	2020-08-17 01:00:00
4499	567	14	9	2019-11-30 00:00:00
4500	567	14	9	2021-01-15 09:00:00
4501	567	14	9	2020-05-09 12:45:00
4502	567	14	9	2020-02-19 19:30:00
4503	567	14	9	2019-06-26 14:00:00
4504	567	14	9	2020-06-12 00:30:00
4505	567	14	9	2019-07-12 11:15:00
4506	567	14	9	2020-01-11 14:00:00
4507	568	18	9	2020-01-15 14:15:00
4508	568	18	9	2020-03-11 04:15:00
4509	568	18	9	2020-01-26 01:45:00
4510	568	18	9	2020-11-19 05:30:00
4511	568	18	9	2018-12-03 01:00:00
4512	568	18	9	2019-09-29 09:00:00
4513	568	18	9	2020-09-04 05:00:00
4514	568	18	9	2020-11-19 03:15:00
4515	568	18	9	2020-06-29 00:00:00
4516	568	18	9	2019-08-01 12:15:00
4517	568	18	9	2020-04-28 15:00:00
4518	568	18	9	2018-12-04 18:45:00
4519	568	18	9	2020-09-24 13:15:00
4520	568	18	9	2019-12-08 15:15:00
4521	569	7	12	2020-08-25 17:30:00
4522	569	7	12	2019-10-11 05:15:00
4523	569	7	12	2019-11-10 09:00:00
4524	569	7	12	2019-10-24 09:45:00
4525	569	7	12	2021-08-20 08:00:00
4526	569	7	12	2021-02-02 22:45:00
4527	569	7	12	2020-02-08 03:15:00
4528	569	7	12	2020-02-21 06:00:00
4529	569	7	12	2020-05-06 12:15:00
4530	569	7	12	2021-05-17 01:15:00
4531	569	7	12	2021-01-16 03:30:00
4532	570	6	10	2018-08-30 14:30:00
4533	570	6	10	2017-11-07 09:30:00
4534	570	6	10	2018-03-19 17:15:00
4535	570	6	10	2017-04-28 11:00:00
4536	570	6	10	2017-07-14 03:00:00
4537	570	6	10	2017-11-09 10:00:00
4538	570	6	10	2017-04-29 20:30:00
4539	570	6	10	2019-02-06 00:15:00
4540	570	6	10	2017-07-06 11:00:00
4541	570	6	10	2017-05-10 06:45:00
4542	570	6	10	2017-09-11 06:45:00
4543	571	7	13	2019-06-30 14:00:00
4544	571	7	13	2019-04-04 11:30:00
4545	571	7	13	2017-11-06 11:00:00
4546	571	7	13	2018-08-16 00:00:00
4547	571	7	13	2018-10-03 05:00:00
4548	571	7	13	2017-12-26 12:45:00
4549	572	6	17	2019-02-03 16:30:00
4550	572	6	17	2018-01-29 23:30:00
4551	572	6	17	2018-04-03 04:30:00
4552	572	6	17	2018-03-15 11:00:00
4553	572	6	17	2018-09-13 15:30:00
4554	572	6	17	2019-03-28 23:30:00
4555	572	6	17	2017-11-03 18:45:00
4556	573	3	14	2020-04-27 15:45:00
4557	573	3	14	2019-08-29 07:30:00
4558	573	3	14	2021-04-12 19:30:00
4559	573	3	14	2020-02-14 22:30:00
4560	573	3	14	2021-05-02 05:00:00
4561	573	3	14	2020-12-08 19:15:00
4562	573	3	14	2020-08-12 06:00:00
4563	573	3	14	2019-06-04 08:00:00
4564	573	3	14	2021-02-09 01:00:00
4565	573	3	14	2019-12-06 08:15:00
4566	573	3	14	2020-08-30 13:30:00
4567	573	3	14	2020-01-06 03:00:00
4568	573	3	14	2020-01-27 18:00:00
4569	574	14	14	2018-10-09 07:30:00
4570	574	14	14	2020-03-26 15:30:00
4571	574	14	14	2018-11-25 22:15:00
4572	575	15	2	2019-08-17 02:30:00
4573	575	15	2	2019-06-26 23:00:00
4574	575	15	2	2018-08-18 07:00:00
4575	575	15	2	2018-04-10 01:00:00
4576	575	15	2	2019-02-11 16:45:00
4577	575	15	2	2018-04-21 13:30:00
4578	575	15	2	2018-02-04 18:45:00
4579	575	15	2	2019-08-30 01:15:00
4580	575	15	2	2018-08-14 17:30:00
4581	576	7	14	2019-03-02 22:15:00
4582	577	20	12	2017-10-10 20:15:00
4583	577	20	12	2018-05-06 14:00:00
4584	577	20	12	2017-11-11 03:15:00
4585	577	20	12	2018-02-19 22:00:00
4586	577	20	12	2017-08-16 10:45:00
4587	577	20	12	2018-03-04 14:15:00
4588	577	20	12	2018-02-01 18:30:00
4589	577	20	12	2018-02-03 19:45:00
4590	578	5	3	2020-04-19 07:00:00
4591	578	5	3	2020-07-18 20:30:00
4592	579	3	11	2019-11-15 09:00:00
4593	579	3	11	2019-06-03 16:00:00
4594	579	3	11	2018-08-25 14:30:00
4595	579	3	11	2019-08-18 04:15:00
4596	579	3	11	2020-05-01 01:00:00
4597	579	3	11	2019-04-16 23:00:00
4598	579	3	11	2018-12-09 00:15:00
4599	579	3	11	2019-09-08 06:30:00
4600	579	3	11	2019-11-28 19:45:00
4601	579	3	11	2019-01-11 07:15:00
4602	579	3	11	2018-12-13 16:00:00
4603	580	19	16	2020-02-20 15:30:00
4604	580	19	16	2020-03-08 21:45:00
4605	580	19	16	2020-01-18 22:45:00
4606	580	19	16	2019-06-18 05:00:00
4607	580	19	16	2019-08-30 19:00:00
4608	580	19	16	2018-11-10 12:45:00
4609	580	19	16	2018-10-14 08:30:00
4610	580	19	16	2019-05-28 07:30:00
4611	580	19	16	2018-09-02 09:45:00
4612	580	19	16	2019-09-14 21:30:00
4613	580	19	16	2018-12-13 01:30:00
4614	581	13	17	2018-11-10 06:45:00
4615	581	13	17	2019-05-05 16:30:00
4616	581	13	17	2019-07-29 13:30:00
4617	581	13	17	2019-11-09 21:45:00
4618	581	13	17	2019-08-30 10:30:00
4619	581	13	17	2020-03-18 17:00:00
4620	581	13	17	2019-06-30 23:15:00
4621	581	13	17	2019-12-29 17:30:00
4622	581	13	17	2019-02-04 22:15:00
4623	581	13	17	2020-01-14 17:00:00
4624	581	13	17	2019-12-06 14:00:00
4625	581	13	17	2019-04-02 01:15:00
4626	581	13	17	2018-11-27 15:30:00
4627	581	13	17	2018-05-29 23:15:00
4628	581	13	17	2019-08-22 18:45:00
4629	582	13	10	2020-06-12 02:45:00
4630	582	13	10	2020-05-15 02:00:00
4631	582	13	10	2021-11-14 13:15:00
4632	582	13	10	2020-02-02 21:30:00
4633	582	13	10	2020-04-30 04:30:00
4634	582	13	10	2021-01-28 19:30:00
4635	582	13	10	2020-06-24 12:00:00
4636	582	13	10	2020-12-17 08:15:00
4637	583	9	17	2021-05-02 16:45:00
4638	583	9	17	2021-10-07 03:00:00
4639	583	9	17	2021-04-16 06:45:00
4640	583	9	17	2020-08-11 18:30:00
4641	583	9	17	2021-03-03 10:15:00
4642	583	9	17	2020-02-11 12:15:00
4643	583	9	17	2021-06-11 10:15:00
4644	583	9	17	2020-09-07 00:00:00
4645	583	9	17	2020-06-09 12:15:00
4646	583	9	17	2021-04-29 17:00:00
4647	583	9	17	2021-02-02 17:00:00
4648	584	10	17	2018-07-21 05:15:00
4649	584	10	17	2019-10-09 08:45:00
4650	584	10	17	2020-01-18 01:15:00
4651	584	10	17	2019-11-24 22:00:00
4652	584	10	17	2019-08-17 02:45:00
4653	584	10	17	2018-10-25 15:30:00
4654	584	10	17	2018-03-07 05:30:00
4655	584	10	17	2019-11-01 01:15:00
4656	584	10	17	2019-11-18 22:30:00
4657	584	10	17	2020-01-23 08:45:00
4658	584	10	17	2018-12-18 23:15:00
4659	584	10	17	2019-12-07 23:30:00
4660	585	9	5	2019-07-22 20:00:00
4661	585	9	5	2019-09-29 07:30:00
4662	586	15	8	2019-12-25 02:15:00
4663	586	15	8	2021-06-03 23:15:00
4664	587	19	12	2018-05-24 19:45:00
4665	587	19	12	2018-04-03 16:15:00
4666	587	19	12	2018-07-08 09:00:00
4667	587	19	12	2019-02-17 14:15:00
4668	588	13	18	2021-02-20 03:30:00
4669	588	13	18	2020-04-12 23:15:00
4670	588	13	18	2019-12-22 10:30:00
4671	588	13	18	2021-01-09 08:30:00
4672	588	13	18	2020-08-19 18:45:00
4673	588	13	18	2020-06-12 18:30:00
4674	588	13	18	2019-11-22 20:45:00
4675	589	10	19	2019-10-02 16:45:00
4676	589	10	19	2018-01-10 02:15:00
4677	589	10	19	2018-07-19 00:00:00
4678	589	10	19	2018-07-15 22:30:00
4679	589	10	19	2019-06-24 04:30:00
4680	590	19	11	2020-01-05 06:15:00
4681	590	19	11	2019-12-15 16:00:00
4682	590	19	11	2018-10-13 06:15:00
4683	591	7	20	2020-08-09 16:00:00
4684	591	7	20	2019-02-18 10:00:00
4685	591	7	20	2019-06-03 13:15:00
4686	591	7	20	2019-11-02 13:00:00
4687	591	7	20	2019-06-12 17:45:00
4688	591	7	20	2019-03-09 19:15:00
4689	591	7	20	2020-07-15 09:30:00
4690	591	7	20	2020-10-13 00:30:00
4691	591	7	20	2020-06-18 14:15:00
4692	591	7	20	2020-06-13 19:45:00
4693	591	7	20	2019-07-19 20:30:00
4694	592	6	4	2021-09-12 13:00:00
4695	592	6	4	2019-12-23 19:45:00
4696	592	6	4	2020-05-19 07:30:00
4697	592	6	4	2021-05-26 00:45:00
4698	592	6	4	2019-12-19 08:45:00
4699	592	6	4	2021-09-04 14:15:00
4700	593	17	6	2019-03-15 06:15:00
4701	593	17	6	2018-09-18 21:00:00
4702	593	17	6	2018-11-21 17:30:00
4703	593	17	6	2018-07-27 20:00:00
4704	593	17	6	2019-01-25 09:15:00
4705	593	17	6	2018-11-01 10:45:00
4706	593	17	6	2019-04-10 18:00:00
4707	593	17	6	2018-01-20 11:15:00
4708	593	17	6	2019-09-05 19:30:00
4709	593	17	6	2019-01-21 14:45:00
4710	593	17	6	2019-01-28 08:45:00
4711	593	17	6	2018-10-09 14:30:00
4712	593	17	6	2019-01-05 12:30:00
4713	593	17	6	2018-01-20 10:15:00
4714	594	11	20	2020-01-11 03:00:00
4715	594	11	20	2019-05-28 05:15:00
4716	594	11	20	2019-06-19 15:00:00
4717	594	11	20	2019-01-28 02:00:00
4718	594	11	20	2018-11-09 05:30:00
4719	594	11	20	2020-01-15 20:00:00
4720	594	11	20	2018-10-05 18:00:00
4721	594	11	20	2020-02-06 10:15:00
4722	594	11	20	2019-01-11 07:30:00
4723	595	1	16	2019-08-13 18:30:00
4724	595	1	16	2019-08-25 14:45:00
4725	595	1	16	2018-11-28 04:00:00
4726	595	1	16	2020-04-01 02:45:00
4727	595	1	16	2019-08-14 00:30:00
4728	595	1	16	2020-03-16 19:00:00
4729	595	1	16	2019-11-21 02:30:00
4730	595	1	16	2018-09-02 13:30:00
4731	595	1	16	2018-11-07 19:00:00
4732	595	1	16	2019-06-22 15:15:00
4733	595	1	16	2019-04-18 23:00:00
4734	595	1	16	2018-12-06 12:30:00
4735	596	6	15	2018-01-18 15:45:00
4736	596	6	15	2018-01-06 16:15:00
4737	597	7	5	2020-03-28 04:00:00
4738	597	7	5	2020-03-16 09:30:00
4739	597	7	5	2020-09-02 11:30:00
4740	597	7	5	2021-03-10 21:45:00
4741	597	7	5	2019-12-13 05:30:00
4742	597	7	5	2021-02-13 09:15:00
4743	598	15	1	2020-01-22 01:45:00
4744	598	15	1	2021-02-19 20:30:00
4745	598	15	1	2019-06-06 06:30:00
4746	598	15	1	2019-09-17 08:30:00
4747	598	15	1	2020-11-15 16:00:00
4748	598	15	1	2019-09-09 06:00:00
4749	598	15	1	2020-10-14 15:00:00
4750	598	15	1	2021-05-24 13:15:00
4751	598	15	1	2019-11-03 23:45:00
4752	598	15	1	2020-02-26 21:30:00
4753	599	20	17	2019-10-27 22:45:00
4754	599	20	17	2019-04-20 19:00:00
4755	599	20	17	2019-01-01 17:15:00
4756	599	20	17	2018-12-07 00:15:00
4757	599	20	17	2018-05-30 17:45:00
4758	599	20	17	2018-02-15 13:15:00
4759	599	20	17	2019-09-13 11:00:00
4760	599	20	17	2019-12-01 23:30:00
4761	599	20	17	2019-04-07 02:45:00
4762	600	13	17	2021-08-30 12:15:00
4763	600	13	17	2021-09-23 06:15:00
4764	600	13	17	2020-10-04 23:30:00
4765	600	13	17	2021-08-21 00:30:00
4766	600	13	17	2021-07-04 10:15:00
4767	600	13	17	2020-09-02 16:45:00
4768	600	13	17	2020-06-01 03:45:00
4769	600	13	17	2020-10-24 07:30:00
4770	601	8	15	2021-03-16 14:45:00
4771	601	8	15	2020-03-01 02:45:00
4772	601	8	15	2020-02-06 08:45:00
4773	601	8	15	2020-11-28 18:00:00
4774	601	8	15	2019-06-07 23:15:00
4775	601	8	15	2020-08-07 18:30:00
4776	601	8	15	2020-06-03 20:00:00
4777	601	8	15	2020-03-29 18:15:00
4778	602	13	8	2020-06-01 04:15:00
4779	602	13	8	2020-02-23 08:15:00
4780	603	3	15	2021-06-27 06:00:00
4781	603	3	15	2021-01-11 02:00:00
4782	603	3	15	2020-07-29 15:00:00
4783	603	3	15	2019-08-02 08:45:00
4784	603	3	15	2020-06-20 19:45:00
4785	603	3	15	2019-08-29 15:30:00
4786	603	3	15	2020-03-11 00:30:00
4787	603	3	15	2020-09-09 20:45:00
4788	603	3	15	2021-01-23 14:45:00
4789	603	3	15	2020-02-11 09:15:00
4790	603	3	15	2019-11-12 19:00:00
4791	603	3	15	2020-04-26 09:00:00
4792	603	3	15	2020-04-17 19:45:00
4793	603	3	15	2019-08-26 21:30:00
4794	604	9	16	2020-06-27 14:00:00
4795	605	4	5	2021-01-23 21:15:00
4796	605	4	5	2021-02-02 11:30:00
4797	605	4	5	2020-11-17 09:15:00
4798	605	4	5	2019-09-12 19:15:00
4799	606	5	20	2020-01-19 00:30:00
4800	606	5	20	2019-10-24 13:45:00
4801	606	5	20	2019-11-23 10:00:00
4802	606	5	20	2020-03-29 13:30:00
4803	606	5	20	2019-07-20 04:30:00
4804	606	5	20	2019-12-24 04:30:00
4805	606	5	20	2021-03-27 20:00:00
4806	606	5	20	2020-07-30 19:00:00
4807	606	5	20	2020-11-19 20:45:00
4808	606	5	20	2020-02-02 20:45:00
4809	606	5	20	2020-02-12 13:45:00
4810	607	18	7	2019-11-22 02:45:00
4811	607	18	7	2019-12-23 14:30:00
4812	607	18	7	2020-07-17 23:45:00
4813	607	18	7	2020-12-18 05:00:00
4814	607	18	7	2021-04-14 15:00:00
4815	607	18	7	2020-11-17 21:00:00
4816	608	14	3	2019-07-09 07:45:00
4817	608	14	3	2018-11-02 12:30:00
4818	608	14	3	2018-11-24 15:00:00
4819	608	14	3	2019-06-19 08:00:00
4820	609	12	11	2018-11-13 01:00:00
4821	609	12	11	2018-10-01 14:30:00
4822	609	12	11	2018-06-23 05:30:00
4823	609	12	11	2017-05-27 18:00:00
4824	609	12	11	2018-11-30 06:30:00
4825	609	12	11	2017-11-10 22:45:00
4826	609	12	11	2017-11-30 15:30:00
4827	609	12	11	2018-12-10 20:30:00
4828	609	12	11	2018-04-23 00:00:00
4829	609	12	11	2018-03-12 23:45:00
4830	609	12	11	2018-03-08 20:30:00
4831	610	18	13	2017-10-06 20:30:00
4832	610	18	13	2017-10-18 21:45:00
4833	610	18	13	2017-08-23 13:15:00
4834	610	18	13	2019-03-15 05:00:00
4835	610	18	13	2018-10-18 22:00:00
4836	610	18	13	2018-05-23 01:15:00
4837	610	18	13	2017-06-15 03:15:00
4838	611	3	4	2019-03-13 17:30:00
4839	611	3	4	2019-04-26 17:30:00
4840	611	3	4	2020-05-25 03:15:00
4841	611	3	4	2019-04-25 23:15:00
4842	611	3	4	2020-03-24 23:45:00
4843	611	3	4	2019-06-22 15:45:00
4844	611	3	4	2019-01-11 06:15:00
4845	611	3	4	2019-05-26 04:45:00
4846	611	3	4	2020-05-02 13:00:00
4847	611	3	4	2020-05-21 00:30:00
4848	612	10	9	2019-07-28 23:45:00
4849	612	10	9	2020-03-13 09:15:00
4850	612	10	9	2020-02-20 15:30:00
4851	612	10	9	2019-10-25 03:15:00
4852	612	10	9	2020-05-16 02:45:00
4853	612	10	9	2019-09-26 08:30:00
4854	612	10	9	2019-04-08 10:00:00
4855	612	10	9	2018-11-04 13:45:00
4856	612	10	9	2019-01-26 06:00:00
4857	613	7	18	2018-12-06 05:00:00
4858	613	7	18	2019-12-20 00:45:00
4859	613	7	18	2020-05-25 14:00:00
4860	613	7	18	2019-08-20 18:45:00
4861	613	7	18	2019-07-09 21:30:00
4862	613	7	18	2019-03-15 16:30:00
4863	613	7	18	2018-11-24 03:00:00
4864	613	7	18	2018-10-04 19:15:00
4865	613	7	18	2019-02-19 19:45:00
4866	613	7	18	2020-03-22 03:45:00
4867	613	7	18	2019-10-27 11:15:00
4868	613	7	18	2020-02-09 14:45:00
4869	613	7	18	2018-12-29 16:45:00
4870	613	7	18	2019-12-06 06:00:00
4871	614	9	13	2021-01-29 07:15:00
4872	614	9	13	2019-09-15 04:15:00
4873	614	9	13	2020-12-04 14:45:00
4874	614	9	13	2019-04-12 11:45:00
4875	614	9	13	2019-12-01 01:00:00
4876	614	9	13	2020-11-11 16:30:00
4877	614	9	13	2020-03-05 14:30:00
4878	614	9	13	2020-05-18 14:00:00
4879	614	9	13	2019-09-29 04:15:00
4880	614	9	13	2020-02-04 15:00:00
4881	614	9	13	2021-01-08 08:30:00
4882	614	9	13	2019-09-26 07:00:00
4883	614	9	13	2019-09-19 19:00:00
4884	615	6	5	2019-12-03 03:30:00
4885	615	6	5	2019-02-05 04:00:00
4886	615	6	5	2020-05-19 18:00:00
4887	615	6	5	2018-09-21 01:30:00
4888	615	6	5	2019-04-10 06:15:00
4889	615	6	5	2019-05-07 10:15:00
4890	615	6	5	2019-12-11 19:00:00
4891	615	6	5	2020-03-05 01:15:00
4892	615	6	5	2020-01-21 14:30:00
4893	615	6	5	2020-04-01 19:30:00
4894	615	6	5	2019-05-18 13:45:00
4895	615	6	5	2020-07-22 09:30:00
4896	615	6	5	2020-04-02 20:15:00
4897	616	8	4	2018-08-10 21:30:00
4898	616	8	4	2017-06-01 11:15:00
4899	616	8	4	2017-06-10 04:00:00
4900	616	8	4	2017-08-07 23:45:00
4901	616	8	4	2018-02-23 10:00:00
4902	616	8	4	2017-05-20 20:00:00
4903	617	20	4	2018-02-04 05:30:00
4904	617	20	4	2017-08-10 07:00:00
4905	617	20	4	2017-07-07 10:45:00
4906	617	20	4	2018-10-10 17:15:00
4907	618	16	8	2020-02-14 16:30:00
4908	619	9	1	2019-09-22 05:30:00
4909	619	9	1	2019-02-27 01:00:00
4910	619	9	1	2019-09-02 15:15:00
4911	619	9	1	2019-04-25 18:00:00
4912	619	9	1	2018-11-05 14:00:00
4913	619	9	1	2018-09-22 10:00:00
4914	619	9	1	2019-12-24 01:30:00
4915	619	9	1	2018-05-20 21:15:00
4916	619	9	1	2019-07-17 22:15:00
4917	619	9	1	2018-07-14 06:45:00
4918	619	9	1	2019-09-06 10:30:00
4919	619	9	1	2019-01-18 12:30:00
4920	619	9	1	2018-12-01 09:45:00
4921	620	17	13	2018-11-24 12:00:00
4922	620	17	13	2019-12-02 14:30:00
4923	620	17	13	2020-01-24 20:00:00
4924	620	17	13	2019-09-06 20:15:00
4925	620	17	13	2019-12-03 01:15:00
4926	620	17	13	2018-09-06 06:45:00
4927	620	17	13	2019-04-17 18:15:00
4928	620	17	13	2019-03-18 07:00:00
4929	620	17	13	2018-06-06 20:45:00
4930	620	17	13	2018-08-20 08:15:00
4931	620	17	13	2019-12-22 14:15:00
4932	621	10	12	2018-10-15 08:15:00
4933	621	10	12	2017-09-20 17:45:00
4934	621	10	12	2018-11-03 14:00:00
4935	621	10	12	2018-08-01 07:45:00
4936	621	10	12	2019-01-23 06:15:00
4937	622	12	16	2018-01-30 23:15:00
4938	622	12	16	2018-02-15 22:30:00
4939	622	12	16	2017-04-04 04:00:00
4940	622	12	16	2018-02-08 03:00:00
4941	622	12	16	2017-08-09 07:15:00
4942	622	12	16	2017-11-07 18:45:00
4943	622	12	16	2017-03-19 22:30:00
4944	622	12	16	2018-01-12 08:45:00
4945	622	12	16	2018-08-28 07:45:00
4946	623	4	18	2020-12-20 12:00:00
4947	623	4	18	2021-01-30 08:30:00
4948	623	4	18	2019-06-17 21:30:00
4949	624	2	3	2019-03-17 14:00:00
4950	624	2	3	2018-07-16 03:00:00
4951	624	2	3	2020-04-09 17:15:00
4952	624	2	3	2019-05-26 10:45:00
4953	624	2	3	2020-02-23 00:00:00
4954	624	2	3	2019-01-16 23:45:00
4955	625	4	5	2019-04-16 05:15:00
4956	625	4	5	2018-09-22 08:30:00
4957	625	4	5	2019-03-07 11:45:00
4958	625	4	5	2019-11-16 22:30:00
4959	625	4	5	2019-09-19 03:30:00
4960	625	4	5	2019-10-17 20:15:00
4961	625	4	5	2019-01-22 15:00:00
4962	625	4	5	2020-03-03 13:15:00
4963	625	4	5	2018-11-04 14:45:00
4964	625	4	5	2018-05-06 04:45:00
4965	625	4	5	2019-12-22 00:30:00
4966	625	4	5	2019-11-14 03:15:00
4967	626	19	7	2021-10-06 18:45:00
4968	627	9	5	2019-02-06 12:30:00
4969	627	9	5	2019-01-21 14:45:00
4970	627	9	5	2018-09-17 22:30:00
4971	627	9	5	2018-09-21 22:15:00
4972	627	9	5	2019-09-21 20:45:00
4973	627	9	5	2019-02-20 19:45:00
4974	628	4	13	2017-08-04 23:15:00
4975	628	4	13	2018-02-02 23:45:00
4976	628	4	13	2017-12-02 14:45:00
4977	629	17	19	2020-09-21 01:00:00
4978	629	17	19	2020-11-13 16:15:00
4979	629	17	19	2020-06-16 02:45:00
4980	629	17	19	2020-01-03 11:30:00
4981	629	17	19	2019-02-07 23:30:00
4982	629	17	19	2019-08-15 05:45:00
4983	629	17	19	2019-06-21 13:15:00
4984	629	17	19	2020-09-18 13:00:00
4985	629	17	19	2019-11-20 14:00:00
4986	629	17	19	2020-02-04 07:30:00
4987	629	17	19	2020-01-02 02:30:00
4988	629	17	19	2020-09-12 23:30:00
4989	629	17	19	2020-11-18 11:45:00
4990	629	17	19	2019-12-10 09:00:00
4991	629	17	19	2019-12-01 10:00:00
4992	630	20	20	2020-01-07 19:15:00
4993	630	20	20	2020-03-01 13:15:00
4994	630	20	20	2020-10-08 01:15:00
4995	630	20	20	2019-07-10 20:30:00
4996	631	1	20	2019-07-03 03:45:00
4997	631	1	20	2018-10-03 19:00:00
4998	631	1	20	2019-08-08 01:15:00
4999	631	1	20	2019-10-21 05:00:00
5000	631	1	20	2020-05-27 10:00:00
5001	631	1	20	2019-08-06 12:45:00
5002	631	1	20	2018-08-09 22:30:00
5003	631	1	20	2019-08-22 01:45:00
5004	631	1	20	2020-03-16 06:45:00
5005	631	1	20	2019-07-08 22:30:00
5006	631	1	20	2020-06-08 22:45:00
5007	631	1	20	2019-01-01 14:15:00
5008	631	1	20	2018-10-17 20:45:00
5009	631	1	20	2019-07-09 04:00:00
5010	631	1	20	2019-08-10 03:00:00
5011	632	10	18	2018-08-06 01:30:00
5012	632	10	18	2018-07-03 23:45:00
5013	632	10	18	2018-04-20 19:00:00
5014	632	10	18	2017-08-18 21:45:00
5015	632	10	18	2018-11-18 05:45:00
5016	633	3	16	2020-01-17 21:30:00
5017	633	3	16	2020-06-21 06:15:00
5018	633	3	16	2019-09-21 14:00:00
5019	633	3	16	2020-08-07 20:15:00
5020	633	3	16	2020-11-29 17:15:00
5021	633	3	16	2020-05-24 05:45:00
5022	633	3	16	2019-06-01 16:30:00
5023	633	3	16	2019-04-13 01:00:00
5024	634	3	10	2021-01-01 23:45:00
5025	634	3	10	2019-09-21 17:45:00
5026	634	3	10	2019-08-30 08:30:00
5027	634	3	10	2020-04-08 14:30:00
5028	634	3	10	2019-05-14 03:00:00
5029	634	3	10	2020-04-08 22:45:00
5030	634	3	10	2020-10-23 02:15:00
5031	634	3	10	2019-12-30 18:45:00
5032	634	3	10	2019-04-18 18:30:00
5033	634	3	10	2020-02-19 15:30:00
5034	634	3	10	2020-08-12 07:30:00
5035	635	10	8	2020-04-07 13:30:00
5036	635	10	8	2020-05-16 11:45:00
5037	635	10	8	2020-02-16 15:15:00
5038	635	10	8	2020-07-03 18:30:00
5039	635	10	8	2020-05-06 12:00:00
5040	635	10	8	2020-02-22 02:30:00
5041	635	10	8	2021-01-05 16:15:00
5042	635	10	8	2020-12-14 14:00:00
5043	635	10	8	2020-01-07 03:45:00
5044	635	10	8	2020-10-20 03:45:00
5045	636	13	9	2019-08-28 21:15:00
5046	636	13	9	2019-04-01 13:00:00
5047	637	2	18	2020-11-17 17:30:00
5048	637	2	18	2020-08-06 00:00:00
5049	637	2	18	2021-06-10 07:45:00
5050	637	2	18	2021-02-14 03:30:00
5051	637	2	18	2019-11-08 08:30:00
5052	637	2	18	2020-06-01 15:45:00
5053	637	2	18	2021-01-05 17:30:00
5054	637	2	18	2021-07-22 16:00:00
5055	637	2	18	2020-11-25 13:00:00
5056	637	2	18	2021-08-01 11:00:00
5057	637	2	18	2021-04-30 05:00:00
5058	637	2	18	2020-07-18 17:45:00
5059	637	2	18	2020-02-07 12:00:00
5060	638	1	16	2018-05-19 13:30:00
5061	638	1	16	2018-10-15 23:45:00
5062	638	1	16	2017-03-08 11:15:00
5063	638	1	16	2017-04-13 19:00:00
5064	638	1	16	2018-02-10 10:15:00
5065	638	1	16	2018-09-23 14:45:00
5066	638	1	16	2018-06-08 02:15:00
5067	638	1	16	2018-11-27 20:15:00
5068	638	1	16	2018-04-28 08:00:00
5069	638	1	16	2018-09-06 23:15:00
5070	638	1	16	2017-04-28 19:45:00
5071	638	1	16	2017-06-01 11:45:00
5072	639	14	5	2019-06-02 06:45:00
5073	639	14	5	2019-02-06 04:15:00
5074	639	14	5	2020-08-21 05:00:00
5075	639	14	5	2020-05-22 22:00:00
5076	639	14	5	2018-12-28 02:30:00
5077	639	14	5	2019-08-02 10:00:00
5078	639	14	5	2019-05-21 01:15:00
5079	639	14	5	2020-10-02 12:00:00
5080	640	1	7	2020-01-27 09:15:00
5081	640	1	7	2021-06-15 04:30:00
5082	640	1	7	2020-07-30 03:00:00
5083	641	15	6	2017-05-25 22:30:00
5084	641	15	6	2017-07-11 20:45:00
5085	641	15	6	2017-03-28 02:00:00
5086	641	15	6	2018-06-22 17:45:00
5087	641	15	6	2017-07-06 10:45:00
5088	642	12	15	2019-04-12 23:30:00
5089	642	12	15	2017-11-20 01:30:00
5090	642	12	15	2019-02-04 07:15:00
5091	642	12	15	2018-07-25 18:45:00
5092	642	12	15	2019-06-29 11:15:00
5093	642	12	15	2019-10-30 21:00:00
5094	642	12	15	2019-02-09 15:45:00
5095	642	12	15	2018-05-01 17:30:00
5096	642	12	15	2019-02-22 18:45:00
5097	642	12	15	2018-02-08 03:30:00
5098	642	12	15	2018-08-03 16:30:00
5099	642	12	15	2019-09-12 11:15:00
5100	643	17	4	2019-05-12 06:15:00
5101	644	12	1	2017-09-05 23:15:00
5102	644	12	1	2017-10-09 03:15:00
5103	644	12	1	2018-02-01 03:00:00
5104	644	12	1	2017-07-23 11:00:00
5105	644	12	1	2018-06-24 02:30:00
5106	644	12	1	2018-04-01 17:00:00
5107	644	12	1	2017-06-14 06:00:00
5108	644	12	1	2017-08-18 21:45:00
5109	644	12	1	2018-05-18 21:00:00
5110	645	3	20	2020-01-01 10:45:00
5111	645	3	20	2020-08-03 16:00:00
5112	645	3	20	2021-02-23 10:45:00
5113	646	19	15	2020-02-13 20:30:00
5114	646	19	15	2020-01-25 14:30:00
5115	646	19	15	2020-06-21 21:30:00
5116	646	19	15	2021-02-17 18:00:00
5117	646	19	15	2021-02-08 22:45:00
5118	646	19	15	2020-02-13 21:30:00
5119	646	19	15	2020-11-23 06:45:00
5120	646	19	15	2020-05-15 17:45:00
5121	646	19	15	2020-06-13 11:15:00
5122	647	11	9	2019-12-17 08:30:00
5123	647	11	9	2020-05-23 12:15:00
5124	648	3	5	2019-07-12 11:30:00
5125	649	20	10	2020-02-06 02:15:00
5126	649	20	10	2021-01-11 09:45:00
5127	649	20	10	2020-01-06 22:00:00
5128	649	20	10	2020-09-11 11:45:00
5129	649	20	10	2020-09-17 21:45:00
5130	649	20	10	2020-06-26 17:30:00
5131	650	4	19	2018-06-15 04:15:00
5132	650	4	19	2019-05-16 14:00:00
5133	650	4	19	2018-06-05 21:30:00
5134	650	4	19	2018-06-22 07:30:00
5135	650	4	19	2017-12-20 05:00:00
5136	650	4	19	2018-01-02 09:00:00
5137	650	4	19	2019-04-25 18:00:00
5138	650	4	19	2019-01-27 18:45:00
5139	650	4	19	2018-01-27 11:30:00
5140	650	4	19	2019-04-18 00:30:00
5141	650	4	19	2019-10-19 22:45:00
5142	650	4	19	2019-02-26 18:15:00
5143	651	19	6	2019-01-21 23:00:00
5144	651	19	6	2018-11-28 16:45:00
5145	651	19	6	2019-05-10 02:15:00
5146	651	19	6	2018-10-25 05:45:00
5147	651	19	6	2020-07-18 12:00:00
5148	651	19	6	2019-01-07 20:45:00
5149	651	19	6	2019-12-18 01:00:00
5150	651	19	6	2019-08-01 01:45:00
5151	651	19	6	2019-10-16 11:00:00
5152	651	19	6	2019-12-27 04:45:00
5153	651	19	6	2019-05-21 05:15:00
5154	651	19	6	2018-12-06 16:15:00
5155	651	19	6	2019-10-24 11:00:00
5156	651	19	6	2019-08-16 16:45:00
5157	652	19	14	2020-03-13 07:30:00
5158	652	19	14	2019-05-12 16:15:00
5159	653	5	13	2021-03-22 00:30:00
5160	653	5	13	2020-09-23 15:45:00
5161	653	5	13	2021-10-25 20:15:00
5162	653	5	13	2021-06-03 02:45:00
5163	653	5	13	2020-04-26 08:45:00
5164	653	5	13	2020-09-29 19:45:00
5165	653	5	13	2020-09-05 23:15:00
5166	653	5	13	2020-03-15 19:15:00
5167	653	5	13	2021-04-11 02:45:00
5168	654	12	14	2018-04-16 23:15:00
5169	654	12	14	2018-11-07 13:00:00
5170	654	12	14	2018-11-07 21:30:00
5171	654	12	14	2018-05-24 20:30:00
5172	654	12	14	2018-01-24 23:30:00
5173	654	12	14	2018-10-24 12:15:00
5174	654	12	14	2019-08-11 12:15:00
5175	654	12	14	2019-09-22 06:15:00
5176	654	12	14	2018-03-27 15:30:00
5177	655	8	17	2020-12-13 23:00:00
5178	655	8	17	2020-12-27 16:45:00
5179	655	8	17	2020-05-05 19:30:00
5180	655	8	17	2020-05-30 00:15:00
5181	655	8	17	2020-06-08 18:00:00
5182	655	8	17	2021-02-17 02:30:00
5183	655	8	17	2020-11-20 09:45:00
5184	655	8	17	2019-07-01 10:00:00
5185	655	8	17	2020-11-16 03:15:00
5186	655	8	17	2021-05-29 00:45:00
5187	655	8	17	2020-02-21 17:00:00
5188	655	8	17	2021-04-19 04:00:00
5189	656	8	9	2018-04-05 10:15:00
5190	656	8	9	2018-06-16 18:00:00
5191	656	8	9	2019-01-22 10:00:00
5192	656	8	9	2018-03-08 17:00:00
5193	656	8	9	2020-02-04 04:15:00
5194	656	8	9	2019-06-01 20:45:00
5195	656	8	9	2019-06-22 17:45:00
5196	656	8	9	2018-10-11 18:30:00
5197	656	8	9	2019-11-22 21:30:00
5198	657	2	2	2020-12-14 09:30:00
5199	657	2	2	2021-01-15 18:45:00
5200	658	3	3	2019-07-20 00:00:00
5201	658	3	3	2018-06-26 03:30:00
5202	658	3	3	2019-05-08 20:00:00
5203	659	10	1	2019-04-22 18:30:00
5204	659	10	1	2019-01-13 12:15:00
5205	659	10	1	2018-06-08 07:45:00
5206	660	18	5	2018-03-05 00:30:00
5207	660	18	5	2018-02-09 23:00:00
5208	660	18	5	2017-12-04 16:45:00
5209	660	18	5	2019-08-08 16:30:00
5210	660	18	5	2019-05-07 22:15:00
5211	660	18	5	2019-03-25 19:45:00
5212	660	18	5	2018-08-03 07:45:00
5213	660	18	5	2019-08-20 22:15:00
5214	660	18	5	2019-06-01 15:00:00
5215	660	18	5	2019-01-17 00:30:00
5216	660	18	5	2019-03-09 06:00:00
5217	660	18	5	2018-07-20 07:00:00
5218	660	18	5	2019-07-29 10:30:00
5219	661	20	4	2021-08-14 15:00:00
5220	661	20	4	2021-07-27 00:15:00
5221	661	20	4	2020-02-14 21:45:00
5222	661	20	4	2020-12-13 05:45:00
5223	661	20	4	2020-02-04 17:15:00
5224	661	20	4	2020-09-13 01:15:00
5225	662	4	1	2018-09-16 09:00:00
5226	662	4	1	2019-06-16 21:15:00
5227	662	4	1	2019-12-03 05:30:00
5228	662	4	1	2020-01-08 00:00:00
5229	662	4	1	2018-04-05 16:45:00
5230	662	4	1	2018-11-12 03:30:00
5231	662	4	1	2019-02-12 13:15:00
5232	662	4	1	2019-06-20 23:45:00
5233	662	4	1	2019-08-30 06:00:00
5234	662	4	1	2019-04-12 01:45:00
5235	662	4	1	2018-09-21 22:15:00
5236	662	4	1	2020-02-07 10:00:00
5237	662	4	1	2019-11-03 11:15:00
5238	662	4	1	2018-05-11 06:00:00
5239	662	4	1	2019-03-28 02:30:00
5240	663	17	11	2020-05-05 10:45:00
5241	663	17	11	2019-10-27 14:45:00
5242	663	17	11	2019-06-29 18:15:00
5243	663	17	11	2019-09-29 17:30:00
5244	663	17	11	2020-05-08 21:00:00
5245	663	17	11	2019-11-07 05:15:00
5246	663	17	11	2020-07-24 04:30:00
5247	663	17	11	2019-06-30 20:45:00
5248	663	17	11	2020-04-14 03:30:00
5249	664	11	11	2018-02-13 18:15:00
5250	664	11	11	2018-08-21 22:15:00
5251	664	11	11	2017-10-03 04:15:00
5252	664	11	11	2019-02-12 13:30:00
5253	664	11	11	2019-06-25 14:30:00
5254	664	11	11	2018-11-25 13:00:00
5255	664	11	11	2019-01-12 00:30:00
5256	664	11	11	2018-12-28 00:30:00
5257	664	11	11	2018-06-12 16:15:00
5258	665	8	1	2019-03-12 06:15:00
5259	665	8	1	2020-02-10 01:30:00
5260	666	16	13	2020-06-01 00:30:00
5261	667	20	5	2020-12-11 03:30:00
5262	667	20	5	2019-08-08 06:00:00
5263	667	20	5	2021-02-05 03:45:00
5264	667	20	5	2020-09-14 08:00:00
5265	667	20	5	2019-06-24 18:30:00
5266	667	20	5	2020-02-05 22:45:00
5267	667	20	5	2019-04-23 17:30:00
5268	668	15	3	2019-07-14 04:45:00
5269	668	15	3	2019-10-17 19:15:00
5270	668	15	3	2018-10-17 05:45:00
5271	668	15	3	2020-04-19 01:45:00
5272	668	15	3	2019-08-23 12:00:00
5273	668	15	3	2020-03-05 20:00:00
5274	668	15	3	2018-11-14 22:00:00
5275	668	15	3	2019-10-21 04:30:00
5276	668	15	3	2019-03-29 19:00:00
5277	668	15	3	2019-09-12 07:15:00
5278	668	15	3	2020-02-01 05:15:00
5279	668	15	3	2018-12-10 20:30:00
5280	669	1	13	2020-06-17 21:15:00
5281	669	1	13	2020-11-22 05:30:00
5282	669	1	13	2019-08-22 23:30:00
5283	669	1	13	2020-01-16 17:30:00
5284	669	1	13	2020-05-10 18:45:00
5285	669	1	13	2019-09-07 19:00:00
5286	669	1	13	2020-02-20 12:45:00
5287	669	1	13	2020-08-18 12:45:00
5288	669	1	13	2019-10-02 08:45:00
5289	670	14	14	2018-10-21 02:15:00
5290	670	14	14	2019-02-19 04:15:00
5291	670	14	14	2017-09-30 08:00:00
5292	670	14	14	2019-07-08 19:15:00
5293	670	14	14	2018-02-02 21:30:00
5294	670	14	14	2018-12-25 02:45:00
5295	670	14	14	2019-02-03 19:00:00
5296	671	3	12	2018-02-08 18:00:00
5297	671	3	12	2019-01-01 11:45:00
5298	671	3	12	2018-06-04 06:15:00
5299	671	3	12	2019-02-01 23:15:00
5300	671	3	12	2017-06-16 12:15:00
5301	671	3	12	2017-08-15 08:30:00
5302	672	14	15	2020-02-19 14:00:00
5303	672	14	15	2020-12-19 21:45:00
5304	672	14	15	2020-04-24 07:45:00
5305	672	14	15	2020-12-19 19:00:00
5306	672	14	15	2020-06-16 18:45:00
5307	672	14	15	2020-09-15 03:00:00
5308	672	14	15	2020-01-07 02:15:00
5309	672	14	15	2019-09-23 16:45:00
5310	672	14	15	2019-10-28 21:30:00
5311	672	14	15	2021-01-02 13:15:00
5312	672	14	15	2020-03-08 21:00:00
5313	672	14	15	2019-09-12 13:45:00
5314	673	15	1	2019-08-10 03:30:00
5315	673	15	1	2020-08-30 01:30:00
5316	673	15	1	2021-04-30 04:15:00
5317	673	15	1	2020-04-03 10:45:00
5318	674	18	11	2019-02-20 01:45:00
5319	674	18	11	2020-06-27 18:30:00
5320	674	18	11	2019-04-05 06:30:00
5321	674	18	11	2020-05-23 18:30:00
5322	674	18	11	2019-12-22 21:30:00
5323	674	18	11	2020-04-30 23:00:00
5324	674	18	11	2019-04-03 01:30:00
5325	674	18	11	2019-12-29 11:00:00
5326	674	18	11	2019-10-28 17:15:00
5327	674	18	11	2020-06-09 11:45:00
5328	674	18	11	2019-02-02 02:15:00
5329	674	18	11	2019-10-23 04:00:00
5330	674	18	11	2019-01-17 20:15:00
5331	674	18	11	2020-03-21 14:00:00
5332	674	18	11	2019-08-14 21:30:00
5333	675	8	16	2021-12-17 09:30:00
5334	676	14	19	2020-04-27 00:15:00
5335	676	14	19	2020-08-16 03:15:00
5336	676	14	19	2019-02-03 21:15:00
5337	676	14	19	2019-04-02 15:30:00
5338	676	14	19	2020-04-02 04:30:00
5339	676	14	19	2018-12-15 21:45:00
5340	676	14	19	2019-06-22 09:15:00
5341	676	14	19	2018-12-18 06:30:00
5342	676	14	19	2019-11-15 02:00:00
5343	676	14	19	2018-11-24 11:30:00
5344	676	14	19	2020-05-05 14:45:00
5345	676	14	19	2018-12-14 06:30:00
5346	677	14	1	2020-04-09 00:15:00
5347	677	14	1	2020-08-07 23:15:00
5348	677	14	1	2019-11-18 09:45:00
5349	677	14	1	2019-06-01 23:00:00
5350	677	14	1	2019-07-16 14:30:00
5351	677	14	1	2020-06-17 00:15:00
5352	677	14	1	2020-04-18 08:45:00
5353	677	14	1	2019-12-08 00:15:00
5354	677	14	1	2020-03-05 08:15:00
5355	677	14	1	2019-08-21 17:30:00
5356	677	14	1	2019-06-22 02:30:00
5357	677	14	1	2019-08-28 15:45:00
5358	677	14	1	2020-02-13 03:15:00
5359	677	14	1	2020-06-28 01:45:00
5360	677	14	1	2020-03-20 12:30:00
5361	678	14	7	2021-04-26 00:15:00
5362	678	14	7	2021-11-19 12:45:00
5363	678	14	7	2021-01-03 17:30:00
5364	678	14	7	2021-04-07 19:15:00
5365	678	14	7	2020-04-28 06:30:00
5366	678	14	7	2020-11-18 13:15:00
5367	678	14	7	2021-01-17 22:00:00
5368	678	14	7	2021-12-08 22:00:00
5369	678	14	7	2020-11-11 21:45:00
5370	678	14	7	2021-06-08 09:00:00
5371	678	14	7	2020-10-20 21:30:00
5372	678	14	7	2021-01-12 07:15:00
5373	678	14	7	2020-04-06 18:45:00
5374	679	3	19	2021-09-03 07:00:00
5375	679	3	19	2020-11-02 11:00:00
5376	679	3	19	2020-08-16 00:30:00
5377	679	3	19	2020-11-26 00:00:00
5378	679	3	19	2021-09-01 13:30:00
5379	679	3	19	2019-12-03 11:15:00
5380	679	3	19	2020-04-09 02:45:00
5381	680	8	4	2018-10-13 09:30:00
5382	680	8	4	2018-08-27 08:15:00
5383	680	8	4	2020-03-12 19:00:00
5384	681	20	14	2018-02-04 18:15:00
5385	681	20	14	2019-01-12 06:30:00
5386	681	20	14	2017-12-25 15:45:00
5387	681	20	14	2018-06-16 16:00:00
5388	681	20	14	2019-04-22 01:00:00
5389	682	9	20	2021-06-04 04:00:00
5390	682	9	20	2020-04-14 18:30:00
5391	682	9	20	2021-12-25 15:00:00
5392	682	9	20	2021-06-04 11:15:00
5393	682	9	20	2021-10-28 06:45:00
5394	682	9	20	2020-08-20 20:00:00
5395	682	9	20	2020-01-05 15:15:00
5396	682	9	20	2021-09-04 06:45:00
5397	682	9	20	2021-01-26 16:15:00
5398	682	9	20	2020-08-08 14:45:00
5399	682	9	20	2020-06-29 17:30:00
5400	682	9	20	2020-12-06 01:00:00
5401	683	6	18	2020-11-24 20:30:00
5402	683	6	18	2019-12-13 19:00:00
5403	683	6	18	2020-05-23 01:15:00
5404	683	6	18	2021-01-16 11:15:00
5405	683	6	18	2019-10-04 01:15:00
5406	683	6	18	2021-01-10 12:15:00
5407	683	6	18	2020-02-01 09:15:00
5408	683	6	18	2019-07-02 06:15:00
5409	683	6	18	2020-09-17 14:45:00
5410	683	6	18	2019-08-14 23:15:00
5411	684	13	19	2020-01-21 20:00:00
5412	684	13	19	2019-11-12 03:30:00
5413	684	13	19	2018-08-30 14:00:00
5414	684	13	19	2019-10-10 18:45:00
5415	684	13	19	2018-05-19 00:15:00
5416	684	13	19	2020-02-02 04:00:00
5417	684	13	19	2019-02-17 10:00:00
5418	684	13	19	2019-12-02 11:15:00
5419	684	13	19	2019-06-19 16:15:00
5420	684	13	19	2018-09-19 04:30:00
5421	684	13	19	2018-10-09 20:15:00
5422	684	13	19	2019-10-17 06:45:00
5423	684	13	19	2019-05-23 23:15:00
5424	685	19	19	2021-09-18 03:15:00
5425	685	19	19	2021-09-23 21:00:00
5426	685	19	19	2021-01-30 01:45:00
5427	685	19	19	2020-04-08 15:00:00
5428	685	19	19	2021-02-20 17:15:00
5429	685	19	19	2020-05-26 16:45:00
5430	685	19	19	2021-03-27 12:15:00
5431	685	19	19	2021-08-05 03:15:00
5432	685	19	19	2020-04-01 06:00:00
5433	685	19	19	2020-08-12 01:45:00
5434	685	19	19	2020-01-02 19:45:00
5435	686	1	15	2018-04-28 00:15:00
5436	686	1	15	2017-12-26 14:30:00
5437	687	1	5	2020-03-23 15:00:00
5438	687	1	5	2019-11-13 09:45:00
5439	687	1	5	2021-04-18 20:45:00
5440	687	1	5	2020-12-29 11:30:00
5441	687	1	5	2020-07-21 21:00:00
5442	687	1	5	2020-02-18 15:30:00
5443	687	1	5	2021-01-26 11:00:00
5444	687	1	5	2021-02-05 21:45:00
5445	688	11	19	2019-11-02 06:15:00
5446	688	11	19	2018-10-30 10:00:00
5447	688	11	19	2018-06-01 09:15:00
5448	688	11	19	2018-03-08 16:15:00
5449	688	11	19	2019-02-22 01:30:00
5450	688	11	19	2018-09-21 18:00:00
5451	688	11	19	2018-07-19 19:00:00
5452	688	11	19	2019-03-27 17:45:00
5453	688	11	19	2018-05-27 15:15:00
5454	688	11	19	2018-10-19 16:45:00
5455	688	11	19	2019-12-16 08:15:00
5456	688	11	19	2018-09-10 05:15:00
5457	688	11	19	2018-10-01 17:00:00
5458	689	15	2	2021-02-14 08:30:00
5459	689	15	2	2021-02-25 06:30:00
5460	690	12	19	2019-02-06 09:30:00
5461	690	12	19	2020-02-03 10:00:00
5462	690	12	19	2020-05-06 03:45:00
5463	690	12	19	2019-03-16 14:15:00
5464	690	12	19	2020-06-19 08:15:00
5465	690	12	19	2020-10-08 20:00:00
5466	690	12	19	2019-08-22 19:00:00
5467	690	12	19	2020-02-01 03:30:00
5468	691	9	3	2020-07-06 09:15:00
5469	691	9	3	2019-10-02 05:00:00
5470	691	9	3	2020-10-29 11:00:00
5471	691	9	3	2020-01-11 17:15:00
5472	691	9	3	2019-04-09 22:15:00
5473	691	9	3	2020-05-15 20:30:00
5474	691	9	3	2020-04-01 22:15:00
5475	691	9	3	2020-06-10 05:30:00
5476	691	9	3	2019-04-19 03:15:00
5477	692	12	11	2019-12-12 03:45:00
5478	692	12	11	2020-08-01 15:00:00
5479	692	12	11	2020-05-03 11:30:00
5480	692	12	11	2020-06-21 06:15:00
5481	692	12	11	2019-07-06 18:00:00
5482	692	12	11	2020-11-08 05:00:00
5483	692	12	11	2019-02-16 09:00:00
5484	692	12	11	2019-02-10 20:15:00
5485	692	12	11	2019-02-06 21:00:00
5486	693	13	2	2018-03-05 22:00:00
5487	693	13	2	2018-03-26 03:00:00
5488	693	13	2	2018-05-10 01:45:00
5489	693	13	2	2019-04-20 12:45:00
5490	693	13	2	2018-05-04 12:15:00
5491	693	13	2	2018-07-25 07:45:00
5492	693	13	2	2019-05-27 23:30:00
5493	693	13	2	2019-03-01 10:30:00
5494	693	13	2	2019-03-01 06:15:00
5495	693	13	2	2018-07-29 00:45:00
5496	693	13	2	2019-03-21 03:45:00
5497	693	13	2	2018-04-10 15:45:00
5498	693	13	2	2018-01-18 15:00:00
5499	693	13	2	2017-07-12 05:30:00
5500	693	13	2	2018-09-28 15:00:00
5501	694	9	2	2019-05-06 11:00:00
5502	694	9	2	2020-12-19 22:45:00
5503	694	9	2	2019-11-01 20:45:00
5504	694	9	2	2019-07-28 10:15:00
5505	694	9	2	2019-11-07 12:30:00
5506	694	9	2	2019-12-29 16:00:00
5507	694	9	2	2020-09-16 04:00:00
5508	694	9	2	2020-05-29 08:45:00
5509	695	4	3	2017-08-23 08:30:00
5510	695	4	3	2018-05-28 03:00:00
5511	695	4	3	2017-06-04 20:15:00
5512	695	4	3	2018-06-15 09:45:00
5513	695	4	3	2017-08-16 06:15:00
5514	695	4	3	2018-12-01 17:30:00
5515	695	4	3	2018-01-16 06:30:00
5516	695	4	3	2018-04-22 00:45:00
5517	695	4	3	2018-10-24 16:00:00
5518	695	4	3	2017-07-20 02:15:00
5519	695	4	3	2018-02-16 19:15:00
5520	695	4	3	2017-07-05 00:15:00
5521	695	4	3	2018-12-25 00:15:00
5522	695	4	3	2018-02-07 04:45:00
5523	696	13	3	2021-01-05 03:15:00
5524	696	13	3	2019-07-04 14:00:00
5525	696	13	3	2020-10-22 22:30:00
5526	696	13	3	2020-05-16 12:30:00
5527	696	13	3	2021-02-17 08:00:00
5528	696	13	3	2020-06-24 07:30:00
5529	696	13	3	2019-09-29 13:00:00
5530	696	13	3	2019-07-06 18:15:00
5531	696	13	3	2019-05-18 21:15:00
5532	696	13	3	2020-09-22 12:45:00
5533	696	13	3	2020-04-18 17:15:00
5534	697	12	18	2019-07-03 17:45:00
5535	697	12	18	2020-05-22 09:15:00
5536	697	12	18	2020-10-29 01:45:00
5537	697	12	18	2020-07-18 19:00:00
5538	697	12	18	2019-08-23 20:15:00
5539	697	12	18	2019-01-03 21:30:00
5540	697	12	18	2019-07-14 22:00:00
5541	697	12	18	2020-11-07 06:30:00
5542	698	6	5	2018-07-25 14:30:00
5543	698	6	5	2019-03-18 16:30:00
5544	698	6	5	2018-10-06 07:30:00
5545	698	6	5	2019-08-22 12:30:00
5546	699	3	7	2018-10-22 06:00:00
5547	699	3	7	2019-09-19 03:30:00
5548	699	3	7	2018-12-08 22:30:00
5549	699	3	7	2018-05-07 12:30:00
5550	699	3	7	2018-07-16 11:30:00
5551	699	3	7	2019-07-17 21:00:00
5552	699	3	7	2018-02-14 04:45:00
5553	699	3	7	2018-05-29 14:00:00
5554	699	3	7	2018-08-03 21:15:00
5555	700	19	11	2020-09-17 22:15:00
5556	700	19	11	2019-06-07 21:15:00
5557	700	19	11	2018-12-26 05:00:00
5558	700	19	11	2020-06-20 19:00:00
5559	700	19	11	2018-12-21 14:00:00
5560	700	19	11	2019-10-08 23:00:00
5561	700	19	11	2018-12-11 05:00:00
5562	701	2	8	2020-07-25 11:00:00
5563	701	2	8	2019-02-25 17:00:00
5564	701	2	8	2019-12-27 23:30:00
5565	701	2	8	2019-05-14 02:30:00
5566	701	2	8	2019-12-30 18:30:00
5567	701	2	8	2019-02-08 08:30:00
5568	701	2	8	2019-06-26 03:00:00
5569	701	2	8	2019-11-24 08:00:00
5570	701	2	8	2019-09-18 02:00:00
5571	701	2	8	2019-04-14 22:00:00
5572	702	19	14	2019-03-25 05:00:00
5573	702	19	14	2017-12-23 21:30:00
5574	702	19	14	2019-09-28 11:45:00
5575	702	19	14	2018-01-07 17:00:00
5576	702	19	14	2018-09-24 05:15:00
5577	702	19	14	2018-07-29 08:45:00
5578	702	19	14	2017-10-07 06:15:00
5579	702	19	14	2019-07-16 07:30:00
5580	702	19	14	2018-03-20 04:45:00
5581	703	12	18	2020-04-02 06:45:00
5582	703	12	18	2020-05-01 12:15:00
5583	703	12	18	2018-12-18 20:15:00
5584	703	12	18	2020-04-04 04:15:00
5585	703	12	18	2019-08-20 04:45:00
5586	703	12	18	2019-08-06 03:00:00
5587	703	12	18	2018-12-03 22:45:00
5588	703	12	18	2018-09-01 13:15:00
5589	703	12	18	2018-09-25 07:15:00
5590	703	12	18	2020-04-23 18:00:00
5591	703	12	18	2020-03-07 23:30:00
5592	703	12	18	2019-11-02 06:15:00
5593	703	12	18	2018-10-09 15:00:00
5594	703	12	18	2019-12-03 00:45:00
5595	703	12	18	2018-12-22 02:30:00
5596	704	20	3	2020-05-01 22:15:00
5597	704	20	3	2020-06-29 11:45:00
5598	704	20	3	2021-09-06 20:00:00
5599	704	20	3	2020-12-29 05:30:00
5600	704	20	3	2021-05-10 11:15:00
5601	704	20	3	2021-04-08 19:15:00
5602	704	20	3	2020-05-25 00:00:00
5603	704	20	3	2021-03-09 01:30:00
5604	704	20	3	2021-10-28 06:15:00
5605	705	5	8	2017-05-30 04:00:00
5606	705	5	8	2017-04-30 12:45:00
5607	705	5	8	2017-04-21 02:30:00
5608	705	5	8	2017-04-03 21:30:00
5609	706	20	16	2019-03-11 11:30:00
5610	706	20	16	2018-12-16 16:30:00
5611	706	20	16	2019-06-19 12:00:00
5612	706	20	16	2019-03-08 11:45:00
5613	706	20	16	2019-01-15 09:45:00
5614	706	20	16	2018-07-06 16:15:00
5615	706	20	16	2018-04-22 21:45:00
5616	706	20	16	2018-10-29 02:15:00
5617	707	15	9	2018-09-20 10:30:00
5618	707	15	9	2018-07-10 09:15:00
5619	707	15	9	2019-04-28 11:00:00
5620	707	15	9	2018-07-22 04:30:00
5621	707	15	9	2019-06-24 10:30:00
5622	707	15	9	2019-12-08 13:15:00
5623	707	15	9	2019-12-03 13:15:00
5624	707	15	9	2019-05-03 02:15:00
5625	707	15	9	2018-11-16 05:00:00
5626	707	15	9	2019-11-27 21:45:00
5627	707	15	9	2020-01-12 04:00:00
5628	707	15	9	2020-01-10 06:00:00
5629	707	15	9	2020-02-19 06:30:00
5630	707	15	9	2020-02-18 15:45:00
5631	708	1	19	2020-12-10 09:15:00
5632	708	1	19	2019-09-25 02:30:00
5633	708	1	19	2020-08-23 16:00:00
5634	708	1	19	2020-01-22 20:45:00
5635	708	1	19	2021-01-15 08:30:00
5636	708	1	19	2019-09-29 01:15:00
5637	708	1	19	2020-10-18 14:30:00
5638	709	6	6	2018-01-18 15:00:00
5639	709	6	6	2018-12-15 12:00:00
5640	709	6	6	2019-02-10 22:30:00
5641	709	6	6	2019-03-02 20:00:00
5642	710	1	9	2019-07-04 10:45:00
5643	710	1	9	2020-02-07 04:45:00
5644	710	1	9	2020-04-03 18:15:00
5645	710	1	9	2020-10-27 20:00:00
5646	710	1	9	2020-10-29 13:30:00
5647	710	1	9	2020-06-15 16:00:00
5648	710	1	9	2021-03-15 09:00:00
5649	710	1	9	2020-07-10 21:30:00
5650	710	1	9	2020-07-16 11:00:00
5651	711	17	9	2020-01-24 21:30:00
5652	712	14	5	2020-05-21 17:00:00
5653	712	14	5	2019-04-18 08:00:00
5654	712	14	5	2019-03-04 00:30:00
5655	712	14	5	2019-11-27 01:30:00
5656	712	14	5	2018-12-03 14:30:00
5657	712	14	5	2018-09-12 16:30:00
5658	712	14	5	2020-03-08 09:00:00
5659	713	8	14	2020-07-18 02:00:00
5660	713	8	14	2021-05-26 20:45:00
5661	713	8	14	2020-05-09 13:00:00
5662	713	8	14	2021-03-19 07:00:00
5663	713	8	14	2020-08-15 22:00:00
5664	713	8	14	2020-06-09 00:45:00
5665	713	8	14	2020-09-29 03:30:00
5666	713	8	14	2021-05-16 10:30:00
5667	714	11	11	2020-01-01 01:30:00
5668	714	11	11	2021-01-02 05:00:00
5669	714	11	11	2020-11-06 13:00:00
5670	714	11	11	2021-09-22 10:45:00
5671	714	11	11	2020-01-02 08:30:00
5672	714	11	11	2020-01-01 05:30:00
5673	714	11	11	2020-11-27 17:45:00
5674	714	11	11	2020-04-10 12:15:00
5675	714	11	11	2020-02-09 12:15:00
5676	715	8	5	2018-03-02 22:15:00
5677	715	8	5	2018-08-26 09:00:00
5678	715	8	5	2018-05-29 07:15:00
5679	715	8	5	2019-10-27 13:00:00
5680	715	8	5	2019-04-27 08:30:00
5681	715	8	5	2018-11-13 19:00:00
5682	715	8	5	2018-04-29 16:30:00
5683	715	8	5	2019-05-11 11:00:00
5684	715	8	5	2018-06-14 13:00:00
5685	715	8	5	2019-10-22 23:15:00
5686	715	8	5	2018-05-22 22:45:00
5687	716	5	9	2021-06-10 15:00:00
5688	716	5	9	2020-11-02 20:30:00
5689	716	5	9	2020-09-20 02:30:00
5690	716	5	9	2020-04-21 23:00:00
5691	716	5	9	2021-01-14 12:15:00
5692	716	5	9	2021-01-10 00:15:00
5693	717	16	7	2020-11-02 07:30:00
5694	717	16	7	2020-06-21 16:30:00
5695	717	16	7	2021-09-24 09:30:00
5696	717	16	7	2021-02-05 05:00:00
5697	717	16	7	2020-09-22 23:15:00
5698	717	16	7	2020-01-24 22:45:00
5699	717	16	7	2020-08-03 18:45:00
5700	717	16	7	2020-11-13 08:15:00
5701	717	16	7	2021-01-09 06:30:00
5702	717	16	7	2021-02-12 21:15:00
5703	718	12	6	2020-08-13 13:30:00
5704	718	12	6	2021-02-07 05:45:00
5705	718	12	6	2021-01-29 12:30:00
5706	718	12	6	2019-12-08 09:30:00
5707	718	12	6	2020-08-03 03:30:00
5708	718	12	6	2020-06-02 17:00:00
5709	718	12	6	2021-04-10 02:30:00
5710	718	12	6	2020-11-03 09:45:00
5711	718	12	6	2020-01-16 00:30:00
5712	718	12	6	2020-08-14 10:00:00
5713	718	12	6	2020-07-22 21:45:00
5714	718	12	6	2021-10-22 21:30:00
5715	719	11	13	2019-04-07 23:30:00
5716	720	19	1	2018-01-07 00:45:00
5717	720	19	1	2017-09-05 22:30:00
5718	720	19	1	2018-11-26 17:15:00
5719	720	19	1	2018-07-07 06:45:00
5720	720	19	1	2018-10-09 00:15:00
5721	720	19	1	2018-07-28 17:30:00
5722	720	19	1	2017-06-14 22:30:00
5723	720	19	1	2019-04-25 04:00:00
5724	720	19	1	2018-04-16 20:45:00
5725	721	19	4	2018-06-14 17:45:00
5726	721	19	4	2020-04-26 07:00:00
5727	722	1	2	2018-07-20 16:45:00
5728	722	1	2	2017-12-07 13:15:00
5729	722	1	2	2017-12-03 17:15:00
5730	722	1	2	2017-08-24 08:45:00
5731	722	1	2	2018-08-01 03:45:00
5732	723	20	1	2019-02-22 12:45:00
5733	723	20	1	2018-06-21 20:15:00
5734	723	20	1	2018-03-26 07:00:00
5735	723	20	1	2019-04-03 17:30:00
5736	723	20	1	2019-07-05 01:00:00
5737	723	20	1	2019-06-02 11:15:00
5738	723	20	1	2019-01-20 11:00:00
5739	724	10	13	2018-07-30 01:45:00
5740	724	10	13	2020-05-29 11:15:00
5741	724	10	13	2019-11-05 06:00:00
5742	724	10	13	2019-06-09 15:30:00
5743	724	10	13	2018-12-13 23:15:00
5744	724	10	13	2018-06-19 23:30:00
5745	724	10	13	2020-02-04 15:15:00
5746	724	10	13	2019-05-09 16:15:00
5747	725	15	2	2017-12-13 04:45:00
5748	725	15	2	2018-02-01 20:45:00
5749	725	15	2	2017-11-03 07:45:00
5750	725	15	2	2017-07-16 02:00:00
5751	725	15	2	2019-03-24 13:15:00
5752	725	15	2	2017-10-01 09:00:00
5753	725	15	2	2018-08-24 04:15:00
5754	725	15	2	2018-09-07 16:30:00
5755	725	15	2	2017-08-30 02:30:00
5756	725	15	2	2017-09-25 12:30:00
5757	725	15	2	2018-12-03 08:00:00
5758	725	15	2	2018-06-15 14:00:00
5759	725	15	2	2017-07-27 02:15:00
5760	725	15	2	2018-11-13 00:30:00
5761	726	15	14	2019-12-11 16:15:00
5762	726	15	14	2019-06-23 20:45:00
5763	726	15	14	2020-03-23 21:15:00
5764	726	15	14	2018-12-26 14:30:00
5765	726	15	14	2019-08-01 00:00:00
5766	726	15	14	2020-02-04 13:30:00
5767	726	15	14	2019-07-25 21:45:00
5768	726	15	14	2018-11-18 12:15:00
5769	726	15	14	2019-04-25 21:15:00
5770	726	15	14	2020-08-30 19:30:00
5771	726	15	14	2019-02-23 07:00:00
5772	726	15	14	2020-08-04 13:45:00
5773	726	15	14	2019-09-19 09:00:00
5774	726	15	14	2019-05-25 10:30:00
5775	727	19	4	2020-02-10 13:45:00
5776	727	19	4	2019-08-24 20:45:00
5777	727	19	4	2019-06-14 01:00:00
5778	727	19	4	2019-01-29 05:45:00
5779	727	19	4	2019-12-06 18:15:00
5780	727	19	4	2018-06-29 23:00:00
5781	727	19	4	2019-05-22 22:15:00
5782	727	19	4	2019-02-12 21:15:00
5783	727	19	4	2020-01-22 21:00:00
5784	727	19	4	2019-11-05 19:15:00
5785	727	19	4	2018-06-08 07:45:00
5786	727	19	4	2020-04-30 02:30:00
5787	727	19	4	2020-01-11 10:00:00
5788	727	19	4	2018-12-20 01:00:00
5789	727	19	4	2018-10-28 17:00:00
5790	728	20	17	2019-07-20 15:00:00
5791	728	20	17	2019-08-26 08:30:00
5792	728	20	17	2019-06-11 16:15:00
5793	728	20	17	2018-01-24 02:15:00
5794	728	20	17	2018-09-17 14:00:00
5795	728	20	17	2019-03-15 07:00:00
5796	728	20	17	2018-10-20 13:45:00
5797	728	20	17	2019-10-07 21:00:00
5798	729	13	4	2021-01-23 08:30:00
5799	729	13	4	2019-12-09 10:30:00
5800	729	13	4	2020-10-07 07:15:00
5801	729	13	4	2020-04-10 02:00:00
5802	729	13	4	2019-10-05 07:45:00
5803	729	13	4	2019-08-28 17:15:00
5804	729	13	4	2020-11-15 02:00:00
5805	729	13	4	2020-01-05 19:30:00
5806	729	13	4	2019-04-09 17:00:00
5807	729	13	4	2019-07-01 01:00:00
5808	729	13	4	2020-11-22 08:15:00
5809	730	1	17	2019-07-08 18:00:00
5810	731	1	20	2020-06-23 14:15:00
5811	731	1	20	2019-02-20 22:15:00
5812	731	1	20	2019-04-24 09:00:00
5813	732	11	8	2021-05-29 21:15:00
5814	732	11	8	2021-01-01 21:30:00
5815	732	11	8	2021-04-05 18:45:00
5816	732	11	8	2021-06-20 23:00:00
5817	732	11	8	2020-06-04 03:30:00
5818	732	11	8	2021-03-01 16:15:00
5819	732	11	8	2021-03-05 19:30:00
5820	732	11	8	2020-09-15 02:30:00
5821	732	11	8	2020-02-03 02:30:00
5822	732	11	8	2020-12-06 21:45:00
5823	732	11	8	2021-12-20 11:45:00
5824	732	11	8	2021-12-29 19:30:00
5825	733	20	9	2020-02-23 03:15:00
5826	733	20	9	2020-10-26 05:15:00
5827	733	20	9	2020-07-23 12:00:00
5828	733	20	9	2019-08-05 23:30:00
5829	733	20	9	2020-09-28 16:00:00
5830	733	20	9	2019-05-04 16:45:00
5831	733	20	9	2020-04-11 01:15:00
5832	733	20	9	2019-04-18 23:30:00
5833	734	8	8	2020-01-18 20:45:00
5834	734	8	8	2021-07-05 12:15:00
5835	734	8	8	2021-01-12 08:00:00
5836	734	8	8	2021-01-18 04:15:00
5837	735	8	13	2018-10-17 14:30:00
5838	735	8	13	2019-09-11 17:30:00
5839	735	8	13	2019-09-20 14:30:00
5840	735	8	13	2018-08-10 10:15:00
5841	735	8	13	2018-02-03 17:45:00
5842	735	8	13	2018-11-23 11:30:00
5843	735	8	13	2019-01-26 05:00:00
5844	735	8	13	2018-12-02 02:30:00
5845	735	8	13	2019-01-17 13:45:00
5846	736	1	12	2019-02-24 05:30:00
5847	736	1	12	2018-12-13 07:30:00
5848	736	1	12	2017-11-07 14:00:00
5849	736	1	12	2017-03-01 07:15:00
5850	736	1	12	2017-03-01 00:00:00
5851	736	1	12	2019-02-19 01:45:00
5852	736	1	12	2018-12-20 14:30:00
5853	736	1	12	2018-11-27 04:30:00
5854	736	1	12	2017-08-03 05:45:00
5855	736	1	12	2019-02-08 14:45:00
5856	736	1	12	2017-06-08 03:45:00
5857	736	1	12	2018-01-23 03:30:00
5858	736	1	12	2018-07-05 14:45:00
5859	736	1	12	2018-01-29 13:45:00
5860	737	3	2	2019-10-22 15:30:00
5861	737	3	2	2019-04-11 23:30:00
5862	737	3	2	2019-03-02 07:30:00
5863	737	3	2	2019-10-13 14:00:00
5864	737	3	2	2018-05-29 12:45:00
5865	737	3	2	2019-01-04 18:15:00
5866	737	3	2	2018-10-13 21:15:00
5867	737	3	2	2019-08-12 01:30:00
5868	737	3	2	2018-11-01 05:30:00
5869	737	3	2	2019-01-01 15:45:00
5870	738	2	2	2020-01-04 03:00:00
5871	738	2	2	2020-04-19 11:30:00
5872	738	2	2	2019-08-01 06:00:00
5873	738	2	2	2020-09-15 09:00:00
5874	738	2	2	2020-01-09 02:30:00
5875	738	2	2	2020-04-24 02:15:00
5876	738	2	2	2020-12-13 09:00:00
5877	738	2	2	2019-04-21 00:00:00
5878	738	2	2	2020-10-03 01:30:00
5879	738	2	2	2020-09-21 17:30:00
5880	739	6	20	2020-06-18 11:15:00
5881	739	6	20	2021-01-16 22:45:00
5882	739	6	20	2021-01-27 07:30:00
5883	739	6	20	2021-07-01 04:30:00
5884	739	6	20	2019-11-08 07:15:00
5885	739	6	20	2020-10-17 10:30:00
5886	739	6	20	2020-09-06 00:00:00
5887	740	17	19	2019-02-03 03:30:00
5888	740	17	19	2020-01-29 11:30:00
5889	740	17	19	2019-12-25 08:00:00
5890	740	17	19	2018-11-07 17:00:00
5891	740	17	19	2018-11-18 21:15:00
5892	740	17	19	2019-11-06 05:15:00
5893	740	17	19	2020-03-14 02:00:00
5894	740	17	19	2019-08-03 07:30:00
5895	740	17	19	2020-08-27 15:30:00
5896	740	17	19	2019-05-08 23:15:00
5897	741	19	1	2018-04-20 11:15:00
5898	741	19	1	2019-03-02 02:15:00
5899	741	19	1	2019-08-04 00:00:00
5900	741	19	1	2019-12-07 11:45:00
5901	741	19	1	2019-11-26 00:00:00
5902	741	19	1	2019-08-28 18:30:00
5903	741	19	1	2019-06-05 10:00:00
5904	741	19	1	2018-09-18 00:30:00
5905	741	19	1	2018-02-13 19:30:00
5906	741	19	1	2019-11-18 02:45:00
5907	741	19	1	2019-02-05 06:45:00
5908	742	15	5	2021-03-02 12:00:00
5909	742	15	5	2020-10-30 09:30:00
5910	742	15	5	2020-05-08 13:00:00
5911	742	15	5	2019-12-07 20:45:00
5912	742	15	5	2021-01-30 14:15:00
5913	742	15	5	2020-12-09 22:45:00
5914	742	15	5	2020-06-05 19:00:00
5915	743	10	11	2019-02-04 21:30:00
5916	743	10	11	2020-04-07 00:30:00
5917	743	10	11	2019-02-03 00:15:00
5918	744	2	13	2020-07-08 03:45:00
5919	744	2	13	2019-11-26 06:30:00
5920	744	2	13	2019-06-07 11:00:00
5921	744	2	13	2019-03-17 08:00:00
5922	744	2	13	2019-02-09 03:45:00
5923	744	2	13	2020-05-26 23:30:00
5924	744	2	13	2019-09-12 11:30:00
5925	744	2	13	2020-02-03 05:30:00
5926	744	2	13	2020-10-01 14:00:00
5927	745	15	20	2020-06-06 03:00:00
5928	745	15	20	2020-09-09 07:00:00
5929	745	15	20	2019-09-28 15:45:00
5930	745	15	20	2021-01-24 01:45:00
5931	745	15	20	2019-12-29 11:00:00
5932	745	15	20	2021-01-22 07:15:00
5933	745	15	20	2019-08-12 10:15:00
5934	746	19	7	2020-08-02 19:30:00
5935	746	19	7	2020-01-12 10:00:00
5936	746	19	7	2020-02-01 22:30:00
5937	746	19	7	2021-06-15 04:15:00
5938	746	19	7	2020-02-16 21:15:00
5939	746	19	7	2020-05-16 00:45:00
5940	746	19	7	2020-09-27 09:00:00
5941	746	19	7	2021-04-20 03:00:00
5942	746	19	7	2019-12-26 13:30:00
5943	746	19	7	2020-08-17 19:30:00
5944	747	8	5	2021-08-27 03:45:00
5945	747	8	5	2021-09-27 00:45:00
5946	747	8	5	2020-09-06 09:15:00
5947	747	8	5	2020-07-19 08:15:00
5948	748	14	18	2020-03-26 03:15:00
5949	748	14	18	2020-04-20 08:15:00
5950	748	14	18	2021-07-21 00:15:00
5951	748	14	18	2019-11-23 08:00:00
5952	748	14	18	2020-07-15 16:45:00
5953	748	14	18	2021-02-27 00:45:00
5954	748	14	18	2020-11-30 20:00:00
5955	748	14	18	2020-09-14 15:15:00
5956	748	14	18	2020-12-02 00:00:00
5957	749	2	2	2019-04-04 14:45:00
5958	749	2	2	2019-07-30 10:30:00
5959	749	2	2	2018-03-22 01:00:00
5960	749	2	2	2019-07-06 09:30:00
5961	749	2	2	2018-01-11 06:30:00
5962	749	2	2	2018-08-08 10:45:00
5963	749	2	2	2019-02-10 07:15:00
5964	749	2	2	2019-02-26 10:00:00
5965	749	2	2	2017-11-29 09:15:00
5966	750	1	7	2019-12-10 04:30:00
5967	750	1	7	2019-08-04 02:45:00
5968	750	1	7	2019-04-28 15:30:00
5969	751	15	17	2018-07-04 20:15:00
5970	751	15	17	2019-04-23 05:30:00
5971	751	15	17	2018-05-18 00:30:00
5972	751	15	17	2019-04-07 16:00:00
5973	752	20	4	2019-04-27 04:30:00
5974	752	20	4	2020-07-12 16:00:00
5975	752	20	4	2020-05-01 12:15:00
5976	752	20	4	2018-11-23 02:15:00
5977	752	20	4	2019-04-08 23:00:00
5978	752	20	4	2020-06-23 19:15:00
5979	753	15	16	2020-02-23 23:45:00
5980	753	15	16	2020-11-21 14:45:00
5981	753	15	16	2021-02-05 13:15:00
5982	753	15	16	2020-03-22 19:00:00
5983	753	15	16	2020-11-07 12:45:00
5984	754	17	20	2018-11-17 04:45:00
5985	754	17	20	2018-09-29 01:00:00
5986	755	4	15	2018-09-07 14:15:00
5987	755	4	15	2019-09-10 09:15:00
5988	755	4	15	2019-08-01 03:00:00
5989	755	4	15	2018-09-06 15:30:00
5990	755	4	15	2018-10-15 02:00:00
5991	755	4	15	2018-05-10 20:00:00
5992	755	4	15	2018-05-22 09:45:00
5993	755	4	15	2018-09-02 03:30:00
5994	756	3	6	2019-10-07 06:15:00
5995	756	3	6	2018-03-08 17:15:00
5996	756	3	6	2018-09-12 03:30:00
5997	756	3	6	2018-02-20 09:15:00
5998	756	3	6	2019-02-08 03:45:00
5999	756	3	6	2019-05-03 21:30:00
6000	756	3	6	2018-12-07 02:30:00
6001	756	3	6	2019-08-01 16:45:00
6002	756	3	6	2019-09-21 16:15:00
6003	756	3	6	2019-07-01 12:00:00
6004	756	3	6	2018-06-03 11:15:00
6005	756	3	6	2018-02-04 06:15:00
6006	756	3	6	2019-05-14 04:45:00
6007	756	3	6	2018-08-06 23:00:00
6008	756	3	6	2019-01-25 14:30:00
6009	757	14	4	2018-06-15 06:30:00
6010	757	14	4	2018-02-08 08:30:00
6011	757	14	4	2018-04-10 22:45:00
6012	758	20	13	2018-02-20 09:15:00
6013	758	20	13	2018-05-27 15:30:00
6014	758	20	13	2019-02-12 16:15:00
6015	758	20	13	2018-12-10 19:15:00
6016	758	20	13	2019-02-14 14:45:00
6017	758	20	13	2018-12-06 14:30:00
6018	758	20	13	2018-03-15 17:45:00
6019	758	20	13	2018-04-29 02:30:00
6020	758	20	13	2018-01-12 15:15:00
6021	759	18	7	2018-07-12 11:00:00
6022	759	18	7	2017-08-08 15:30:00
6023	759	18	7	2017-09-23 22:30:00
6024	759	18	7	2018-11-30 17:15:00
6025	759	18	7	2017-06-22 21:30:00
6026	760	20	18	2018-12-30 06:45:00
6027	760	20	18	2018-10-05 18:30:00
6028	761	14	15	2020-09-16 00:45:00
6029	761	14	15	2019-01-23 01:45:00
6030	761	14	15	2019-07-29 03:45:00
6031	762	3	20	2020-09-14 17:00:00
6032	762	3	20	2020-02-07 05:30:00
6033	763	10	18	2018-10-11 21:15:00
6034	763	10	18	2019-07-30 08:15:00
6035	763	10	18	2020-03-11 03:00:00
6036	764	15	2	2018-01-05 11:15:00
6037	764	15	2	2019-08-05 22:30:00
6038	764	15	2	2019-07-29 18:00:00
6039	764	15	2	2019-04-15 19:00:00
6040	764	15	2	2017-12-20 05:00:00
6041	764	15	2	2018-10-12 17:15:00
6042	765	2	14	2018-10-24 03:45:00
6043	765	2	14	2019-08-18 09:45:00
6044	766	20	16	2019-01-30 00:45:00
6045	766	20	16	2018-10-01 21:15:00
6046	767	16	15	2020-04-13 00:00:00
6047	767	16	15	2021-07-03 20:30:00
6048	767	16	15	2021-05-10 16:15:00
6049	767	16	15	2020-02-21 20:15:00
6050	767	16	15	2020-10-24 14:30:00
6051	767	16	15	2020-04-21 01:30:00
6052	767	16	15	2020-09-07 14:30:00
6053	767	16	15	2021-01-01 06:45:00
6054	767	16	15	2020-06-26 00:45:00
6055	767	16	15	2020-12-18 07:00:00
6056	767	16	15	2020-04-06 02:45:00
6057	767	16	15	2021-06-18 11:45:00
6058	767	16	15	2021-05-06 14:00:00
6059	767	16	15	2020-10-06 05:30:00
6060	768	17	5	2020-01-03 16:15:00
6061	769	11	2	2019-12-12 18:15:00
6062	769	11	2	2018-12-01 13:45:00
6063	769	11	2	2018-10-03 21:15:00
6064	769	11	2	2020-07-05 11:15:00
6065	769	11	2	2019-01-15 00:00:00
6066	769	11	2	2019-10-01 19:30:00
6067	769	11	2	2020-02-25 03:15:00
6068	770	18	4	2020-02-04 18:45:00
6069	770	18	4	2020-03-03 06:30:00
6070	770	18	4	2019-10-24 19:00:00
6071	770	18	4	2020-05-03 05:45:00
6072	770	18	4	2020-06-28 04:00:00
6073	770	18	4	2020-09-08 04:00:00
6074	770	18	4	2019-09-09 16:30:00
6075	770	18	4	2019-02-03 05:15:00
6076	771	11	2	2020-12-26 10:00:00
6077	771	11	2	2019-11-29 01:45:00
6078	771	11	2	2019-01-09 06:15:00
6079	771	11	2	2020-08-23 11:00:00
6080	772	4	17	2018-09-07 23:15:00
6081	772	4	17	2018-11-22 13:45:00
6082	772	4	17	2019-04-09 10:45:00
6083	772	4	17	2019-03-28 22:30:00
6084	772	4	17	2018-09-19 19:45:00
6085	772	4	17	2019-05-22 19:30:00
6086	772	4	17	2019-01-19 04:30:00
6087	773	7	4	2021-04-24 00:30:00
6088	774	18	8	2020-04-13 22:00:00
6089	774	18	8	2021-03-11 14:00:00
6090	774	18	8	2020-05-20 13:15:00
6091	774	18	8	2020-09-12 06:30:00
6092	774	18	8	2021-05-09 08:00:00
6093	774	18	8	2021-06-09 17:00:00
6094	774	18	8	2021-05-05 20:45:00
6095	774	18	8	2020-06-11 08:45:00
6096	774	18	8	2021-06-01 19:30:00
6097	774	18	8	2020-12-23 12:15:00
6098	774	18	8	2020-09-20 13:45:00
6099	774	18	8	2020-11-29 03:15:00
6100	774	18	8	2020-10-14 22:00:00
6101	775	2	6	2020-11-14 15:30:00
6102	775	2	6	2019-10-18 15:00:00
6103	775	2	6	2020-01-14 12:30:00
6104	775	2	6	2019-11-27 03:30:00
6105	775	2	6	2020-01-21 14:00:00
6106	775	2	6	2020-07-15 19:15:00
6107	775	2	6	2019-12-06 17:00:00
6108	776	7	12	2020-03-30 12:00:00
6109	776	7	12	2020-01-03 01:15:00
6110	776	7	12	2019-12-03 23:45:00
6111	777	8	8	2021-05-22 00:00:00
6112	777	8	8	2020-03-22 03:00:00
6113	777	8	8	2021-04-12 20:30:00
6114	777	8	8	2020-01-07 23:45:00
6115	777	8	8	2021-06-08 13:15:00
6116	778	3	9	2018-05-05 09:00:00
6117	778	3	9	2017-10-19 14:45:00
6118	778	3	9	2017-09-21 21:00:00
6119	778	3	9	2017-10-02 03:15:00
6120	778	3	9	2017-11-07 10:45:00
6121	778	3	9	2018-12-30 23:45:00
6122	778	3	9	2018-10-15 17:45:00
6123	778	3	9	2017-06-06 22:15:00
6124	779	7	13	2018-08-10 06:45:00
6125	779	7	13	2019-03-29 12:00:00
6126	779	7	13	2019-06-05 05:15:00
6127	779	7	13	2018-07-09 07:30:00
6128	779	7	13	2019-05-13 12:00:00
6129	779	7	13	2018-11-08 11:45:00
6130	779	7	13	2019-10-29 21:30:00
6131	779	7	13	2020-04-28 15:30:00
6132	779	7	13	2018-07-07 11:30:00
6133	779	7	13	2018-07-22 13:45:00
6134	779	7	13	2019-04-20 21:00:00
6135	779	7	13	2018-10-21 08:00:00
6136	779	7	13	2019-10-22 07:30:00
6137	779	7	13	2018-11-07 17:45:00
6138	779	7	13	2018-10-11 09:15:00
6139	780	12	7	2020-02-04 11:30:00
6140	780	12	7	2020-10-06 03:45:00
6141	780	12	7	2020-10-15 15:45:00
6142	780	12	7	2020-02-03 18:15:00
6143	780	12	7	2019-12-14 21:30:00
6144	780	12	7	2019-05-10 14:45:00
6145	780	12	7	2019-12-15 14:30:00
6146	780	12	7	2020-01-06 06:00:00
6147	780	12	7	2021-01-05 23:00:00
6148	781	6	9	2018-10-01 10:00:00
6149	781	6	9	2019-01-15 08:00:00
6150	781	6	9	2019-03-20 06:15:00
6151	781	6	9	2017-09-16 17:00:00
6152	781	6	9	2018-05-02 13:30:00
6153	781	6	9	2017-09-10 01:30:00
6154	781	6	9	2018-07-28 23:00:00
6155	781	6	9	2018-02-21 15:00:00
6156	781	6	9	2018-01-29 06:15:00
6157	781	6	9	2018-11-15 06:00:00
6158	781	6	9	2017-11-02 18:45:00
6159	781	6	9	2018-06-07 22:30:00
6160	781	6	9	2018-04-13 13:15:00
6161	782	3	9	2019-04-25 13:15:00
6162	782	3	9	2020-09-02 18:00:00
6163	783	12	16	2019-04-30 01:00:00
6164	783	12	16	2018-11-11 00:45:00
6165	783	12	16	2019-03-24 08:45:00
6166	783	12	16	2019-01-27 15:45:00
6167	783	12	16	2019-03-19 15:15:00
6168	783	12	16	2020-04-18 05:00:00
6169	783	12	16	2020-08-26 09:45:00
6170	783	12	16	2020-07-10 23:45:00
6171	783	12	16	2019-06-03 08:00:00
6172	783	12	16	2019-11-13 20:30:00
6173	783	12	16	2020-01-15 01:30:00
6174	784	19	9	2019-04-28 21:15:00
6175	784	19	9	2020-12-11 20:45:00
6176	784	19	9	2020-10-17 01:15:00
6177	784	19	9	2019-02-02 01:00:00
6178	784	19	9	2019-11-22 23:45:00
6179	784	19	9	2020-06-29 16:45:00
6180	784	19	9	2019-06-29 18:15:00
6181	784	19	9	2020-02-06 23:00:00
6182	784	19	9	2019-10-04 03:00:00
6183	784	19	9	2020-07-19 01:15:00
6184	785	14	6	2019-04-24 08:30:00
6185	785	14	6	2020-03-28 02:15:00
6186	786	14	3	2019-03-02 11:00:00
6187	786	14	3	2020-06-10 00:15:00
6188	786	14	3	2020-06-03 16:00:00
6189	786	14	3	2020-07-29 13:15:00
6190	786	14	3	2020-08-11 13:45:00
6191	786	14	3	2019-11-12 07:30:00
6192	786	14	3	2020-08-20 22:15:00
6193	787	9	11	2019-05-05 17:00:00
6194	787	9	11	2019-12-24 09:30:00
6195	788	12	9	2019-02-07 18:45:00
6196	788	12	9	2018-11-08 12:30:00
6197	788	12	9	2018-09-11 16:00:00
6198	788	12	9	2017-09-05 00:00:00
6199	788	12	9	2017-12-25 15:15:00
6200	788	12	9	2017-12-11 17:15:00
6201	788	12	9	2017-11-20 10:30:00
6202	788	12	9	2017-12-28 17:45:00
6203	788	12	9	2018-03-08 00:00:00
6204	788	12	9	2019-03-04 04:30:00
6205	788	12	9	2018-09-21 03:00:00
6206	788	12	9	2019-05-22 06:00:00
6207	788	12	9	2019-05-13 16:00:00
6208	788	12	9	2018-11-01 10:15:00
6209	789	9	14	2018-01-27 22:15:00
6210	789	9	14	2017-12-27 09:00:00
6211	789	9	14	2018-11-04 04:30:00
6212	789	9	14	2018-03-05 17:00:00
6213	789	9	14	2017-03-21 04:30:00
6214	789	9	14	2017-07-08 10:30:00
6215	790	14	20	2021-12-11 19:15:00
6216	790	14	20	2020-02-12 01:15:00
6217	790	14	20	2020-04-23 18:00:00
6218	791	2	18	2017-10-09 21:15:00
6219	791	2	18	2017-09-13 08:30:00
6220	791	2	18	2017-05-28 20:15:00
6221	791	2	18	2017-03-30 13:45:00
6222	791	2	18	2018-12-03 18:15:00
6223	791	2	18	2017-11-25 17:30:00
6224	791	2	18	2018-11-03 04:00:00
6225	791	2	18	2018-11-20 13:45:00
6226	791	2	18	2018-12-13 23:15:00
6227	791	2	18	2018-01-07 18:15:00
6228	791	2	18	2017-04-22 15:30:00
6229	791	2	18	2018-08-13 13:00:00
6230	791	2	18	2017-05-19 20:30:00
6231	792	14	5	2020-10-20 06:15:00
6232	792	14	5	2021-04-25 13:30:00
6233	792	14	5	2019-07-26 09:00:00
6234	792	14	5	2020-07-21 05:30:00
6235	792	14	5	2019-05-22 17:00:00
6236	792	14	5	2020-02-21 15:30:00
6237	793	13	18	2019-05-18 11:30:00
6238	793	13	18	2019-07-09 20:45:00
6239	793	13	18	2018-12-29 22:15:00
6240	794	14	11	2019-03-24 06:30:00
6241	794	14	11	2018-05-27 16:45:00
6242	794	14	11	2017-10-17 10:30:00
6243	794	14	11	2017-09-12 03:30:00
6244	794	14	11	2017-11-23 01:15:00
6245	794	14	11	2018-05-14 03:45:00
6246	794	14	11	2019-03-16 09:00:00
6247	794	14	11	2019-07-04 12:30:00
6248	794	14	11	2019-01-14 00:00:00
6249	794	14	11	2018-01-21 17:15:00
6250	794	14	11	2018-08-26 18:00:00
6251	794	14	11	2019-06-22 07:00:00
6252	795	8	17	2019-09-07 16:00:00
6253	795	8	17	2020-03-10 13:30:00
6254	795	8	17	2020-02-10 02:00:00
6255	795	8	17	2019-06-13 20:15:00
6256	795	8	17	2019-08-26 15:30:00
6257	795	8	17	2021-02-20 11:45:00
6258	795	8	17	2019-04-21 17:15:00
6259	795	8	17	2019-06-12 07:30:00
6260	796	18	6	2020-03-08 23:15:00
6261	796	18	6	2019-12-15 12:00:00
6262	796	18	6	2019-11-02 18:30:00
6263	796	18	6	2019-04-23 19:45:00
6264	797	18	7	2020-05-12 03:15:00
6265	797	18	7	2020-11-30 18:00:00
6266	798	17	13	2019-04-20 19:00:00
6267	798	17	13	2018-04-03 19:45:00
6268	799	17	16	2019-09-15 23:00:00
6269	799	17	16	2020-08-05 09:30:00
6270	799	17	16	2020-02-15 17:00:00
6271	799	17	16	2019-02-24 01:45:00
6272	799	17	16	2020-11-30 08:30:00
6273	799	17	16	2019-09-03 11:30:00
6274	799	17	16	2020-04-20 07:15:00
6275	799	17	16	2020-11-28 17:45:00
6276	799	17	16	2020-06-03 16:30:00
6277	799	17	16	2019-01-28 04:30:00
6278	799	17	16	2019-03-16 12:45:00
6279	799	17	16	2019-02-27 04:00:00
6280	799	17	16	2019-06-17 06:15:00
6281	800	10	1	2019-06-25 01:45:00
6282	800	10	1	2019-07-13 06:15:00
6283	800	10	1	2018-01-27 19:15:00
6284	800	10	1	2018-03-05 00:00:00
6285	800	10	1	2019-04-03 21:30:00
6286	800	10	1	2019-08-26 23:15:00
6287	800	10	1	2018-08-23 00:30:00
6288	801	4	20	2020-05-10 14:00:00
6289	801	4	20	2020-12-17 13:30:00
6290	801	4	20	2021-02-15 01:45:00
6291	801	4	20	2019-07-10 17:00:00
6292	801	4	20	2020-09-07 21:15:00
6293	801	4	20	2019-12-28 21:00:00
6294	801	4	20	2019-07-22 04:45:00
6295	801	4	20	2020-04-04 09:00:00
6296	801	4	20	2020-10-04 00:45:00
6297	801	4	20	2019-10-15 03:45:00
6298	801	4	20	2021-02-05 15:15:00
6299	802	14	8	2019-08-11 10:15:00
6300	802	14	8	2019-12-05 22:30:00
6301	802	14	8	2018-08-30 16:45:00
6302	802	14	8	2019-12-23 12:45:00
6303	802	14	8	2018-02-22 13:00:00
6304	802	14	8	2019-12-13 17:15:00
6305	802	14	8	2019-10-26 05:00:00
6306	802	14	8	2019-12-24 14:30:00
6307	802	14	8	2018-03-21 05:30:00
6308	802	14	8	2019-09-07 11:00:00
6309	803	19	19	2021-02-16 02:15:00
6310	803	19	19	2020-11-18 19:15:00
6311	803	19	19	2021-08-09 05:15:00
6312	803	19	19	2021-09-09 20:15:00
6313	803	19	19	2021-02-03 23:30:00
6314	803	19	19	2021-01-05 17:45:00
6315	803	19	19	2020-08-07 08:00:00
6316	803	19	19	2020-01-18 15:00:00
6317	803	19	19	2021-06-14 07:30:00
6318	803	19	19	2021-01-26 19:45:00
6319	803	19	19	2020-07-18 12:00:00
6320	803	19	19	2020-03-20 15:30:00
6321	803	19	19	2020-07-23 20:45:00
6322	804	15	14	2019-04-28 04:00:00
6323	804	15	14	2019-10-18 11:45:00
6324	804	15	14	2019-04-20 20:15:00
6325	804	15	14	2019-05-06 04:30:00
6326	804	15	14	2018-04-12 04:00:00
6327	804	15	14	2019-09-15 08:00:00
6328	804	15	14	2019-08-23 20:00:00
6329	804	15	14	2019-09-26 19:45:00
6330	804	15	14	2019-10-14 18:15:00
6331	804	15	14	2018-10-27 23:30:00
6332	804	15	14	2018-11-18 17:30:00
6333	804	15	14	2019-01-13 02:00:00
6334	805	12	15	2019-06-12 00:00:00
6335	805	12	15	2019-06-03 10:00:00
6336	805	12	15	2019-05-21 23:30:00
6337	805	12	15	2019-11-07 20:45:00
6338	805	12	15	2020-12-29 04:45:00
6339	805	12	15	2019-11-07 19:45:00
6340	805	12	15	2019-04-19 18:30:00
6341	805	12	15	2020-10-03 21:45:00
6342	805	12	15	2019-05-27 17:45:00
6343	805	12	15	2019-03-20 22:45:00
6344	805	12	15	2019-04-19 20:45:00
6345	805	12	15	2019-10-06 08:30:00
6346	805	12	15	2019-11-13 03:00:00
6347	806	19	19	2018-10-17 06:15:00
6348	806	19	19	2019-05-19 01:00:00
6349	806	19	19	2019-06-23 10:45:00
6350	807	3	20	2018-06-26 23:15:00
6351	807	3	20	2018-12-13 05:15:00
6352	807	3	20	2019-01-22 01:00:00
6353	807	3	20	2018-01-20 04:15:00
6354	807	3	20	2019-04-04 10:45:00
6355	807	3	20	2019-07-09 15:30:00
6356	807	3	20	2019-03-16 07:30:00
6357	808	15	12	2019-05-08 14:45:00
6358	808	15	12	2019-09-02 03:30:00
6359	808	15	12	2019-11-29 12:00:00
6360	808	15	12	2019-02-13 00:00:00
6361	808	15	12	2020-01-16 12:00:00
6362	808	15	12	2019-10-22 03:00:00
6363	808	15	12	2020-02-07 03:00:00
6364	808	15	12	2018-11-18 04:30:00
6365	808	15	12	2019-05-19 21:45:00
6366	808	15	12	2019-06-05 16:30:00
6367	808	15	12	2019-06-16 10:30:00
6368	808	15	12	2019-01-23 20:30:00
6369	808	15	12	2018-06-07 05:00:00
6370	809	3	17	2019-10-11 23:15:00
6371	809	3	17	2019-03-30 08:30:00
6372	809	3	17	2019-01-06 08:30:00
6373	809	3	17	2020-08-21 20:45:00
6374	809	3	17	2019-03-06 15:15:00
6375	809	3	17	2019-12-29 14:15:00
6376	809	3	17	2020-09-07 00:45:00
6377	810	7	14	2018-08-13 19:30:00
6378	811	14	17	2018-12-16 14:30:00
6379	811	14	17	2018-02-08 23:45:00
6380	811	14	17	2018-12-22 22:30:00
6381	811	14	17	2018-10-29 03:45:00
6382	811	14	17	2019-03-20 22:15:00
6383	811	14	17	2019-07-03 16:30:00
6384	811	14	17	2018-05-05 01:15:00
6385	811	14	17	2018-01-27 23:15:00
6386	811	14	17	2019-07-10 09:45:00
6387	811	14	17	2018-04-04 07:45:00
6388	812	12	5	2017-02-07 00:45:00
6389	812	12	5	2018-11-04 02:00:00
6390	812	12	5	2017-12-05 05:00:00
6391	812	12	5	2017-11-28 15:15:00
6392	812	12	5	2018-06-03 05:00:00
6393	812	12	5	2018-07-10 23:45:00
6394	812	12	5	2017-03-29 01:15:00
6395	812	12	5	2018-03-03 11:45:00
6396	812	12	5	2018-10-08 05:15:00
6397	812	12	5	2018-08-13 07:15:00
6398	812	12	5	2018-06-10 06:00:00
6399	812	12	5	2018-02-02 07:00:00
6400	812	12	5	2019-01-01 06:45:00
6401	812	12	5	2018-04-05 01:15:00
6402	813	9	20	2020-01-01 03:45:00
6403	813	9	20	2018-10-23 18:45:00
6404	813	9	20	2019-05-01 05:30:00
6405	813	9	20	2018-02-18 23:15:00
6406	813	9	20	2018-08-20 00:30:00
6407	813	9	20	2019-09-22 11:15:00
6408	813	9	20	2018-06-07 17:30:00
6409	813	9	20	2019-03-07 07:45:00
6410	813	9	20	2019-11-18 23:15:00
6411	814	6	8	2017-09-22 02:30:00
6412	814	6	8	2017-05-05 19:45:00
6413	814	6	8	2017-10-04 20:15:00
6414	814	6	8	2018-02-21 19:30:00
6415	814	6	8	2018-07-12 17:15:00
6416	814	6	8	2018-04-12 17:45:00
6417	814	6	8	2018-08-09 07:15:00
6418	815	9	2	2019-06-29 04:45:00
6419	815	9	2	2018-05-02 14:15:00
6420	815	9	2	2018-05-20 22:45:00
6421	815	9	2	2019-08-19 18:15:00
6422	815	9	2	2019-04-10 04:30:00
6423	815	9	2	2019-03-05 22:00:00
6424	815	9	2	2018-05-04 13:00:00
6425	815	9	2	2019-01-27 00:30:00
6426	815	9	2	2019-08-07 12:30:00
6427	815	9	2	2019-11-01 23:30:00
6428	815	9	2	2019-10-06 11:15:00
6429	815	9	2	2019-11-02 15:00:00
6430	815	9	2	2018-12-28 16:30:00
6431	816	14	8	2019-03-02 19:30:00
6432	816	14	8	2020-05-19 20:45:00
6433	817	3	17	2020-01-15 00:00:00
6434	817	3	17	2019-05-04 11:15:00
6435	818	11	19	2019-07-06 07:45:00
6436	818	11	19	2019-10-12 22:00:00
6437	818	11	19	2020-03-01 15:30:00
6438	818	11	19	2019-03-12 13:30:00
6439	818	11	19	2019-01-18 10:45:00
6440	818	11	19	2019-01-19 18:00:00
6441	818	11	19	2020-03-21 05:00:00
6442	818	11	19	2019-12-01 03:15:00
6443	818	11	19	2019-05-14 08:00:00
6444	818	11	19	2019-10-28 01:00:00
6445	818	11	19	2019-02-19 22:15:00
6446	818	11	19	2019-10-16 19:30:00
6447	819	8	3	2018-09-09 11:00:00
6448	819	8	3	2017-06-30 12:00:00
6449	819	8	3	2019-04-27 13:30:00
6450	819	8	3	2017-08-26 14:00:00
6451	820	19	8	2019-07-07 09:15:00
6452	820	19	8	2018-10-16 06:15:00
6453	820	19	8	2019-06-04 00:45:00
6454	820	19	8	2019-03-01 01:00:00
6455	820	19	8	2018-02-20 09:15:00
6456	820	19	8	2018-08-24 18:30:00
6457	820	19	8	2019-06-02 10:15:00
6458	820	19	8	2018-02-21 07:15:00
6459	820	19	8	2019-07-07 00:15:00
6460	821	1	16	2020-05-04 05:45:00
6461	821	1	16	2020-02-20 01:00:00
6462	821	1	16	2019-04-06 21:00:00
6463	821	1	16	2019-07-19 23:15:00
6464	821	1	16	2019-12-08 14:30:00
6465	821	1	16	2020-09-13 19:30:00
6466	821	1	16	2019-08-06 08:15:00
6467	821	1	16	2020-08-14 06:30:00
6468	821	1	16	2020-07-02 17:00:00
6469	822	10	7	2018-11-28 18:45:00
6470	822	10	7	2017-06-12 09:45:00
6471	822	10	7	2017-08-06 17:30:00
6472	822	10	7	2019-01-29 12:30:00
6473	822	10	7	2017-12-12 08:15:00
6474	822	10	7	2018-03-08 00:00:00
6475	822	10	7	2017-09-22 01:45:00
6476	822	10	7	2017-12-21 19:45:00
6477	822	10	7	2018-04-12 15:00:00
6478	823	11	11	2019-02-02 18:30:00
6479	823	11	11	2017-06-17 14:15:00
6480	824	19	11	2019-05-16 12:15:00
6481	824	19	11	2019-05-17 21:00:00
6482	824	19	11	2019-05-30 22:15:00
6483	824	19	11	2020-06-29 14:30:00
6484	824	19	11	2020-08-13 09:00:00
6485	824	19	11	2018-10-09 06:00:00
6486	825	7	12	2020-02-27 04:15:00
6487	825	7	12	2018-12-23 00:15:00
6488	825	7	12	2019-02-16 17:30:00
6489	825	7	12	2019-04-12 08:45:00
6490	825	7	12	2019-05-21 01:00:00
6491	825	7	12	2018-11-20 01:45:00
6492	825	7	12	2020-04-28 21:45:00
6493	825	7	12	2019-12-08 00:15:00
6494	825	7	12	2019-07-17 13:00:00
6495	826	19	9	2020-04-19 03:15:00
6496	826	19	9	2019-04-23 22:15:00
6497	826	19	9	2019-08-26 00:15:00
6498	826	19	9	2019-07-21 21:45:00
6499	826	19	9	2020-04-18 16:15:00
6500	826	19	9	2019-05-29 22:15:00
6501	827	13	7	2019-12-07 05:45:00
6502	827	13	7	2020-04-16 01:15:00
6503	827	13	7	2020-01-12 10:15:00
6504	827	13	7	2018-12-11 15:30:00
6505	827	13	7	2019-10-17 23:00:00
6506	827	13	7	2020-02-19 04:15:00
6507	827	13	7	2019-04-25 09:30:00
6508	827	13	7	2019-02-20 05:30:00
6509	827	13	7	2019-10-24 12:45:00
6510	828	10	8	2020-10-14 17:45:00
6511	828	10	8	2019-10-16 07:45:00
6512	828	10	8	2019-05-04 23:30:00
6513	828	10	8	2019-09-11 17:15:00
6514	828	10	8	2020-01-15 10:30:00
6515	829	5	12	2019-05-17 16:00:00
6516	829	5	12	2018-01-27 14:45:00
6517	829	5	12	2018-03-22 20:15:00
6518	829	5	12	2018-12-09 12:00:00
6519	829	5	12	2019-02-23 03:15:00
6520	830	12	8	2019-11-14 03:15:00
6521	830	12	8	2019-08-26 22:30:00
6522	830	12	8	2018-05-12 17:45:00
6523	830	12	8	2019-01-11 11:15:00
6524	831	11	10	2019-12-09 14:00:00
6525	831	11	10	2018-09-10 09:00:00
6526	831	11	10	2019-02-08 14:15:00
6527	831	11	10	2018-06-18 08:30:00
6528	832	13	14	2017-06-11 19:30:00
6529	832	13	14	2018-02-13 05:45:00
6530	832	13	14	2018-04-14 05:00:00
6531	832	13	14	2017-08-24 10:00:00
6532	833	6	4	2020-08-06 07:00:00
6533	833	6	4	2020-01-24 14:45:00
6534	833	6	4	2020-02-04 06:00:00
6535	833	6	4	2019-06-11 16:00:00
6536	833	6	4	2020-07-12 09:00:00
6537	833	6	4	2018-11-05 09:45:00
6538	833	6	4	2020-03-04 17:00:00
6539	833	6	4	2019-01-16 10:30:00
6540	833	6	4	2019-10-13 03:15:00
6541	834	17	2	2019-06-08 11:45:00
6542	834	17	2	2019-07-16 21:30:00
6543	834	17	2	2020-08-09 08:45:00
6544	834	17	2	2020-01-26 15:00:00
6545	834	17	2	2019-01-27 20:15:00
6546	834	17	2	2019-02-25 13:00:00
6547	834	17	2	2019-06-24 14:00:00
6548	834	17	2	2020-07-20 06:45:00
6549	834	17	2	2019-08-28 19:45:00
6550	835	4	19	2020-04-11 12:45:00
6551	835	4	19	2020-03-26 05:15:00
6552	836	6	9	2018-08-18 03:15:00
6553	836	6	9	2018-12-14 20:15:00
6554	836	6	9	2018-11-21 13:30:00
6555	836	6	9	2018-08-22 16:45:00
6556	836	6	9	2018-03-14 15:00:00
6557	836	6	9	2017-12-01 17:00:00
6558	836	6	9	2017-05-03 07:45:00
6559	836	6	9	2017-11-21 06:45:00
6560	836	6	9	2017-10-04 10:15:00
6561	837	12	6	2020-09-08 04:00:00
6562	837	12	6	2021-07-14 22:45:00
6563	837	12	6	2021-03-22 00:30:00
6564	837	12	6	2020-02-22 14:45:00
6565	837	12	6	2021-04-29 14:30:00
6566	837	12	6	2020-05-12 21:30:00
6567	837	12	6	2020-01-26 18:30:00
6568	837	12	6	2020-10-27 01:30:00
6569	837	12	6	2020-01-07 01:45:00
6570	837	12	6	2020-03-11 04:45:00
6571	837	12	6	2021-01-11 14:00:00
6572	837	12	6	2020-03-01 01:30:00
6573	838	3	17	2018-12-21 11:30:00
6574	838	3	17	2019-05-05 12:15:00
6575	838	3	17	2019-06-08 21:00:00
6576	838	3	17	2019-09-06 19:30:00
6577	838	3	17	2019-04-15 23:45:00
6578	839	16	2	2020-06-20 13:15:00
6579	839	16	2	2020-02-03 18:30:00
6580	839	16	2	2021-06-20 03:15:00
6581	839	16	2	2021-07-24 17:15:00
6582	839	16	2	2021-01-11 20:00:00
6583	840	12	15	2019-09-11 12:15:00
6584	841	18	2	2019-06-16 14:00:00
6585	841	18	2	2020-11-28 18:15:00
6586	841	18	2	2019-01-10 14:00:00
6587	841	18	2	2019-12-11 11:45:00
6588	842	15	8	2021-02-27 11:30:00
6589	842	15	8	2021-03-24 01:45:00
6590	842	15	8	2020-01-04 10:15:00
6591	842	15	8	2020-01-25 04:30:00
6592	842	15	8	2021-02-11 07:00:00
6593	842	15	8	2021-01-09 19:15:00
6594	842	15	8	2019-07-13 11:45:00
6595	842	15	8	2020-06-11 11:00:00
6596	842	15	8	2020-02-03 17:00:00
6597	842	15	8	2020-12-12 04:15:00
6598	842	15	8	2020-07-19 02:45:00
6599	842	15	8	2020-07-27 10:15:00
6600	843	18	9	2019-01-14 06:45:00
6601	843	18	9	2019-04-19 02:45:00
6602	843	18	9	2019-08-07 04:30:00
6603	843	18	9	2019-04-10 11:00:00
6604	843	18	9	2018-08-14 21:15:00
6605	843	18	9	2019-03-13 02:00:00
6606	843	18	9	2019-02-19 19:30:00
6607	843	18	9	2018-11-09 06:15:00
6608	843	18	9	2019-10-09 05:30:00
6609	844	9	13	2020-11-30 06:15:00
6610	844	9	13	2020-06-01 08:30:00
6611	844	9	13	2021-04-16 08:45:00
6612	844	9	13	2021-02-17 01:15:00
6613	844	9	13	2020-09-27 00:45:00
6614	844	9	13	2020-10-29 09:45:00
6615	844	9	13	2020-05-22 01:15:00
6616	844	9	13	2019-05-28 11:15:00
6617	844	9	13	2020-09-01 05:15:00
6618	844	9	13	2020-10-29 11:15:00
6619	844	9	13	2020-05-13 19:30:00
6620	845	8	8	2019-07-02 21:15:00
6621	845	8	8	2020-03-11 05:30:00
6622	845	8	8	2020-04-01 03:45:00
6623	845	8	8	2020-11-07 12:00:00
6624	846	15	14	2017-10-22 05:45:00
6625	846	15	14	2017-08-22 08:00:00
6626	846	15	14	2017-12-05 08:15:00
6627	846	15	14	2017-09-06 15:00:00
6628	846	15	14	2018-05-02 07:45:00
6629	846	15	14	2017-10-18 03:00:00
6630	846	15	14	2018-02-24 12:45:00
6631	846	15	14	2018-12-22 11:30:00
6632	846	15	14	2017-09-25 18:00:00
6633	847	20	20	2020-05-01 00:15:00
6634	847	20	20	2020-01-10 15:00:00
6635	847	20	20	2019-06-07 07:00:00
6636	847	20	20	2020-06-17 23:30:00
6637	847	20	20	2019-06-15 05:30:00
6638	847	20	20	2020-11-30 12:45:00
6639	847	20	20	2019-03-20 10:45:00
6640	847	20	20	2020-01-16 21:15:00
6641	847	20	20	2020-04-14 00:45:00
6642	847	20	20	2020-06-15 02:30:00
6643	847	20	20	2020-07-26 12:30:00
6644	847	20	20	2020-08-29 04:15:00
6645	848	18	8	2019-01-11 00:00:00
6646	848	18	8	2019-11-10 13:15:00
6647	848	18	8	2018-05-26 22:15:00
6648	848	18	8	2018-12-08 00:15:00
6649	848	18	8	2019-08-06 08:30:00
6650	848	18	8	2019-07-05 17:30:00
6651	848	18	8	2018-06-04 00:45:00
6652	848	18	8	2019-08-19 06:45:00
6653	848	18	8	2019-02-21 10:45:00
6654	849	1	7	2018-04-21 13:00:00
6655	849	1	7	2019-08-19 11:15:00
6656	849	1	7	2019-01-04 23:00:00
6657	849	1	7	2018-01-30 15:30:00
6658	849	1	7	2018-07-17 00:00:00
6659	850	2	3	2020-06-09 12:00:00
6660	850	2	3	2018-12-22 00:45:00
6661	850	2	3	2018-11-03 04:15:00
6662	850	2	3	2018-12-03 03:15:00
6663	850	2	3	2019-04-20 15:15:00
6664	850	2	3	2019-07-04 05:45:00
6665	850	2	3	2020-07-11 12:45:00
6666	850	2	3	2020-02-04 11:15:00
6667	850	2	3	2018-08-23 19:30:00
6668	850	2	3	2019-05-19 18:45:00
6669	850	2	3	2020-05-03 00:15:00
6670	850	2	3	2018-10-22 09:45:00
6671	850	2	3	2019-06-06 23:15:00
6672	851	14	6	2018-07-01 21:00:00
6673	852	15	16	2021-05-21 09:45:00
6674	852	15	16	2021-01-01 15:00:00
6675	852	15	16	2020-09-28 20:00:00
6676	852	15	16	2021-02-02 07:30:00
6677	852	15	16	2020-09-02 02:45:00
6678	852	15	16	2019-06-25 15:30:00
6679	852	15	16	2019-09-24 18:00:00
6680	852	15	16	2019-10-18 11:45:00
6681	853	19	13	2019-02-04 19:00:00
6682	853	19	13	2018-11-07 14:00:00
6683	853	19	13	2018-12-23 10:45:00
6684	853	19	13	2018-03-04 14:45:00
6685	853	19	13	2019-07-05 09:00:00
6686	853	19	13	2018-08-23 13:45:00
6687	853	19	13	2018-02-09 10:45:00
6688	853	19	13	2019-09-14 02:00:00
6689	853	19	13	2019-07-09 12:45:00
6690	853	19	13	2018-05-23 13:30:00
6691	853	19	13	2019-01-03 02:00:00
6692	853	19	13	2017-12-02 05:30:00
6693	853	19	13	2018-01-21 15:30:00
6694	853	19	13	2018-02-17 00:30:00
6695	854	4	5	2018-12-05 22:00:00
6696	854	4	5	2018-11-12 08:45:00
6697	854	4	5	2017-07-06 05:00:00
6698	855	14	17	2020-03-23 09:45:00
6699	855	14	17	2020-02-14 02:45:00
6700	855	14	17	2020-10-25 23:30:00
6701	855	14	17	2021-11-11 13:15:00
6702	855	14	17	2021-09-18 04:45:00
6703	855	14	17	2020-04-18 03:30:00
6704	855	14	17	2020-04-30 08:15:00
6705	855	14	17	2020-07-29 01:30:00
6706	855	14	17	2020-04-15 15:15:00
6707	856	12	10	2019-03-19 08:30:00
6708	856	12	10	2019-01-08 12:30:00
6709	856	12	10	2018-04-18 23:15:00
6710	856	12	10	2019-03-24 05:15:00
6711	856	12	10	2018-09-28 11:15:00
6712	856	12	10	2019-08-22 08:45:00
6713	856	12	10	2017-11-05 14:30:00
6714	856	12	10	2019-08-28 16:45:00
6715	856	12	10	2018-04-16 08:30:00
6716	856	12	10	2017-11-06 20:30:00
6717	856	12	10	2018-04-16 12:15:00
6718	856	12	10	2018-11-26 17:45:00
6719	856	12	10	2019-04-09 05:15:00
6720	857	13	4	2020-05-07 08:00:00
6721	857	13	4	2020-04-18 18:00:00
6722	857	13	4	2020-04-06 15:30:00
6723	857	13	4	2020-08-09 04:45:00
6724	857	13	4	2019-04-12 10:30:00
6725	857	13	4	2020-07-14 14:00:00
6726	857	13	4	2019-08-04 20:30:00
6727	857	13	4	2020-01-08 16:15:00
6728	857	13	4	2020-02-16 20:15:00
6729	857	13	4	2019-06-13 06:30:00
6730	857	13	4	2020-02-22 17:15:00
6731	858	15	5	2021-08-01 19:30:00
6732	858	15	5	2021-01-01 09:45:00
6733	858	15	5	2020-03-21 08:30:00
6734	858	15	5	2021-05-10 16:45:00
6735	858	15	5	2021-02-26 09:00:00
6736	858	15	5	2020-02-03 12:30:00
6737	859	4	9	2017-12-12 08:30:00
6738	859	4	9	2018-03-08 07:15:00
6739	859	4	9	2017-06-17 22:00:00
6740	859	4	9	2017-09-14 10:15:00
6741	859	4	9	2018-08-09 15:00:00
6742	859	4	9	2019-02-08 17:30:00
6743	859	4	9	2018-02-08 04:15:00
6744	859	4	9	2018-08-01 05:30:00
6745	859	4	9	2018-01-11 11:15:00
6746	859	4	9	2018-02-25 11:45:00
6747	859	4	9	2018-01-10 16:30:00
6748	859	4	9	2018-03-28 09:00:00
6749	859	4	9	2017-08-30 19:45:00
6750	859	4	9	2019-05-06 16:45:00
6751	860	9	8	2019-06-10 20:00:00
6752	860	9	8	2019-08-01 21:45:00
6753	860	9	8	2020-07-14 06:45:00
6754	860	9	8	2019-06-09 16:45:00
6755	860	9	8	2019-11-18 20:30:00
6756	860	9	8	2018-08-16 19:45:00
6757	860	9	8	2019-09-04 03:45:00
6758	860	9	8	2020-01-28 17:30:00
6759	860	9	8	2020-04-09 10:15:00
6760	860	9	8	2019-09-21 22:15:00
6761	860	9	8	2018-08-17 06:45:00
6762	860	9	8	2020-02-02 16:15:00
6763	861	3	18	2020-02-01 07:45:00
6764	861	3	18	2020-07-06 20:00:00
6765	861	3	18	2019-03-25 09:00:00
6766	861	3	18	2019-02-27 04:15:00
6767	861	3	18	2020-07-09 18:30:00
6768	861	3	18	2019-04-22 11:15:00
6769	861	3	18	2019-03-01 01:45:00
6770	861	3	18	2020-04-23 06:30:00
6771	861	3	18	2019-02-11 14:15:00
6772	861	3	18	2020-04-30 12:15:00
6773	861	3	18	2019-12-09 02:15:00
6774	861	3	18	2019-10-28 08:30:00
6775	862	7	10	2019-09-22 22:45:00
6776	862	7	10	2019-09-08 22:00:00
6777	862	7	10	2019-07-23 00:30:00
6778	862	7	10	2019-11-20 09:45:00
6779	862	7	10	2018-02-07 23:45:00
6780	862	7	10	2019-12-01 20:00:00
6781	862	7	10	2019-09-21 19:15:00
6782	862	7	10	2019-05-16 16:15:00
6783	862	7	10	2018-03-28 11:45:00
6784	862	7	10	2019-12-14 16:30:00
6785	863	5	5	2018-01-27 17:15:00
6786	863	5	5	2019-04-09 21:45:00
6787	863	5	5	2017-11-29 16:30:00
6788	863	5	5	2018-06-18 22:30:00
6789	863	5	5	2019-01-02 05:00:00
6790	863	5	5	2019-06-04 15:00:00
6791	864	3	3	2019-04-04 22:45:00
6792	864	3	3	2018-09-15 02:30:00
6793	865	9	14	2020-01-12 06:00:00
6794	865	9	14	2020-07-21 05:30:00
6795	865	9	14	2019-10-21 08:00:00
6796	865	9	14	2020-07-05 13:15:00
6797	865	9	14	2019-02-20 18:00:00
6798	865	9	14	2019-03-15 14:45:00
6799	866	7	5	2018-08-15 07:45:00
6800	866	7	5	2018-08-27 00:45:00
6801	866	7	5	2017-10-29 16:00:00
6802	866	7	5	2018-07-04 13:00:00
6803	866	7	5	2018-05-08 23:00:00
6804	866	7	5	2019-02-11 21:45:00
6805	866	7	5	2018-09-17 11:45:00
6806	866	7	5	2019-04-14 00:45:00
6807	866	7	5	2019-04-22 03:45:00
6808	866	7	5	2018-12-09 06:00:00
6809	866	7	5	2017-09-14 13:15:00
6810	866	7	5	2019-06-01 04:30:00
6811	867	6	8	2019-07-22 20:15:00
6812	867	6	8	2020-02-11 09:30:00
6813	867	6	8	2019-04-27 14:45:00
6814	867	6	8	2018-11-22 19:15:00
6815	867	6	8	2019-10-07 01:00:00
6816	867	6	8	2019-02-01 00:00:00
6817	867	6	8	2019-07-11 20:00:00
6818	867	6	8	2019-11-21 17:15:00
6819	867	6	8	2020-01-13 11:30:00
6820	867	6	8	2019-12-13 02:00:00
6821	868	11	17	2019-04-23 09:45:00
6822	868	11	17	2018-02-08 23:00:00
6823	868	11	17	2018-02-02 23:15:00
6824	868	11	17	2018-09-07 13:15:00
6825	868	11	17	2019-05-29 18:00:00
6826	868	11	17	2017-10-05 14:00:00
6827	868	11	17	2018-02-01 13:45:00
6828	868	11	17	2019-06-27 19:30:00
6829	868	11	17	2019-01-08 15:00:00
6830	868	11	17	2019-08-28 05:30:00
6831	868	11	17	2018-06-10 09:30:00
6832	868	11	17	2017-10-02 06:45:00
6833	868	11	17	2018-03-10 13:45:00
6834	869	15	12	2020-03-08 21:00:00
6835	869	15	12	2019-03-11 01:45:00
6836	869	15	12	2020-01-08 17:15:00
6837	869	15	12	2020-02-02 02:45:00
6838	869	15	12	2019-07-17 12:00:00
6839	869	15	12	2018-10-07 07:15:00
6840	869	15	12	2018-12-17 05:15:00
6841	869	15	12	2018-11-19 07:00:00
6842	869	15	12	2018-12-01 11:30:00
6843	869	15	12	2020-06-13 04:15:00
6844	869	15	12	2019-03-25 01:45:00
6845	870	17	18	2017-11-26 08:00:00
6846	870	17	18	2019-06-18 00:30:00
6847	870	17	18	2017-11-14 23:00:00
6848	870	17	18	2018-06-26 21:30:00
6849	871	19	12	2018-07-06 03:15:00
6850	871	19	12	2019-01-21 05:30:00
6851	871	19	12	2018-11-19 09:00:00
6852	871	19	12	2018-06-28 14:45:00
6853	871	19	12	2019-03-15 06:00:00
6854	871	19	12	2018-03-19 08:00:00
6855	871	19	12	2018-11-22 04:00:00
6856	872	14	18	2019-09-19 21:45:00
6857	872	14	18	2019-03-16 07:45:00
6858	872	14	18	2019-10-27 13:30:00
6859	872	14	18	2019-10-12 03:00:00
6860	872	14	18	2018-08-05 08:00:00
6861	873	20	18	2018-09-12 09:45:00
6862	873	20	18	2019-08-01 10:15:00
6863	873	20	18	2018-04-15 06:00:00
6864	874	14	10	2020-07-28 21:00:00
6865	874	14	10	2020-12-06 20:15:00
6866	874	14	10	2021-06-02 15:45:00
6867	874	14	10	2021-07-17 22:15:00
6868	874	14	10	2021-02-19 19:30:00
6869	874	14	10	2021-01-02 22:45:00
6870	874	14	10	2021-02-16 16:00:00
6871	875	5	9	2019-09-13 22:15:00
6872	875	5	9	2020-02-14 14:45:00
6873	875	5	9	2020-10-03 17:00:00
6874	875	5	9	2020-07-01 14:00:00
6875	875	5	9	2019-06-22 10:30:00
6876	875	5	9	2021-03-10 08:00:00
6877	876	6	9	2019-03-09 04:45:00
6878	876	6	9	2018-08-24 13:15:00
6879	876	6	9	2018-02-04 13:30:00
6880	876	6	9	2019-02-02 11:00:00
6881	876	6	9	2018-10-07 09:30:00
6882	876	6	9	2017-12-08 22:45:00
6883	877	4	7	2019-04-18 18:30:00
6884	877	4	7	2019-05-22 13:15:00
6885	877	4	7	2020-09-16 08:45:00
6886	877	4	7	2019-03-07 15:45:00
6887	877	4	7	2020-08-02 05:45:00
6888	877	4	7	2020-12-07 03:00:00
6889	877	4	7	2019-04-09 19:30:00
6890	878	15	7	2020-02-07 09:45:00
6891	878	15	7	2020-10-22 13:45:00
6892	878	15	7	2019-04-28 11:15:00
6893	878	15	7	2019-08-23 22:00:00
6894	878	15	7	2019-06-22 03:15:00
6895	878	15	7	2019-05-11 15:45:00
6896	878	15	7	2019-12-25 08:45:00
6897	878	15	7	2019-09-29 10:00:00
6898	878	15	7	2020-11-28 20:00:00
6899	879	3	15	2019-01-03 09:30:00
6900	879	3	15	2018-12-21 03:15:00
6901	879	3	15	2019-11-10 07:15:00
6902	879	3	15	2019-03-15 04:15:00
6903	879	3	15	2020-01-13 06:45:00
6904	879	3	15	2018-10-24 17:45:00
6905	880	9	6	2019-02-03 03:45:00
6906	880	9	6	2019-06-06 00:45:00
6907	880	9	6	2020-12-21 00:45:00
6908	881	3	7	2020-07-14 03:45:00
6909	882	9	17	2019-04-19 08:00:00
6910	882	9	17	2017-11-03 21:15:00
6911	882	9	17	2018-06-13 01:45:00
6912	882	9	17	2019-01-22 12:30:00
6913	882	9	17	2018-08-15 18:45:00
6914	882	9	17	2019-03-16 14:45:00
6915	882	9	17	2018-11-23 12:45:00
6916	883	15	7	2020-04-29 20:00:00
6917	883	15	7	2020-05-17 19:15:00
6918	883	15	7	2020-06-02 08:30:00
6919	883	15	7	2021-06-12 19:30:00
6920	883	15	7	2021-11-06 09:15:00
6921	883	15	7	2020-05-30 16:00:00
6922	884	16	15	2018-03-22 23:00:00
6923	884	16	15	2020-01-25 11:15:00
6924	884	16	15	2019-08-05 20:45:00
6925	884	16	15	2018-09-17 12:15:00
6926	884	16	15	2019-04-19 15:30:00
6927	884	16	15	2020-02-20 13:30:00
6928	884	16	15	2018-10-21 19:30:00
6929	884	16	15	2020-02-22 10:15:00
6930	884	16	15	2019-11-06 04:45:00
6931	884	16	15	2018-11-01 01:00:00
6932	884	16	15	2018-05-14 12:45:00
6933	885	1	17	2021-01-09 20:15:00
6934	885	1	17	2021-02-24 11:00:00
6935	885	1	17	2021-01-19 13:30:00
6936	885	1	17	2020-02-10 05:00:00
6937	885	1	17	2020-03-03 09:30:00
6938	885	1	17	2021-07-08 05:15:00
6939	885	1	17	2021-01-18 20:00:00
6940	885	1	17	2020-03-22 20:00:00
6941	886	10	15	2018-11-22 16:00:00
6942	887	5	7	2020-02-02 02:30:00
6943	887	5	7	2019-06-22 21:00:00
6944	887	5	7	2019-10-23 12:45:00
6945	887	5	7	2019-11-17 13:15:00
6946	887	5	7	2019-08-09 08:00:00
6947	887	5	7	2019-10-17 02:45:00
6948	887	5	7	2020-02-02 17:00:00
6949	887	5	7	2018-12-29 01:00:00
6950	887	5	7	2018-05-04 21:00:00
6951	887	5	7	2019-07-16 11:00:00
6952	888	1	1	2018-05-13 09:00:00
6953	888	1	1	2019-04-10 09:00:00
6954	888	1	1	2019-09-22 15:00:00
6955	888	1	1	2018-02-12 12:45:00
6956	888	1	1	2018-02-14 15:45:00
6957	888	1	1	2018-11-12 12:00:00
6958	888	1	1	2019-06-08 00:00:00
6959	888	1	1	2019-09-15 13:30:00
6960	888	1	1	2019-02-15 23:15:00
6961	888	1	1	2018-08-10 12:00:00
6962	888	1	1	2018-01-17 02:15:00
6963	888	1	1	2018-12-21 21:45:00
6964	888	1	1	2019-05-11 03:00:00
6965	889	13	4	2017-09-13 00:00:00
6966	889	13	4	2019-04-30 21:15:00
6967	889	13	4	2017-11-01 22:30:00
6968	889	13	4	2018-03-10 18:00:00
6969	889	13	4	2019-01-27 02:45:00
6970	889	13	4	2019-05-01 18:30:00
6971	889	13	4	2019-06-09 22:15:00
6972	889	13	4	2018-06-26 21:30:00
6973	889	13	4	2017-09-13 20:45:00
6974	889	13	4	2019-01-21 02:00:00
6975	889	13	4	2018-06-02 05:15:00
6976	890	1	11	2021-08-01 09:30:00
6977	890	1	11	2020-11-05 12:45:00
6978	890	1	11	2020-07-30 18:30:00
6979	890	1	11	2021-02-23 09:15:00
6980	890	1	11	2020-12-15 15:00:00
6981	890	1	11	2020-03-12 04:15:00
6982	890	1	11	2021-07-12 09:00:00
6983	890	1	11	2021-11-10 01:00:00
6984	890	1	11	2021-02-11 15:00:00
6985	890	1	11	2021-01-27 14:45:00
6986	891	10	11	2019-11-21 16:00:00
6987	891	10	11	2019-01-09 03:30:00
6988	891	10	11	2020-01-17 05:45:00
6989	892	19	19	2018-10-29 00:00:00
6990	892	19	19	2018-11-28 13:15:00
6991	892	19	19	2019-06-17 05:30:00
6992	892	19	19	2020-06-06 09:45:00
6993	893	4	8	2017-09-03 17:15:00
6994	893	4	8	2019-02-23 23:15:00
6995	893	4	8	2018-02-27 21:15:00
6996	893	4	8	2018-03-25 11:00:00
6997	893	4	8	2017-12-05 23:30:00
6998	893	4	8	2018-11-24 20:15:00
6999	893	4	8	2018-11-01 01:30:00
7000	893	4	8	2018-08-08 14:15:00
7001	894	5	13	2020-09-07 04:00:00
7002	894	5	13	2021-08-16 16:30:00
7003	894	5	13	2021-06-05 10:15:00
7004	894	5	13	2021-02-02 17:15:00
7005	894	5	13	2021-03-09 08:30:00
7006	895	3	20	2018-07-23 17:45:00
7007	895	3	20	2018-12-19 06:00:00
7008	895	3	20	2019-12-05 04:15:00
7009	895	3	20	2018-08-15 11:00:00
7010	895	3	20	2018-06-23 08:00:00
7011	895	3	20	2018-08-16 08:15:00
7012	895	3	20	2019-02-07 05:00:00
7013	895	3	20	2019-03-11 18:00:00
7014	895	3	20	2018-03-28 07:30:00
7015	895	3	20	2019-05-06 22:00:00
7016	895	3	20	2019-02-07 17:15:00
7017	895	3	20	2019-09-25 06:30:00
7018	896	11	2	2019-10-12 09:15:00
7019	896	11	2	2020-07-22 22:45:00
7020	896	11	2	2020-08-13 03:00:00
7021	896	11	2	2021-01-26 15:45:00
7022	896	11	2	2019-10-09 00:15:00
7023	896	11	2	2019-09-09 21:45:00
7024	896	11	2	2021-01-30 10:30:00
7025	896	11	2	2020-06-19 21:00:00
7026	896	11	2	2020-07-18 03:15:00
7027	897	8	3	2020-11-28 23:15:00
7028	897	8	3	2020-05-06 11:00:00
7029	897	8	3	2020-12-28 14:15:00
7030	897	8	3	2019-03-04 13:15:00
7031	897	8	3	2020-04-05 07:45:00
7032	897	8	3	2020-08-26 14:30:00
7033	897	8	3	2020-06-04 14:45:00
7034	897	8	3	2020-11-14 07:45:00
7035	897	8	3	2020-07-04 23:15:00
7036	897	8	3	2020-07-30 07:15:00
7037	897	8	3	2020-05-13 19:00:00
7038	897	8	3	2020-11-25 15:45:00
7039	897	8	3	2019-05-05 17:30:00
7040	897	8	3	2019-05-09 00:00:00
7041	898	13	8	2019-05-16 23:15:00
7042	898	13	8	2018-01-22 16:30:00
7043	898	13	8	2018-01-12 17:15:00
7044	898	13	8	2019-06-13 19:30:00
7045	899	4	16	2019-01-27 09:00:00
7046	899	4	16	2019-10-29 16:30:00
7047	900	11	8	2019-10-09 03:30:00
7048	900	11	8	2019-03-07 02:00:00
7049	900	11	8	2019-10-18 00:15:00
7050	900	11	8	2019-09-28 05:00:00
7051	900	11	8	2020-06-11 14:00:00
7052	900	11	8	2019-12-19 17:45:00
7053	900	11	8	2020-03-04 06:15:00
7054	900	11	8	2019-11-13 12:00:00
7055	900	11	8	2018-12-08 16:00:00
7056	900	11	8	2019-07-28 19:45:00
7057	901	16	2	2018-08-28 11:30:00
7058	901	16	2	2019-11-03 12:30:00
7059	901	16	2	2019-01-24 15:45:00
7060	901	16	2	2019-08-10 08:15:00
7061	901	16	2	2019-01-17 05:00:00
7062	901	16	2	2018-09-27 13:15:00
7063	901	16	2	2019-08-18 07:30:00
7064	901	16	2	2019-01-18 01:15:00
7065	901	16	2	2018-02-19 08:00:00
7066	901	16	2	2019-05-24 17:45:00
7067	901	16	2	2019-04-10 05:30:00
7068	901	16	2	2018-09-02 23:00:00
7069	902	4	5	2020-07-21 22:45:00
7070	902	4	5	2021-07-06 10:30:00
7071	902	4	5	2019-12-07 12:15:00
7072	902	4	5	2021-11-26 03:15:00
7073	902	4	5	2020-11-04 09:45:00
7074	902	4	5	2020-12-22 02:45:00
7075	902	4	5	2020-06-07 12:00:00
7076	902	4	5	2021-06-08 16:00:00
7077	902	4	5	2020-05-16 13:00:00
7078	902	4	5	2020-09-11 10:45:00
7079	902	4	5	2020-04-28 13:45:00
7080	902	4	5	2021-02-06 11:15:00
7081	902	4	5	2021-06-10 23:30:00
7082	902	4	5	2020-02-06 20:45:00
7083	902	4	5	2021-03-20 06:00:00
7084	903	11	11	2021-07-26 00:30:00
7085	903	11	11	2020-06-06 20:15:00
7086	903	11	11	2021-06-01 14:45:00
7087	903	11	11	2021-03-23 08:15:00
7088	903	11	11	2020-10-04 20:00:00
7089	903	11	11	2021-07-19 11:00:00
7090	903	11	11	2020-03-14 08:45:00
7091	903	11	11	2020-02-05 22:00:00
7092	903	11	11	2021-09-14 18:30:00
7093	903	11	11	2021-10-11 01:00:00
7094	903	11	11	2020-09-11 02:15:00
7095	903	11	11	2020-06-26 03:00:00
7096	903	11	11	2021-10-19 05:15:00
7097	904	5	1	2018-05-05 17:45:00
7098	904	5	1	2019-06-26 11:15:00
7099	904	5	1	2019-01-25 04:45:00
7100	904	5	1	2018-05-23 16:15:00
7101	905	6	20	2020-10-15 02:45:00
7102	905	6	20	2019-05-03 13:30:00
7103	905	6	20	2020-03-28 04:00:00
7104	905	6	20	2020-12-11 17:30:00
7105	905	6	20	2021-01-27 08:30:00
7106	905	6	20	2019-06-18 00:15:00
7107	905	6	20	2021-02-16 15:15:00
7108	905	6	20	2020-06-10 22:15:00
7109	906	3	4	2020-11-01 23:30:00
7110	906	3	4	2020-09-21 01:30:00
7111	906	3	4	2021-02-14 21:45:00
7112	906	3	4	2021-06-22 19:00:00
7113	906	3	4	2020-09-23 17:00:00
7114	906	3	4	2019-09-16 15:30:00
7115	906	3	4	2020-11-26 16:30:00
7116	906	3	4	2021-01-08 19:00:00
7117	906	3	4	2021-05-25 09:30:00
7118	906	3	4	2021-03-13 00:30:00
7119	906	3	4	2020-11-16 21:00:00
7120	907	18	5	2018-09-09 06:30:00
7121	908	4	14	2019-06-26 05:45:00
7122	909	13	13	2017-09-23 19:00:00
7123	909	13	13	2019-02-24 21:15:00
7124	909	13	13	2017-11-06 14:15:00
7125	909	13	13	2018-02-10 08:45:00
7126	909	13	13	2017-07-22 20:15:00
7127	909	13	13	2019-02-22 23:15:00
7128	909	13	13	2018-09-25 09:45:00
7129	909	13	13	2018-08-05 20:45:00
7130	909	13	13	2018-10-08 02:30:00
7131	909	13	13	2018-02-06 03:45:00
7132	909	13	13	2019-05-26 14:15:00
7133	909	13	13	2019-05-19 18:15:00
7134	909	13	13	2019-01-22 08:45:00
7135	910	1	1	2020-02-09 16:45:00
7136	910	1	1	2020-08-02 05:45:00
7137	910	1	1	2019-12-24 05:45:00
7138	910	1	1	2019-09-24 00:45:00
7139	910	1	1	2020-02-17 16:15:00
7140	910	1	1	2019-09-23 09:15:00
7141	910	1	1	2019-06-12 09:45:00
7142	910	1	1	2020-01-10 04:15:00
7143	910	1	1	2019-11-25 03:45:00
7144	910	1	1	2020-11-23 16:45:00
7145	910	1	1	2020-11-10 06:45:00
7146	910	1	1	2020-08-06 03:15:00
7147	910	1	1	2021-01-04 22:15:00
7148	910	1	1	2020-11-21 17:00:00
7149	911	17	17	2019-06-05 20:30:00
7150	911	17	17	2019-08-17 15:00:00
7151	911	17	17	2020-02-18 06:00:00
7152	911	17	17	2020-04-08 06:30:00
7153	911	17	17	2019-01-29 19:30:00
7154	911	17	17	2019-04-26 04:15:00
7155	911	17	17	2019-07-22 02:30:00
7156	911	17	17	2020-03-16 00:30:00
7157	912	12	6	2020-03-17 20:30:00
7158	912	12	6	2021-08-15 18:15:00
7159	912	12	6	2020-03-20 20:15:00
7160	912	12	6	2019-10-20 20:45:00
7161	913	11	14	2018-03-24 01:45:00
7162	913	11	14	2019-02-23 08:00:00
7163	913	11	14	2018-08-26 10:15:00
7164	913	11	14	2018-12-10 19:30:00
7165	913	11	14	2019-09-02 17:30:00
7166	913	11	14	2019-06-19 23:00:00
7167	913	11	14	2019-06-24 11:00:00
7168	913	11	14	2018-12-23 02:00:00
7169	913	11	14	2019-03-09 03:45:00
7170	913	11	14	2018-10-04 22:30:00
7171	913	11	14	2019-02-02 06:15:00
7172	913	11	14	2018-07-17 10:45:00
7173	913	11	14	2018-11-09 19:30:00
7174	913	11	14	2018-04-27 22:30:00
7175	913	11	14	2019-05-13 14:30:00
7176	914	15	2	2019-05-01 22:30:00
7177	915	11	1	2018-05-29 15:45:00
7178	915	11	1	2019-02-04 01:15:00
7179	915	11	1	2018-04-07 21:15:00
7180	915	11	1	2018-11-25 09:15:00
7181	915	11	1	2018-03-13 04:45:00
7182	915	11	1	2019-02-15 02:15:00
7183	915	11	1	2019-01-11 13:00:00
7184	915	11	1	2018-12-04 08:15:00
7185	915	11	1	2018-04-16 03:30:00
7186	915	11	1	2018-11-27 23:30:00
7187	915	11	1	2018-02-03 21:45:00
7188	915	11	1	2018-07-29 00:45:00
7189	915	11	1	2019-04-10 12:30:00
7190	916	10	17	2018-10-18 07:00:00
7191	916	10	17	2017-12-04 13:45:00
7192	917	12	20	2017-12-11 07:00:00
7193	917	12	20	2019-04-27 17:15:00
7194	917	12	20	2018-04-20 09:15:00
7195	918	18	20	2017-10-17 19:45:00
7196	919	18	10	2020-10-06 14:45:00
7197	919	18	10	2020-05-08 10:00:00
7198	919	18	10	2020-10-09 00:00:00
7199	919	18	10	2021-03-23 07:45:00
7200	919	18	10	2020-05-16 12:45:00
7201	919	18	10	2021-12-14 22:00:00
7202	919	18	10	2020-06-13 20:30:00
7203	919	18	10	2020-09-16 06:15:00
7204	919	18	10	2020-05-04 18:00:00
7205	919	18	10	2020-10-07 06:00:00
7206	920	16	12	2019-06-06 15:45:00
7207	920	16	12	2019-02-16 06:30:00
7208	920	16	12	2020-04-01 12:45:00
7209	920	16	12	2019-10-20 10:30:00
7210	920	16	12	2019-08-23 09:45:00
7211	920	16	12	2019-05-24 12:15:00
7212	920	16	12	2020-05-03 14:00:00
7213	921	18	14	2021-11-13 03:45:00
7214	921	18	14	2021-09-11 15:30:00
7215	921	18	14	2021-09-11 05:45:00
7216	921	18	14	2020-04-02 04:15:00
7217	921	18	14	2020-08-09 23:15:00
7218	921	18	14	2020-11-01 18:15:00
7219	922	2	18	2018-09-18 17:45:00
7220	922	2	18	2018-05-27 13:15:00
7221	922	2	18	2018-08-09 06:45:00
7222	922	2	18	2018-03-30 07:15:00
7223	922	2	18	2019-05-01 07:00:00
7224	922	2	18	2019-04-11 16:30:00
7225	923	19	19	2021-04-30 12:00:00
7226	923	19	19	2021-04-10 18:00:00
7227	923	19	19	2021-02-27 14:00:00
7228	923	19	19	2020-01-20 10:30:00
7229	923	19	19	2021-02-13 12:15:00
7230	923	19	19	2019-10-24 15:15:00
7231	923	19	19	2020-09-03 22:45:00
7232	923	19	19	2021-02-21 12:45:00
7233	923	19	19	2021-03-20 19:15:00
7234	924	20	16	2021-04-02 18:45:00
7235	924	20	16	2021-01-19 23:15:00
7236	925	4	4	2019-06-20 17:15:00
7237	925	4	4	2019-06-08 04:30:00
7238	925	4	4	2020-02-10 23:45:00
7239	925	4	4	2020-03-22 13:30:00
7240	925	4	4	2019-01-24 00:45:00
7241	925	4	4	2019-09-22 09:45:00
7242	925	4	4	2020-08-05 14:00:00
7243	925	4	4	2019-02-27 04:00:00
7244	925	4	4	2020-09-02 21:15:00
7245	926	12	16	2018-08-15 22:15:00
7246	926	12	16	2019-08-15 05:45:00
7247	926	12	16	2018-04-29 04:45:00
7248	926	12	16	2017-12-23 09:15:00
7249	926	12	16	2019-07-12 00:00:00
7250	926	12	16	2018-05-11 03:30:00
7251	926	12	16	2019-03-22 22:15:00
7252	927	7	7	2019-01-19 03:30:00
7253	927	7	7	2018-04-27 11:45:00
7254	927	7	7	2018-08-17 14:00:00
7255	927	7	7	2017-09-12 01:00:00
7256	927	7	7	2018-12-14 17:15:00
7257	927	7	7	2019-06-04 17:30:00
7258	927	7	7	2018-01-21 08:00:00
7259	927	7	7	2019-05-02 09:45:00
7260	927	7	7	2018-09-03 02:30:00
7261	927	7	7	2017-10-16 04:15:00
7262	927	7	7	2017-08-18 10:15:00
7263	928	17	10	2018-12-29 09:15:00
7264	928	17	10	2019-02-02 13:30:00
7265	928	17	10	2018-09-27 01:15:00
7266	928	17	10	2018-04-07 16:30:00
7267	928	17	10	2017-12-08 12:30:00
7268	928	17	10	2018-11-10 12:45:00
7269	928	17	10	2018-08-28 07:30:00
7270	928	17	10	2019-03-02 10:45:00
7271	928	17	10	2018-08-12 15:45:00
7272	928	17	10	2018-12-04 02:00:00
7273	928	17	10	2018-07-30 01:45:00
7274	928	17	10	2018-06-18 08:15:00
7275	928	17	10	2019-06-06 19:30:00
7276	928	17	10	2018-06-14 10:30:00
7277	928	17	10	2019-06-07 04:45:00
7278	929	13	3	2019-08-29 16:45:00
7279	929	13	3	2019-06-13 14:45:00
7280	929	13	3	2019-03-02 11:45:00
7281	929	13	3	2019-06-25 05:30:00
7282	929	13	3	2018-12-18 03:30:00
7283	929	13	3	2019-04-12 21:30:00
7284	929	13	3	2019-10-30 17:30:00
7285	929	13	3	2018-12-10 03:15:00
7286	929	13	3	2019-04-17 11:15:00
7287	929	13	3	2019-02-10 19:45:00
7288	929	13	3	2019-09-29 08:00:00
7289	929	13	3	2018-10-13 16:00:00
7290	929	13	3	2019-04-14 18:15:00
7291	930	13	8	2020-08-17 11:45:00
7292	930	13	8	2021-03-01 07:00:00
7293	930	13	8	2020-07-07 10:30:00
7294	930	13	8	2021-02-14 19:45:00
7295	930	13	8	2021-04-01 15:45:00
7296	931	6	4	2020-07-26 16:30:00
7297	931	6	4	2020-08-17 23:45:00
7298	931	6	4	2020-11-13 16:30:00
7299	931	6	4	2019-06-26 20:45:00
7300	931	6	4	2021-05-07 02:45:00
7301	931	6	4	2021-01-06 00:15:00
7302	932	14	14	2019-12-29 08:15:00
7303	932	14	14	2018-12-26 07:15:00
7304	932	14	14	2018-06-17 06:30:00
7305	932	14	14	2019-10-08 10:15:00
7306	932	14	14	2018-09-09 03:00:00
7307	932	14	14	2020-04-17 22:00:00
7308	932	14	14	2019-03-01 22:30:00
7309	932	14	14	2018-12-02 11:00:00
7310	932	14	14	2020-05-30 20:45:00
7311	932	14	14	2019-02-17 19:45:00
7312	932	14	14	2019-03-21 22:00:00
7313	932	14	14	2019-09-26 08:15:00
7314	932	14	14	2018-10-02 13:00:00
7315	932	14	14	2018-12-21 03:30:00
7316	932	14	14	2020-03-08 11:30:00
7317	933	11	15	2018-10-06 22:15:00
7318	933	11	15	2019-11-26 08:30:00
7319	933	11	15	2020-04-25 19:15:00
7320	933	11	15	2019-08-13 08:15:00
7321	933	11	15	2020-04-06 02:00:00
7322	933	11	15	2018-11-24 19:45:00
7323	934	12	20	2020-04-14 13:00:00
7324	934	12	20	2020-03-09 09:30:00
7325	935	16	8	2019-01-23 02:00:00
7326	935	16	8	2018-07-07 16:15:00
7327	935	16	8	2019-04-05 22:15:00
7328	935	16	8	2019-07-29 01:30:00
7329	935	16	8	2018-09-27 04:15:00
7330	935	16	8	2019-04-09 15:30:00
7331	935	16	8	2017-12-23 23:30:00
7332	935	16	8	2017-11-16 22:30:00
7333	935	16	8	2019-04-20 05:00:00
7334	936	15	15	2019-06-04 23:15:00
7335	936	15	15	2020-09-28 14:45:00
7336	936	15	15	2021-02-08 14:30:00
7337	936	15	15	2019-04-07 07:15:00
7338	936	15	15	2019-12-04 04:15:00
7339	936	15	15	2019-10-22 19:00:00
7340	937	13	4	2021-02-07 17:45:00
7341	937	13	4	2020-03-18 05:00:00
7342	937	13	4	2021-09-15 11:30:00
7343	937	13	4	2021-08-15 16:45:00
7344	937	13	4	2021-09-12 13:00:00
7345	937	13	4	2021-06-06 11:30:00
7346	937	13	4	2021-08-21 04:00:00
7347	937	13	4	2020-03-04 19:00:00
7348	937	13	4	2021-09-17 18:00:00
7349	938	2	8	2018-09-21 19:00:00
7350	938	2	8	2020-01-16 05:30:00
7351	938	2	8	2019-02-03 16:45:00
7352	938	2	8	2018-06-25 03:00:00
7353	938	2	8	2019-01-20 20:45:00
7354	938	2	8	2019-10-19 16:15:00
7355	938	2	8	2018-12-06 22:00:00
7356	938	2	8	2018-03-03 23:00:00
7357	938	2	8	2018-04-27 14:45:00
7358	939	8	16	2020-01-26 00:15:00
7359	939	8	16	2021-05-18 09:15:00
7360	939	8	16	2021-07-03 00:15:00
7361	939	8	16	2020-11-11 02:15:00
7362	939	8	16	2021-02-12 10:30:00
7363	940	11	9	2017-04-03 06:15:00
7364	940	11	9	2018-11-23 11:45:00
7365	940	11	9	2019-02-26 18:45:00
7366	940	11	9	2019-02-02 17:15:00
7367	940	11	9	2018-02-23 23:45:00
7368	940	11	9	2018-10-22 03:15:00
7369	940	11	9	2018-03-21 07:45:00
7370	940	11	9	2018-07-04 02:00:00
7371	940	11	9	2018-10-18 14:15:00
7372	940	11	9	2018-10-21 01:00:00
7373	940	11	9	2018-12-11 11:00:00
7374	940	11	9	2017-09-04 07:30:00
7375	941	14	16	2021-04-10 15:30:00
7376	941	14	16	2021-08-13 18:45:00
7377	941	14	16	2021-01-25 00:15:00
7378	941	14	16	2020-05-15 03:45:00
7379	941	14	16	2020-07-06 08:15:00
7380	941	14	16	2020-08-13 09:30:00
7381	941	14	16	2020-04-06 17:30:00
7382	941	14	16	2020-09-09 23:15:00
7383	941	14	16	2020-10-18 03:30:00
7384	941	14	16	2021-11-15 20:00:00
7385	941	14	16	2020-06-26 09:00:00
7386	941	14	16	2020-09-28 19:30:00
7387	942	12	16	2017-10-04 23:45:00
7388	942	12	16	2018-07-11 03:45:00
7389	942	12	16	2017-11-24 15:30:00
7390	942	12	16	2017-10-05 04:45:00
7391	942	12	16	2018-01-22 18:00:00
7392	942	12	16	2018-08-04 02:30:00
7393	942	12	16	2017-09-25 19:15:00
7394	942	12	16	2018-04-27 00:15:00
7395	942	12	16	2018-03-12 21:00:00
7396	943	10	3	2019-02-20 23:45:00
7397	943	10	3	2018-07-03 09:30:00
7398	943	10	3	2019-02-02 20:30:00
7399	943	10	3	2017-04-02 06:00:00
7400	944	7	9	2018-12-23 21:15:00
7401	944	7	9	2017-07-23 01:15:00
7402	944	7	9	2018-05-26 17:00:00
7403	944	7	9	2017-11-28 12:45:00
7404	944	7	9	2018-09-13 00:30:00
7405	944	7	9	2018-06-01 06:15:00
7406	944	7	9	2018-11-05 08:30:00
7407	944	7	9	2017-12-09 03:30:00
7408	944	7	9	2018-02-27 09:45:00
7409	945	4	18	2019-04-03 20:45:00
7410	945	4	18	2019-09-08 05:00:00
7411	945	4	18	2020-04-08 18:45:00
7412	945	4	18	2020-05-02 22:30:00
7413	945	4	18	2020-09-03 09:30:00
7414	945	4	18	2020-03-29 09:45:00
7415	945	4	18	2019-05-21 03:45:00
7416	945	4	18	2019-09-08 12:15:00
7417	945	4	18	2019-11-23 20:30:00
7418	945	4	18	2020-03-26 09:45:00
7419	945	4	18	2020-03-28 22:15:00
7420	945	4	18	2019-03-02 12:30:00
7421	946	19	11	2018-12-12 00:45:00
7422	946	19	11	2018-05-15 16:45:00
7423	946	19	11	2019-09-10 13:15:00
7424	946	19	11	2019-07-15 03:30:00
7425	946	19	11	2018-11-17 18:45:00
7426	946	19	11	2019-06-14 17:45:00
7427	946	19	11	2018-09-04 16:15:00
7428	946	19	11	2019-02-08 17:15:00
7429	946	19	11	2018-05-07 22:15:00
7430	946	19	11	2018-06-12 02:15:00
7431	946	19	11	2019-04-05 15:45:00
7432	946	19	11	2019-10-02 00:45:00
7433	946	19	11	2018-06-28 23:15:00
7434	946	19	11	2019-10-05 08:00:00
7435	946	19	11	2018-09-20 07:45:00
7436	947	19	8	2019-02-02 09:30:00
7437	947	19	8	2018-09-02 00:30:00
7438	947	19	8	2017-11-21 22:00:00
7439	947	19	8	2018-10-14 14:30:00
7440	947	19	8	2017-08-09 22:15:00
7441	947	19	8	2017-05-28 05:30:00
7442	947	19	8	2018-12-26 17:30:00
7443	947	19	8	2018-10-04 00:15:00
7444	947	19	8	2018-11-07 18:30:00
7445	948	14	15	2017-03-13 22:00:00
7446	948	14	15	2019-01-30 11:30:00
7447	948	14	15	2018-09-30 09:00:00
7448	948	14	15	2017-03-19 15:30:00
7449	948	14	15	2017-08-13 18:15:00
7450	949	15	3	2021-03-29 08:45:00
7451	949	15	3	2021-02-27 21:00:00
7452	949	15	3	2021-04-22 09:15:00
7453	949	15	3	2021-05-20 01:45:00
7454	949	15	3	2020-08-28 19:45:00
7455	949	15	3	2020-04-01 00:30:00
7456	949	15	3	2021-07-18 01:45:00
7457	949	15	3	2021-03-30 20:45:00
7458	949	15	3	2020-10-15 01:30:00
7459	949	15	3	2021-03-22 14:15:00
7460	950	15	7	2019-12-30 04:30:00
7461	950	15	7	2020-03-22 02:30:00
7462	951	1	6	2019-10-05 03:30:00
7463	951	1	6	2021-01-13 08:00:00
7464	951	1	6	2020-09-10 04:30:00
7465	951	1	6	2019-07-08 12:45:00
7466	951	1	6	2020-03-26 19:45:00
7467	951	1	6	2019-07-09 16:45:00
7468	951	1	6	2020-02-02 00:15:00
7469	951	1	6	2019-12-19 00:15:00
7470	951	1	6	2020-04-12 15:30:00
7471	952	18	12	2019-08-06 00:15:00
7472	952	18	12	2020-10-26 00:00:00
7473	952	18	12	2020-05-22 19:00:00
7474	952	18	12	2019-04-20 05:15:00
7475	952	18	12	2019-09-26 01:00:00
7476	952	18	12	2019-05-19 20:30:00
7477	952	18	12	2019-09-09 02:30:00
7478	952	18	12	2019-02-17 04:15:00
7479	952	18	12	2020-02-17 16:15:00
7480	952	18	12	2020-12-17 05:45:00
7481	953	18	14	2020-11-16 14:00:00
7482	953	18	14	2020-02-16 15:15:00
7483	953	18	14	2021-05-10 19:30:00
7484	953	18	14	2020-02-26 07:45:00
7485	953	18	14	2020-04-03 05:45:00
7486	953	18	14	2021-05-10 00:15:00
7487	954	8	5	2020-05-23 07:00:00
7488	954	8	5	2020-11-13 17:15:00
7489	954	8	5	2020-02-14 13:00:00
7490	954	8	5	2020-06-27 00:00:00
7491	954	8	5	2021-01-12 10:15:00
7492	954	8	5	2021-04-07 13:00:00
7493	955	1	7	2019-08-09 23:00:00
7494	955	1	7	2020-01-27 10:45:00
7495	955	1	7	2019-12-26 10:00:00
7496	955	1	7	2020-01-04 09:30:00
7497	955	1	7	2020-02-04 22:00:00
7498	956	5	1	2019-04-27 04:30:00
7499	956	5	1	2019-02-16 04:00:00
7500	956	5	1	2019-08-05 16:15:00
7501	956	5	1	2019-12-10 12:00:00
7502	957	11	7	2017-11-27 15:15:00
7503	957	11	7	2018-02-05 05:15:00
7504	957	11	7	2017-11-02 04:15:00
7505	957	11	7	2019-03-12 07:30:00
7506	957	11	7	2017-12-20 05:30:00
7507	957	11	7	2017-08-04 11:30:00
7508	958	15	16	2021-01-23 12:30:00
7509	958	15	16	2020-06-10 00:15:00
7510	958	15	16	2019-09-16 07:00:00
7511	958	15	16	2020-06-30 20:15:00
7512	958	15	16	2020-06-29 02:00:00
7513	958	15	16	2020-09-10 10:00:00
7514	958	15	16	2019-09-05 20:15:00
7515	958	15	16	2020-12-27 07:45:00
7516	959	1	12	2020-03-02 14:30:00
7517	959	1	12	2021-05-17 03:30:00
7518	959	1	12	2020-06-11 00:30:00
7519	959	1	12	2021-03-08 09:00:00
7520	959	1	12	2020-12-19 14:45:00
7521	959	1	12	2020-10-09 22:15:00
7522	959	1	12	2020-07-04 12:30:00
7523	959	1	12	2021-05-27 19:15:00
7524	959	1	12	2021-05-05 20:30:00
7525	959	1	12	2021-03-01 09:45:00
7526	960	8	7	2021-06-16 21:00:00
7527	960	8	7	2019-12-07 21:15:00
7528	960	8	7	2019-10-03 18:30:00
7529	960	8	7	2021-03-07 10:45:00
7530	960	8	7	2020-11-23 01:15:00
7531	961	4	2	2018-06-01 03:30:00
7532	961	4	2	2018-02-15 21:30:00
7533	961	4	2	2019-05-30 07:00:00
7534	961	4	2	2019-04-06 04:15:00
7535	961	4	2	2017-10-22 17:15:00
7536	962	1	14	2020-12-23 14:45:00
7537	962	1	14	2019-06-07 07:45:00
7538	962	1	14	2021-03-16 00:00:00
7539	962	1	14	2019-06-11 00:15:00
7540	962	1	14	2019-09-23 06:00:00
7541	962	1	14	2019-12-16 21:45:00
7542	962	1	14	2019-09-24 19:00:00
7543	962	1	14	2021-01-19 14:15:00
7544	962	1	14	2019-09-18 17:00:00
7545	962	1	14	2020-12-30 14:45:00
7546	962	1	14	2020-04-13 22:30:00
7547	963	10	8	2019-11-26 02:30:00
7548	963	10	8	2019-09-23 10:00:00
7549	963	10	8	2019-08-11 22:00:00
7550	963	10	8	2020-04-15 06:30:00
7551	963	10	8	2020-08-25 09:15:00
7552	963	10	8	2019-06-30 04:45:00
7553	963	10	8	2020-05-06 23:30:00
7554	963	10	8	2020-12-22 15:00:00
7555	963	10	8	2019-03-02 10:45:00
7556	963	10	8	2019-12-25 21:45:00
7557	963	10	8	2019-11-05 14:45:00
7558	963	10	8	2020-10-09 19:30:00
7559	963	10	8	2020-05-20 05:45:00
7560	963	10	8	2019-07-11 05:15:00
7561	964	12	10	2018-12-28 20:00:00
7562	964	12	10	2018-10-18 18:00:00
7563	964	12	10	2019-01-28 14:15:00
7564	964	12	10	2017-11-20 13:15:00
7565	964	12	10	2018-10-22 10:45:00
7566	964	12	10	2018-06-23 20:45:00
7567	964	12	10	2018-07-10 15:15:00
7568	964	12	10	2018-07-19 01:15:00
7569	964	12	10	2017-09-25 15:00:00
7570	965	3	19	2017-05-15 18:15:00
7571	965	3	19	2018-07-05 17:15:00
7572	965	3	19	2018-04-21 11:00:00
7573	965	3	19	2017-04-07 23:15:00
7574	965	3	19	2017-06-02 03:30:00
7575	965	3	19	2018-10-05 19:30:00
7576	966	14	6	2019-11-21 11:00:00
7577	966	14	6	2019-11-08 08:30:00
7578	966	14	6	2020-01-24 17:30:00
7579	966	14	6	2019-07-25 08:00:00
7580	966	14	6	2020-02-08 18:45:00
7581	967	7	17	2020-01-08 08:45:00
7582	967	7	17	2020-06-30 03:00:00
7583	967	7	17	2019-12-26 02:15:00
7584	967	7	17	2020-06-09 05:15:00
7585	967	7	17	2021-01-07 07:15:00
7586	967	7	17	2021-05-01 21:15:00
7587	967	7	17	2020-05-28 10:00:00
7588	968	2	11	2018-12-19 10:00:00
7589	968	2	11	2018-03-11 21:45:00
7590	968	2	11	2018-02-19 21:30:00
7591	968	2	11	2018-10-07 15:15:00
7592	969	11	13	2019-12-14 19:15:00
7593	969	11	13	2019-09-09 22:15:00
7594	969	11	13	2019-12-04 18:00:00
7595	969	11	13	2019-03-19 17:45:00
7596	969	11	13	2020-01-18 03:00:00
7597	969	11	13	2020-09-10 22:00:00
7598	969	11	13	2020-06-23 13:45:00
7599	970	9	17	2018-05-14 10:45:00
7600	970	9	17	2018-06-22 23:30:00
7601	970	9	17	2017-08-13 20:45:00
7602	970	9	17	2018-05-12 14:45:00
7603	970	9	17	2018-09-15 22:45:00
7604	971	18	19	2019-10-21 10:15:00
7605	971	18	19	2019-04-18 01:00:00
7606	971	18	19	2020-08-13 19:00:00
7607	971	18	19	2020-07-20 15:00:00
7608	971	18	19	2019-09-24 14:45:00
7609	971	18	19	2020-08-26 13:45:00
7610	971	18	19	2020-05-25 02:15:00
7611	971	18	19	2020-02-06 00:15:00
7612	971	18	19	2019-11-28 07:45:00
7613	971	18	19	2019-08-14 21:15:00
7614	972	2	5	2020-04-08 23:15:00
7615	972	2	5	2019-10-27 05:15:00
7616	972	2	5	2019-06-25 18:00:00
7617	973	11	2	2018-04-04 16:00:00
7618	973	11	2	2019-05-26 08:15:00
7619	973	11	2	2019-10-01 18:15:00
7620	973	11	2	2018-10-15 12:15:00
7621	973	11	2	2017-12-20 10:45:00
7622	973	11	2	2018-01-03 06:15:00
7623	973	11	2	2018-04-09 17:15:00
7624	974	9	13	2018-12-10 08:15:00
7625	974	9	13	2019-08-21 00:45:00
7626	974	9	13	2019-03-03 14:15:00
7627	974	9	13	2018-12-27 04:15:00
7628	974	9	13	2018-02-12 18:00:00
7629	974	9	13	2019-05-19 07:45:00
7630	974	9	13	2019-10-14 08:00:00
7631	974	9	13	2019-12-04 05:15:00
7632	974	9	13	2019-08-12 03:30:00
7633	975	9	11	2019-07-07 11:45:00
7634	975	9	11	2019-07-08 12:15:00
7635	975	9	11	2018-07-04 23:45:00
7636	976	1	11	2018-09-26 14:15:00
7637	976	1	11	2019-02-21 20:45:00
7638	977	18	15	2020-08-09 02:30:00
7639	977	18	15	2020-08-03 21:00:00
7640	977	18	15	2019-07-05 05:15:00
7641	977	18	15	2019-08-06 16:00:00
7642	977	18	15	2019-06-24 15:30:00
7643	977	18	15	2020-08-29 12:45:00
7644	977	18	15	2019-01-26 20:30:00
7645	977	18	15	2019-02-19 11:45:00
7646	977	18	15	2018-12-01 14:45:00
7647	977	18	15	2019-03-09 00:15:00
7648	977	18	15	2018-10-06 11:15:00
7649	977	18	15	2019-12-14 14:15:00
7650	977	18	15	2019-05-08 14:00:00
7651	977	18	15	2020-06-30 09:15:00
7652	977	18	15	2019-10-04 18:00:00
7653	978	1	17	2019-05-17 14:00:00
7654	978	1	17	2018-09-09 06:45:00
7655	978	1	17	2018-11-09 07:30:00
7656	978	1	17	2020-04-04 03:00:00
7657	978	1	17	2019-12-22 18:15:00
7658	978	1	17	2020-04-09 20:45:00
7659	978	1	17	2018-11-10 13:00:00
7660	978	1	17	2019-09-22 23:15:00
7661	978	1	17	2019-08-20 02:15:00
7662	978	1	17	2018-05-11 02:45:00
7663	978	1	17	2019-07-28 09:15:00
7664	978	1	17	2019-05-24 06:30:00
7665	978	1	17	2018-08-02 23:00:00
7666	978	1	17	2018-11-18 21:30:00
7667	979	14	20	2020-03-29 22:15:00
7668	979	14	20	2020-10-10 00:30:00
7669	979	14	20	2019-04-07 02:30:00
7670	979	14	20	2020-06-16 13:15:00
7671	979	14	20	2020-01-21 07:15:00
7672	979	14	20	2019-05-12 14:15:00
7673	980	1	3	2017-04-08 03:15:00
7674	980	1	3	2018-09-13 13:45:00
7675	980	1	3	2018-04-14 06:00:00
7676	980	1	3	2017-02-16 13:45:00
7677	980	1	3	2017-12-05 22:15:00
7678	980	1	3	2017-03-10 15:45:00
7679	980	1	3	2017-05-09 03:00:00
7680	980	1	3	2017-05-18 09:00:00
7681	980	1	3	2017-05-12 07:45:00
7682	980	1	3	2018-11-27 07:30:00
7683	980	1	3	2018-02-03 12:30:00
7684	981	17	11	2018-11-05 16:45:00
7685	981	17	11	2018-02-18 17:45:00
7686	981	17	11	2019-04-11 18:30:00
7687	981	17	11	2018-03-13 19:15:00
7688	981	17	11	2019-02-13 01:30:00
7689	982	2	8	2018-07-04 04:30:00
7690	982	2	8	2018-03-22 06:00:00
7691	982	2	8	2019-02-26 14:30:00
7692	982	2	8	2018-03-04 09:30:00
7693	982	2	8	2018-04-19 07:15:00
7694	982	2	8	2018-04-11 02:15:00
7695	982	2	8	2019-10-17 10:00:00
7696	982	2	8	2019-05-22 23:45:00
7697	982	2	8	2018-04-25 11:30:00
7698	982	2	8	2019-04-30 19:15:00
7699	982	2	8	2018-05-28 22:00:00
7700	983	19	2	2017-11-16 23:00:00
7701	983	19	2	2018-05-27 01:30:00
7702	983	19	2	2017-12-04 08:30:00
7703	983	19	2	2017-10-11 02:45:00
7704	983	19	2	2018-12-09 22:15:00
7705	983	19	2	2018-11-27 08:00:00
7706	983	19	2	2017-09-06 20:30:00
7707	983	19	2	2018-08-08 18:00:00
7708	983	19	2	2018-08-29 03:15:00
7709	983	19	2	2017-10-08 12:30:00
7710	983	19	2	2017-04-04 16:00:00
7711	983	19	2	2018-09-01 13:00:00
7712	984	3	11	2018-09-15 01:30:00
7713	984	3	11	2019-04-03 00:00:00
7714	984	3	11	2019-04-12 13:30:00
7715	984	3	11	2020-02-01 05:45:00
7716	984	3	11	2019-03-23 22:15:00
7717	985	8	5	2017-11-24 06:15:00
7718	985	8	5	2018-11-15 16:15:00
7719	985	8	5	2019-02-23 05:45:00
7720	985	8	5	2018-09-20 02:45:00
7721	985	8	5	2019-03-17 23:45:00
7722	985	8	5	2019-03-03 02:30:00
7723	986	20	11	2018-12-19 12:15:00
7724	987	1	14	2018-10-02 10:30:00
7725	987	1	14	2018-12-16 14:00:00
7726	987	1	14	2017-12-12 15:30:00
7727	987	1	14	2018-03-02 11:30:00
7728	987	1	14	2018-10-10 20:15:00
7729	987	1	14	2018-07-04 10:00:00
7730	987	1	14	2018-04-08 20:45:00
7731	987	1	14	2019-01-16 22:00:00
7732	987	1	14	2019-09-09 02:30:00
7733	987	1	14	2018-10-11 13:00:00
7734	987	1	14	2017-12-14 07:45:00
7735	987	1	14	2019-01-17 15:15:00
7736	987	1	14	2018-09-01 19:15:00
7737	987	1	14	2019-08-22 14:30:00
7738	988	18	16	2019-12-10 08:30:00
7739	988	18	16	2019-10-09 00:45:00
7740	988	18	16	2020-02-07 21:00:00
7741	988	18	16	2018-04-26 06:00:00
7742	988	18	16	2019-06-05 06:00:00
7743	988	18	16	2019-10-11 14:15:00
7744	988	18	16	2020-02-04 07:15:00
7745	988	18	16	2018-11-24 20:30:00
7746	988	18	16	2019-04-23 23:15:00
7747	989	4	11	2018-11-21 14:30:00
7748	989	4	11	2018-04-18 02:00:00
7749	989	4	11	2018-10-15 18:15:00
7750	989	4	11	2018-09-18 04:00:00
7751	989	4	11	2018-03-09 21:30:00
7752	989	4	11	2018-05-04 16:45:00
7753	989	4	11	2018-06-21 21:45:00
7754	989	4	11	2018-05-12 18:45:00
7755	989	4	11	2018-01-28 03:15:00
7756	990	12	3	2020-05-17 06:15:00
7757	990	12	3	2020-12-07 11:30:00
7758	990	12	3	2019-04-20 11:30:00
7759	990	12	3	2019-10-26 09:45:00
7760	990	12	3	2019-05-04 12:45:00
7761	991	6	12	2020-02-04 02:00:00
7762	991	6	12	2018-11-13 14:30:00
7763	991	6	12	2018-12-22 22:30:00
7764	991	6	12	2020-04-07 03:00:00
7765	991	6	12	2019-10-30 06:45:00
7766	991	6	12	2020-06-06 20:00:00
7767	991	6	12	2019-05-30 00:45:00
7768	991	6	12	2019-11-25 01:15:00
7769	992	5	12	2020-01-20 04:00:00
7770	992	5	12	2021-08-07 20:15:00
7771	992	5	12	2020-06-17 16:00:00
7772	992	5	12	2020-07-18 08:30:00
7773	992	5	12	2021-04-30 22:30:00
7774	993	15	13	2020-11-03 04:45:00
7775	993	15	13	2019-11-15 23:00:00
7776	993	15	13	2021-05-17 13:45:00
7777	993	15	13	2019-08-23 17:15:00
7778	993	15	13	2021-03-20 01:30:00
7779	993	15	13	2021-01-02 16:00:00
7780	993	15	13	2020-06-06 10:15:00
7781	993	15	13	2019-06-29 03:30:00
7782	993	15	13	2021-01-24 06:30:00
7783	993	15	13	2020-11-27 06:30:00
7784	993	15	13	2020-04-11 05:15:00
7785	993	15	13	2020-04-13 05:45:00
7786	994	3	8	2017-09-12 23:45:00
7787	994	3	8	2019-08-15 17:30:00
7788	994	3	8	2019-02-08 06:45:00
7789	994	3	8	2018-11-05 13:30:00
7790	994	3	8	2019-04-01 20:15:00
7791	995	9	16	2019-02-02 23:00:00
7792	995	9	16	2018-05-12 10:30:00
7793	995	9	16	2019-05-23 17:00:00
7794	995	9	16	2018-08-30 16:15:00
7795	995	9	16	2018-05-18 06:30:00
7796	995	9	16	2018-03-19 11:15:00
7797	995	9	16	2019-07-27 21:00:00
7798	995	9	16	2018-11-04 04:15:00
7799	995	9	16	2019-01-07 16:45:00
7800	995	9	16	2019-03-10 02:45:00
7801	995	9	16	2018-09-15 20:00:00
7802	995	9	16	2018-03-16 01:30:00
7803	996	11	18	2018-10-30 01:00:00
7804	996	11	18	2019-03-25 00:15:00
7805	996	11	18	2020-03-08 00:45:00
7806	996	11	18	2019-03-06 14:00:00
7807	996	11	18	2019-01-14 21:00:00
7808	997	18	6	2018-10-25 11:45:00
7809	997	18	6	2017-12-12 03:45:00
7810	997	18	6	2019-01-27 23:15:00
7811	998	9	6	2020-01-27 03:15:00
7812	998	9	6	2020-07-14 11:15:00
7813	998	9	6	2019-03-27 12:45:00
7814	998	9	6	2019-05-12 23:45:00
7815	999	6	12	2017-11-05 15:45:00
7816	999	6	12	2019-04-22 03:15:00
7817	999	6	12	2019-02-02 10:00:00
7818	999	6	12	2018-03-16 14:30:00
7819	999	6	12	2018-03-09 16:15:00
7820	999	6	12	2018-09-27 14:15:00
7821	999	6	12	2019-10-04 01:45:00
7822	999	6	12	2018-05-29 23:30:00
7823	1000	16	18	2018-10-25 16:15:00
7824	1000	16	18	2018-10-28 09:15:00
7825	1001	10	1	2020-08-15 02:00:00
7826	1001	10	1	2019-12-05 23:30:00
7827	1001	10	1	2021-07-30 16:15:00
7828	1001	10	1	2020-09-02 02:45:00
7829	1002	9	7	2020-06-29 04:00:00
7830	1002	9	7	2020-03-10 11:00:00
7831	1002	9	7	2020-12-23 19:30:00
7832	1002	9	7	2019-04-19 21:45:00
7833	1003	3	7	2019-09-26 10:00:00
7834	1003	3	7	2020-12-09 01:15:00
7835	1003	3	7	2020-03-23 02:45:00
7836	1003	3	7	2020-11-01 07:00:00
7837	1003	3	7	2019-10-22 01:00:00
7838	1003	3	7	2020-01-24 14:15:00
7839	1003	3	7	2019-07-05 19:30:00
7840	1003	3	7	2020-04-25 11:30:00
7841	1003	3	7	2019-11-02 14:00:00
7842	1003	3	7	2020-09-20 07:15:00
7843	1004	13	8	2020-05-09 06:45:00
7844	1004	13	8	2020-12-17 02:00:00
7845	1004	13	8	2020-02-26 10:15:00
7846	1004	13	8	2019-06-12 20:45:00
7847	1004	13	8	2020-09-28 16:45:00
7848	1004	13	8	2020-07-29 07:15:00
7849	1004	13	8	2019-10-10 09:30:00
7850	1004	13	8	2020-12-10 02:00:00
7851	1004	13	8	2019-11-29 22:30:00
7852	1005	2	19	2018-07-29 05:15:00
7853	1005	2	19	2019-06-09 08:45:00
7854	1006	16	2	2020-07-19 17:30:00
7855	1006	16	2	2020-04-15 21:45:00
7856	1006	16	2	2019-01-28 17:15:00
7857	1006	16	2	2020-05-01 21:15:00
7858	1006	16	2	2020-02-01 16:30:00
7859	1006	16	2	2020-07-23 04:00:00
7860	1007	11	7	2020-04-28 02:15:00
7861	1007	11	7	2018-12-25 13:15:00
7862	1007	11	7	2018-12-08 17:15:00
7863	1007	11	7	2020-05-30 23:45:00
7864	1008	6	14	2019-08-17 14:45:00
7865	1008	6	14	2019-03-28 03:00:00
7866	1008	6	14	2019-12-24 22:45:00
7867	1008	6	14	2020-02-02 23:45:00
7868	1008	6	14	2020-01-19 17:45:00
7869	1008	6	14	2018-11-06 01:15:00
7870	1008	6	14	2019-09-03 00:30:00
7871	1008	6	14	2019-04-11 03:30:00
7872	1008	6	14	2019-10-19 15:15:00
7873	1009	10	8	2018-05-29 08:00:00
7874	1009	10	8	2019-06-01 14:30:00
7875	1010	7	18	2020-02-02 07:00:00
7876	1010	7	18	2020-01-05 01:15:00
7877	1010	7	18	2020-02-24 05:15:00
7878	1010	7	18	2019-03-08 20:00:00
7879	1010	7	18	2020-07-20 01:45:00
7880	1010	7	18	2019-04-03 22:45:00
7881	1010	7	18	2020-02-03 15:45:00
7882	1010	7	18	2020-05-11 00:45:00
7883	1010	7	18	2020-05-23 13:45:00
7884	1010	7	18	2019-02-22 21:45:00
7885	1010	7	18	2020-01-02 11:30:00
7886	1010	7	18	2020-12-20 18:45:00
7887	1010	7	18	2020-04-09 23:30:00
7888	1011	15	8	2018-07-04 00:00:00
7889	1011	15	8	2019-08-08 21:45:00
7890	1011	15	8	2017-12-02 05:15:00
7891	1011	15	8	2019-02-12 13:30:00
7892	1011	15	8	2018-06-25 17:45:00
7893	1012	7	9	2021-04-29 09:15:00
7894	1012	7	9	2020-08-08 08:00:00
7895	1012	7	9	2021-04-29 18:45:00
7896	1012	7	9	2021-04-24 13:30:00
7897	1012	7	9	2021-01-08 21:45:00
7898	1012	7	9	2019-08-22 09:15:00
7899	1012	7	9	2020-09-28 09:00:00
7900	1012	7	9	2021-04-04 13:30:00
7901	1012	7	9	2020-05-20 12:45:00
7902	1012	7	9	2021-03-16 06:15:00
7903	1012	7	9	2021-06-13 06:45:00
7904	1012	7	9	2021-07-24 17:45:00
7905	1013	2	5	2019-01-17 07:30:00
7906	1013	2	5	2018-09-04 19:45:00
7907	1013	2	5	2018-07-17 14:15:00
7908	1014	10	8	2018-04-25 12:15:00
7909	1014	10	8	2019-06-20 10:15:00
7910	1014	10	8	2018-09-23 12:15:00
7911	1014	10	8	2019-04-23 20:45:00
7912	1014	10	8	2017-12-25 22:30:00
7913	1014	10	8	2018-01-20 15:15:00
7914	1014	10	8	2017-10-09 14:30:00
7915	1014	10	8	2018-04-01 19:30:00
7916	1014	10	8	2018-11-05 21:45:00
7917	1015	10	12	2017-09-13 13:00:00
7918	1015	10	12	2019-01-28 07:30:00
7919	1015	10	12	2017-05-01 11:45:00
7920	1015	10	12	2018-02-13 14:30:00
7921	1015	10	12	2019-02-17 03:15:00
7922	1015	10	12	2018-12-20 18:30:00
7923	1015	10	12	2019-04-08 04:00:00
7924	1015	10	12	2017-11-24 14:15:00
7925	1015	10	12	2017-11-27 05:00:00
7926	1015	10	12	2017-12-03 10:15:00
7927	1015	10	12	2018-04-27 03:00:00
7928	1015	10	12	2019-03-06 19:30:00
7929	1015	10	12	2019-01-07 14:30:00
7930	1015	10	12	2018-04-28 11:45:00
7931	1015	10	12	2017-06-13 16:45:00
7932	1016	9	8	2019-10-19 20:15:00
7933	1016	9	8	2019-09-04 12:45:00
7934	1016	9	8	2019-01-03 13:15:00
7935	1016	9	8	2019-06-02 19:00:00
7936	1016	9	8	2019-12-29 08:15:00
7937	1016	9	8	2019-05-17 05:45:00
7938	1016	9	8	2019-11-25 17:15:00
7939	1016	9	8	2020-08-29 07:15:00
7940	1016	9	8	2019-07-16 19:45:00
7941	1017	7	14	2018-02-19 23:45:00
7942	1017	7	14	2018-11-08 10:30:00
7943	1017	7	14	2019-03-03 14:00:00
7944	1017	7	14	2018-05-21 16:30:00
7945	1017	7	14	2018-04-03 07:00:00
7946	1017	7	14	2019-08-09 05:00:00
7947	1017	7	14	2019-02-03 18:45:00
7948	1017	7	14	2018-02-13 00:30:00
7949	1017	7	14	2019-10-14 14:30:00
7950	1017	7	14	2018-08-02 06:30:00
7951	1017	7	14	2018-10-12 08:00:00
7952	1017	7	14	2019-03-21 00:45:00
7953	1017	7	14	2018-06-29 05:15:00
7954	1017	7	14	2018-07-04 03:00:00
7955	1018	15	8	2019-12-20 09:45:00
7956	1019	14	17	2021-06-05 09:30:00
7957	1019	14	17	2021-07-29 15:15:00
7958	1019	14	17	2021-04-05 10:45:00
7959	1019	14	17	2020-12-17 10:45:00
7960	1019	14	17	2021-01-02 11:15:00
7961	1019	14	17	2020-02-26 04:00:00
7962	1020	5	17	2019-07-10 01:30:00
7963	1020	5	17	2019-07-20 22:15:00
7964	1020	5	17	2019-01-18 10:00:00
7965	1020	5	17	2019-06-17 21:45:00
7966	1020	5	17	2020-07-16 19:00:00
7967	1020	5	17	2019-03-04 04:00:00
7968	1020	5	17	2019-02-14 16:45:00
7969	1020	5	17	2018-12-30 12:15:00
7970	1020	5	17	2020-03-29 17:00:00
7971	1021	20	19	2017-11-18 11:45:00
7972	1021	20	19	2018-10-01 02:45:00
7973	1021	20	19	2019-04-06 00:15:00
7974	1021	20	19	2017-10-03 22:00:00
7975	1022	2	16	2018-11-06 16:45:00
7976	1022	2	16	2018-02-04 23:00:00
7977	1022	2	16	2018-08-03 02:15:00
7978	1022	2	16	2019-03-01 08:45:00
7979	1022	2	16	2018-10-14 06:30:00
7980	1022	2	16	2018-10-24 04:45:00
7981	1022	2	16	2018-02-01 04:15:00
7982	1022	2	16	2019-03-20 08:15:00
7983	1022	2	16	2017-10-06 09:15:00
7984	1022	2	16	2018-06-20 13:45:00
7985	1022	2	16	2018-01-09 04:00:00
7986	1023	15	10	2018-08-01 00:00:00
7987	1023	15	10	2017-12-18 00:45:00
7988	1023	15	10	2018-04-03 18:30:00
7989	1023	15	10	2018-08-29 11:45:00
7990	1023	15	10	2019-05-13 11:45:00
7991	1023	15	10	2017-10-14 09:00:00
7992	1023	15	10	2019-03-30 20:00:00
7993	1023	15	10	2017-12-11 06:00:00
7994	1024	15	12	2019-05-09 20:45:00
7995	1024	15	12	2017-07-14 08:30:00
7996	1024	15	12	2018-05-01 20:30:00
7997	1024	15	12	2017-11-04 23:30:00
7998	1024	15	12	2017-11-03 23:15:00
7999	1024	15	12	2018-10-26 16:00:00
8000	1024	15	12	2019-04-20 00:45:00
8001	1024	15	12	2018-12-28 08:30:00
8002	1024	15	12	2018-02-22 06:00:00
8003	1024	15	12	2018-06-27 02:45:00
8004	1025	4	1	2020-01-22 07:45:00
8005	1026	18	5	2020-04-20 04:15:00
8006	1027	14	16	2021-02-21 03:30:00
8007	1027	14	16	2020-06-22 13:45:00
8008	1028	1	1	2020-03-03 23:15:00
8009	1028	1	1	2019-12-22 07:45:00
8010	1028	1	1	2020-02-23 19:00:00
8011	1028	1	1	2019-10-03 00:30:00
8012	1028	1	1	2020-07-20 01:00:00
8013	1028	1	1	2020-08-29 11:00:00
8014	1028	1	1	2020-02-22 09:45:00
8015	1028	1	1	2021-05-08 04:45:00
8016	1028	1	1	2021-06-07 00:45:00
8017	1028	1	1	2021-02-04 23:45:00
8018	1028	1	1	2019-11-06 09:15:00
8019	1028	1	1	2021-06-09 15:45:00
8020	1028	1	1	2021-02-19 05:15:00
8021	1028	1	1	2020-03-08 17:15:00
8022	1029	1	5	2020-03-03 10:30:00
8023	1029	1	5	2021-10-16 16:30:00
8024	1029	1	5	2021-02-26 12:45:00
8025	1029	1	5	2021-04-03 03:45:00
8026	1029	1	5	2020-12-01 18:15:00
8027	1029	1	5	2021-09-10 14:45:00
8028	1029	1	5	2020-12-14 05:00:00
8029	1029	1	5	2021-08-04 09:30:00
8030	1029	1	5	2020-04-22 00:00:00
8031	1030	7	17	2020-08-03 05:15:00
8032	1030	7	17	2020-09-21 14:00:00
8033	1030	7	17	2021-08-30 06:30:00
8034	1030	7	17	2020-08-10 15:00:00
8035	1030	7	17	2020-11-01 23:30:00
8036	1030	7	17	2020-07-07 21:00:00
8037	1030	7	17	2021-05-30 11:00:00
8038	1030	7	17	2020-07-24 18:45:00
8039	1030	7	17	2020-04-28 07:00:00
8040	1030	7	17	2021-06-06 16:45:00
8041	1031	4	3	2019-01-25 00:30:00
8042	1031	4	3	2017-05-30 22:15:00
8043	1031	4	3	2017-04-09 04:00:00
8044	1031	4	3	2017-08-22 13:45:00
8045	1032	6	20	2017-09-23 03:45:00
8046	1032	6	20	2019-01-26 05:00:00
8047	1032	6	20	2019-01-03 10:30:00
8048	1032	6	20	2018-03-03 03:15:00
8049	1033	7	4	2019-04-20 17:45:00
8050	1033	7	4	2019-03-11 10:30:00
8051	1034	11	15	2020-01-27 05:30:00
8052	1034	11	15	2018-02-04 11:45:00
8053	1034	11	15	2018-02-19 07:45:00
8054	1034	11	15	2018-07-30 23:00:00
8055	1034	11	15	2019-04-26 22:45:00
8056	1034	11	15	2020-01-09 10:15:00
8057	1034	11	15	2018-02-12 08:00:00
8058	1034	11	15	2018-07-19 03:45:00
8059	1034	11	15	2018-12-23 14:15:00
8060	1034	11	15	2019-03-23 18:30:00
8061	1035	11	8	2020-02-24 10:30:00
8062	1035	11	8	2020-01-19 18:15:00
8063	1035	11	8	2021-01-14 06:00:00
8064	1035	11	8	2019-07-01 14:00:00
8065	1035	11	8	2019-05-11 03:45:00
8066	1035	11	8	2020-01-25 08:00:00
8067	1036	19	14	2019-05-20 06:30:00
8068	1036	19	14	2019-11-14 15:45:00
8069	1036	19	14	2018-07-16 21:15:00
8070	1037	19	20	2018-10-10 14:30:00
8071	1037	19	20	2019-01-13 17:45:00
8072	1037	19	20	2017-12-25 00:30:00
8073	1037	19	20	2018-06-04 23:15:00
8074	1037	19	20	2017-10-13 16:45:00
8075	1037	19	20	2017-12-10 17:00:00
8076	1037	19	20	2018-06-16 00:45:00
8077	1037	19	20	2019-06-17 20:30:00
8078	1038	2	11	2020-11-22 07:30:00
8079	1038	2	11	2020-06-26 04:00:00
8080	1038	2	11	2019-04-04 04:00:00
8081	1038	2	11	2020-07-25 17:00:00
8082	1038	2	11	2021-01-21 23:45:00
8083	1038	2	11	2020-01-21 01:30:00
8084	1038	2	11	2020-09-10 09:00:00
8085	1038	2	11	2021-02-06 21:00:00
8086	1039	3	6	2019-04-08 00:15:00
8087	1040	15	19	2017-11-05 15:45:00
8088	1040	15	19	2019-06-01 03:15:00
8089	1040	15	19	2018-09-11 13:15:00
8090	1040	15	19	2018-08-25 22:15:00
8091	1040	15	19	2018-05-17 20:15:00
8092	1040	15	19	2018-02-07 10:00:00
8093	1040	15	19	2017-11-28 10:00:00
8094	1040	15	19	2018-02-08 12:30:00
8095	1040	15	19	2018-12-08 06:30:00
8096	1041	15	6	2020-11-29 04:00:00
8097	1041	15	6	2019-03-28 16:00:00
8098	1041	15	6	2020-04-02 02:15:00
8099	1041	15	6	2019-03-03 03:30:00
8100	1041	15	6	2020-02-10 10:15:00
8101	1041	15	6	2019-02-20 02:15:00
8102	1041	15	6	2020-08-10 21:15:00
8103	1041	15	6	2019-10-26 15:30:00
8104	1041	15	6	2019-09-18 23:15:00
8105	1041	15	6	2020-03-24 15:15:00
8106	1041	15	6	2019-10-28 16:30:00
8107	1041	15	6	2020-10-09 22:30:00
8108	1042	8	6	2019-03-12 07:15:00
8109	1042	8	6	2018-01-01 19:30:00
8110	1042	8	6	2019-07-07 11:30:00
8111	1042	8	6	2017-12-16 05:00:00
8112	1042	8	6	2018-05-10 09:00:00
8113	1042	8	6	2019-03-09 06:45:00
8114	1042	8	6	2019-08-21 00:45:00
8115	1042	8	6	2018-04-19 16:15:00
8116	1042	8	6	2017-12-29 04:45:00
8117	1042	8	6	2018-07-29 20:15:00
8118	1042	8	6	2019-09-12 19:15:00
8119	1042	8	6	2018-03-05 08:15:00
8120	1042	8	6	2019-07-28 14:30:00
8121	1043	2	15	2018-11-10 04:45:00
8122	1043	2	15	2018-06-08 06:30:00
8123	1043	2	15	2018-08-02 02:15:00
8124	1043	2	15	2019-04-16 15:15:00
8125	1043	2	15	2019-07-23 20:45:00
8126	1043	2	15	2019-04-09 18:15:00
8127	1043	2	15	2019-01-19 14:30:00
8128	1043	2	15	2020-04-12 13:15:00
8129	1043	2	15	2020-02-13 20:30:00
8130	1043	2	15	2019-10-26 06:00:00
8131	1043	2	15	2018-12-26 02:00:00
8132	1043	2	15	2018-06-28 17:30:00
8133	1044	13	7	2018-01-26 05:45:00
8134	1044	13	7	2018-05-06 16:30:00
8135	1044	13	7	2018-02-15 17:15:00
8136	1045	17	9	2019-12-11 23:00:00
8137	1045	17	9	2019-03-26 18:00:00
8138	1045	17	9	2019-06-29 21:00:00
8139	1045	17	9	2018-12-16 19:00:00
8140	1045	17	9	2018-11-19 04:00:00
8141	1045	17	9	2018-04-08 09:00:00
8142	1045	17	9	2020-01-22 01:00:00
8143	1045	17	9	2019-07-07 11:45:00
8144	1045	17	9	2019-01-14 08:45:00
8145	1045	17	9	2018-03-16 12:45:00
8146	1045	17	9	2019-09-04 12:15:00
8147	1045	17	9	2018-10-29 12:15:00
8148	1045	17	9	2020-01-22 21:00:00
8149	1045	17	9	2019-01-03 18:30:00
8150	1046	4	5	2020-11-29 04:30:00
8151	1046	4	5	2020-01-20 06:30:00
8152	1046	4	5	2019-03-27 06:30:00
8153	1046	4	5	2020-12-16 18:45:00
8154	1046	4	5	2020-06-05 16:15:00
8155	1046	4	5	2020-06-14 09:45:00
8156	1046	4	5	2019-05-04 16:15:00
8157	1046	4	5	2019-03-18 23:00:00
8158	1046	4	5	2020-01-21 21:45:00
8159	1046	4	5	2020-03-30 00:45:00
8160	1047	20	14	2020-04-11 19:30:00
8161	1047	20	14	2019-07-11 04:15:00
8162	1047	20	14	2021-01-23 03:00:00
8163	1047	20	14	2019-09-13 13:30:00
8164	1047	20	14	2020-05-07 14:30:00
8165	1047	20	14	2020-03-07 02:00:00
8166	1047	20	14	2019-04-02 02:15:00
8167	1047	20	14	2019-04-23 07:15:00
8168	1047	20	14	2019-04-10 14:45:00
8169	1047	20	14	2020-07-30 15:30:00
8170	1047	20	14	2019-06-15 12:15:00
8171	1047	20	14	2019-06-23 21:15:00
8172	1048	2	19	2020-10-20 10:00:00
8173	1048	2	19	2019-03-27 20:15:00
8174	1049	7	17	2019-09-26 05:45:00
8175	1049	7	17	2019-10-06 11:30:00
8176	1049	7	17	2018-08-06 10:00:00
8177	1049	7	17	2019-12-21 23:00:00
8178	1049	7	17	2020-01-09 18:15:00
8179	1049	7	17	2020-03-20 17:45:00
8180	1049	7	17	2019-07-29 05:45:00
8181	1050	9	19	2017-09-06 03:15:00
8182	1050	9	19	2017-10-08 11:30:00
8183	1051	2	7	2017-12-27 19:15:00
8184	1051	2	7	2018-07-27 21:00:00
8185	1051	2	7	2017-03-19 09:15:00
8186	1051	2	7	2017-10-02 13:00:00
8187	1051	2	7	2017-08-24 23:30:00
8188	1051	2	7	2018-02-18 04:30:00
8189	1051	2	7	2018-12-08 07:15:00
8190	1051	2	7	2017-02-25 13:30:00
8191	1051	2	7	2017-02-11 21:15:00
8192	1051	2	7	2017-09-28 02:30:00
8193	1051	2	7	2018-09-10 03:45:00
8194	1051	2	7	2018-08-30 19:15:00
8195	1051	2	7	2017-08-13 07:00:00
8196	1051	2	7	2017-05-21 09:30:00
8197	1052	13	15	2021-05-05 20:00:00
8198	1052	13	15	2021-04-10 10:15:00
8199	1052	13	15	2021-05-14 23:00:00
8200	1053	6	1	2019-11-11 05:30:00
8201	1053	6	1	2020-08-07 11:45:00
8202	1053	6	1	2020-08-27 10:15:00
8203	1053	6	1	2019-09-06 01:45:00
8204	1053	6	1	2018-11-23 23:00:00
8205	1054	11	7	2021-07-26 23:45:00
8206	1054	11	7	2020-01-20 06:00:00
8207	1054	11	7	2020-05-12 13:15:00
8208	1054	11	7	2019-12-26 04:00:00
8209	1054	11	7	2021-05-14 22:00:00
8210	1054	11	7	2020-08-24 05:30:00
8211	1054	11	7	2020-04-05 12:30:00
8212	1054	11	7	2020-08-01 18:45:00
8213	1054	11	7	2021-01-23 06:45:00
8214	1054	11	7	2020-01-30 17:00:00
8215	1054	11	7	2021-03-01 19:45:00
8216	1054	11	7	2020-06-27 07:15:00
8217	1054	11	7	2021-06-16 20:00:00
8218	1055	2	10	2019-12-30 19:45:00
8219	1055	2	10	2018-12-18 23:30:00
8220	1055	2	10	2019-08-24 11:15:00
8221	1055	2	10	2019-05-04 17:30:00
8222	1055	2	10	2019-12-20 17:00:00
8223	1055	2	10	2018-12-15 23:30:00
8224	1055	2	10	2020-04-25 07:45:00
8225	1055	2	10	2019-03-07 17:45:00
8226	1055	2	10	2020-05-19 22:00:00
8227	1056	14	11	2020-06-08 14:15:00
8228	1056	14	11	2018-11-23 13:30:00
8229	1056	14	11	2019-02-11 11:00:00
8230	1056	14	11	2018-11-18 20:30:00
8231	1056	14	11	2020-05-26 01:00:00
8232	1056	14	11	2020-06-04 04:15:00
8233	1056	14	11	2019-01-26 08:15:00
8234	1057	16	14	2019-03-07 09:00:00
8235	1057	16	14	2019-01-28 08:15:00
8236	1057	16	14	2019-08-30 13:15:00
8237	1057	16	14	2018-09-25 04:00:00
8238	1057	16	14	2018-11-27 17:30:00
8239	1058	1	14	2020-02-06 23:30:00
8240	1058	1	14	2019-04-30 07:30:00
8241	1058	1	14	2019-11-29 19:45:00
8242	1058	1	14	2018-07-30 14:30:00
8243	1058	1	14	2020-03-02 00:00:00
8244	1058	1	14	2019-12-06 17:30:00
8245	1058	1	14	2020-05-21 02:30:00
8246	1058	1	14	2018-12-10 11:00:00
8247	1058	1	14	2020-02-18 10:45:00
8248	1058	1	14	2019-03-12 15:15:00
8249	1059	6	15	2017-12-03 09:15:00
8250	1059	6	15	2018-09-24 05:45:00
8251	1059	6	15	2018-03-26 03:45:00
8252	1059	6	15	2017-10-22 08:30:00
8253	1060	20	8	2019-11-14 16:30:00
8254	1060	20	8	2020-04-20 11:30:00
8255	1060	20	8	2019-08-16 23:00:00
8256	1061	7	10	2019-05-14 18:15:00
8257	1061	7	10	2019-11-27 19:15:00
8258	1061	7	10	2019-10-12 09:00:00
8259	1061	7	10	2020-03-14 18:45:00
8260	1061	7	10	2020-05-04 02:00:00
8261	1061	7	10	2019-03-16 14:30:00
8262	1061	7	10	2019-12-11 09:45:00
8263	1061	7	10	2019-12-23 18:30:00
8264	1061	7	10	2020-07-12 17:45:00
8265	1061	7	10	2019-07-26 00:45:00
8266	1061	7	10	2019-09-14 12:00:00
8267	1061	7	10	2020-06-23 23:45:00
8268	1062	3	6	2019-05-01 21:45:00
8269	1062	3	6	2018-09-09 00:15:00
8270	1062	3	6	2019-01-18 20:15:00
8271	1062	3	6	2018-10-23 18:00:00
8272	1062	3	6	2018-09-29 19:45:00
8273	1063	5	18	2019-12-10 17:00:00
8274	1063	5	18	2019-12-19 08:15:00
8275	1063	5	18	2018-11-26 19:45:00
8276	1063	5	18	2020-06-06 09:30:00
8277	1063	5	18	2020-01-20 20:00:00
8278	1063	5	18	2019-11-04 14:45:00
8279	1063	5	18	2020-05-17 23:00:00
8280	1063	5	18	2020-03-15 01:00:00
8281	1063	5	18	2020-06-17 18:30:00
8282	1063	5	18	2020-09-04 17:15:00
8283	1063	5	18	2020-07-13 16:00:00
8284	1064	15	18	2019-01-30 10:15:00
8285	1064	15	18	2019-04-18 07:30:00
8286	1064	15	18	2019-03-27 07:15:00
8287	1064	15	18	2018-11-08 16:15:00
8288	1064	15	18	2018-02-12 00:30:00
8289	1064	15	18	2018-02-03 20:45:00
8290	1064	15	18	2017-11-27 05:00:00
8291	1064	15	18	2018-06-30 21:30:00
8292	1064	15	18	2017-09-09 03:45:00
8293	1064	15	18	2017-10-28 15:15:00
8294	1064	15	18	2018-06-20 04:00:00
8295	1065	17	9	2019-01-16 22:30:00
8296	1065	17	9	2019-04-24 13:30:00
8297	1066	7	3	2019-09-19 03:00:00
8298	1066	7	3	2018-08-23 19:15:00
8299	1066	7	3	2018-08-20 21:15:00
8300	1066	7	3	2019-02-12 20:00:00
8301	1067	13	4	2018-02-10 07:30:00
8302	1067	13	4	2017-11-12 07:00:00
8303	1068	9	20	2018-03-30 01:00:00
8304	1068	9	20	2018-07-03 05:30:00
8305	1068	9	20	2018-02-03 02:00:00
8306	1068	9	20	2017-10-01 19:00:00
8307	1068	9	20	2019-06-12 20:30:00
8308	1068	9	20	2019-05-20 12:30:00
8309	1068	9	20	2018-02-16 03:15:00
8310	1068	9	20	2019-02-16 15:15:00
8311	1068	9	20	2018-03-03 14:45:00
8312	1068	9	20	2018-01-16 09:15:00
8313	1068	9	20	2018-06-18 09:00:00
8314	1069	1	10	2018-04-16 17:45:00
8315	1069	1	10	2017-07-13 19:30:00
8316	1069	1	10	2018-11-02 06:30:00
8317	1069	1	10	2018-01-06 20:00:00
8318	1069	1	10	2018-06-20 22:30:00
8319	1069	1	10	2018-12-21 21:00:00
8320	1069	1	10	2018-12-17 15:15:00
8321	1069	1	10	2017-12-17 18:00:00
8322	1069	1	10	2018-01-23 23:15:00
8323	1069	1	10	2019-04-13 01:00:00
8324	1069	1	10	2018-03-25 06:15:00
8325	1069	1	10	2019-03-19 10:15:00
8326	1070	14	18	2019-12-27 21:45:00
8327	1070	14	18	2019-08-19 22:45:00
8328	1070	14	18	2018-09-14 07:15:00
8329	1070	14	18	2019-12-10 17:45:00
8330	1070	14	18	2018-04-07 18:15:00
8331	1070	14	18	2018-07-18 02:15:00
8332	1070	14	18	2019-09-05 10:30:00
8333	1070	14	18	2018-08-07 18:15:00
8334	1071	17	17	2021-04-22 01:15:00
8335	1071	17	17	2019-09-15 18:30:00
8336	1072	19	19	2020-02-17 07:30:00
8337	1072	19	19	2020-01-14 08:00:00
8338	1072	19	19	2019-08-12 00:00:00
8339	1072	19	19	2019-06-24 05:45:00
8340	1072	19	19	2018-12-18 02:00:00
8341	1072	19	19	2019-03-07 10:15:00
8342	1072	19	19	2019-11-15 14:30:00
8343	1072	19	19	2019-02-17 19:45:00
8344	1072	19	19	2019-12-30 07:45:00
8345	1073	6	13	2017-05-28 15:30:00
8346	1073	6	13	2018-01-02 20:45:00
8347	1073	6	13	2018-03-17 06:00:00
8348	1073	6	13	2018-06-16 11:45:00
8349	1073	6	13	2017-07-26 06:45:00
8350	1073	6	13	2018-05-06 16:45:00
8351	1073	6	13	2018-07-12 16:30:00
8352	1073	6	13	2018-05-21 02:30:00
8353	1073	6	13	2018-01-29 00:30:00
8354	1073	6	13	2018-08-27 03:15:00
8355	1073	6	13	2018-03-11 07:00:00
8356	1074	20	4	2018-11-11 05:15:00
8357	1074	20	4	2019-11-23 00:00:00
8358	1074	20	4	2018-12-22 17:30:00
8359	1074	20	4	2019-06-19 07:00:00
8360	1074	20	4	2019-07-10 15:15:00
8361	1074	20	4	2019-10-15 14:00:00
8362	1074	20	4	2020-09-12 19:30:00
8363	1074	20	4	2020-06-21 04:00:00
8364	1074	20	4	2018-11-27 04:15:00
8365	1074	20	4	2019-04-30 12:45:00
8366	1074	20	4	2020-06-13 01:00:00
8367	1074	20	4	2020-02-25 14:30:00
8368	1074	20	4	2020-03-12 09:00:00
8369	1075	6	16	2017-11-11 21:45:00
8370	1075	6	16	2019-04-14 10:15:00
8371	1075	6	16	2019-01-02 09:45:00
8372	1075	6	16	2018-12-26 05:45:00
8373	1075	6	16	2018-03-28 09:30:00
8374	1075	6	16	2019-04-10 13:00:00
8375	1075	6	16	2018-10-01 07:15:00
8376	1075	6	16	2018-03-27 04:15:00
8377	1075	6	16	2019-10-22 06:15:00
8378	1076	11	10	2021-01-25 05:15:00
8379	1076	11	10	2019-12-29 11:00:00
8380	1076	11	10	2020-08-14 20:15:00
8381	1076	11	10	2021-09-13 07:15:00
8382	1076	11	10	2019-10-24 01:15:00
8383	1076	11	10	2020-06-27 09:45:00
8384	1076	11	10	2021-09-05 21:30:00
8385	1076	11	10	2020-08-03 00:15:00
8386	1076	11	10	2020-05-02 00:30:00
8387	1076	11	10	2020-01-28 13:30:00
8388	1076	11	10	2019-12-15 14:00:00
8389	1077	2	20	2018-02-26 22:00:00
8390	1077	2	20	2019-07-13 17:15:00
8391	1077	2	20	2017-12-03 12:15:00
8392	1077	2	20	2018-04-27 00:45:00
8393	1077	2	20	2018-07-05 04:00:00
8394	1077	2	20	2019-07-10 15:30:00
8395	1077	2	20	2018-04-22 15:45:00
8396	1077	2	20	2017-10-19 00:45:00
8397	1078	1	5	2020-07-02 19:45:00
8398	1078	1	5	2018-08-16 13:30:00
8399	1078	1	5	2019-03-13 14:15:00
8400	1078	1	5	2020-01-10 01:15:00
8401	1078	1	5	2019-04-29 07:15:00
8402	1078	1	5	2018-09-22 13:15:00
8403	1079	20	5	2019-08-28 06:15:00
8404	1079	20	5	2018-01-07 17:00:00
8405	1079	20	5	2018-01-30 07:30:00
8406	1079	20	5	2018-06-07 21:15:00
8407	1079	20	5	2018-08-24 19:45:00
8408	1079	20	5	2018-03-17 22:30:00
8409	1079	20	5	2018-09-25 01:00:00
8410	1079	20	5	2018-01-23 03:00:00
8411	1079	20	5	2019-08-08 15:30:00
8412	1079	20	5	2018-07-11 17:45:00
8413	1079	20	5	2019-03-28 17:45:00
8414	1079	20	5	2019-11-16 19:45:00
8415	1079	20	5	2019-08-25 17:45:00
8416	1079	20	5	2019-11-14 11:15:00
8417	1079	20	5	2018-02-12 14:30:00
8418	1080	17	15	2018-03-17 14:45:00
8419	1080	17	15	2019-06-12 19:00:00
8420	1080	17	15	2018-05-22 00:30:00
8421	1080	17	15	2017-09-18 14:00:00
8422	1081	10	20	2020-02-25 17:45:00
8423	1081	10	20	2020-07-11 11:45:00
8424	1081	10	20	2020-07-06 11:30:00
8425	1081	10	20	2019-03-06 11:15:00
8426	1081	10	20	2020-07-09 04:00:00
8427	1081	10	20	2019-10-18 22:30:00
8428	1081	10	20	2019-12-07 13:00:00
8429	1081	10	20	2019-03-25 09:00:00
8430	1081	10	20	2020-09-17 18:00:00
8431	1082	2	5	2020-09-21 13:00:00
8432	1082	2	5	2021-02-03 10:00:00
8433	1082	2	5	2019-05-24 22:00:00
8434	1082	2	5	2020-08-18 10:45:00
8435	1082	2	5	2021-01-15 08:15:00
8436	1082	2	5	2019-04-30 07:45:00
8437	1082	2	5	2019-10-09 19:00:00
8438	1082	2	5	2020-08-15 00:15:00
8439	1082	2	5	2019-10-06 03:45:00
8440	1082	2	5	2019-12-21 04:45:00
8441	1082	2	5	2020-06-21 04:00:00
8442	1082	2	5	2019-03-20 23:45:00
8443	1083	5	14	2020-11-28 14:15:00
8444	1084	4	2	2020-04-02 23:15:00
8445	1084	4	2	2020-08-07 19:30:00
8446	1084	4	2	2020-09-17 04:30:00
8447	1084	4	2	2019-06-03 01:45:00
8448	1084	4	2	2020-08-07 09:45:00
8449	1084	4	2	2020-11-17 03:45:00
8450	1084	4	2	2020-05-26 21:15:00
8451	1084	4	2	2020-12-23 20:00:00
8452	1084	4	2	2020-07-17 13:15:00
8453	1085	13	17	2018-03-04 12:45:00
8454	1085	13	17	2017-04-11 15:00:00
8455	1086	16	14	2020-08-17 12:00:00
8456	1086	16	14	2018-10-20 23:30:00
8457	1086	16	14	2020-08-26 12:15:00
8458	1086	16	14	2020-06-07 18:30:00
8459	1086	16	14	2019-06-26 08:00:00
8460	1086	16	14	2020-09-28 06:15:00
8461	1086	16	14	2019-01-04 17:00:00
8462	1087	14	7	2019-09-12 06:15:00
8463	1087	14	7	2019-05-07 16:30:00
8464	1087	14	7	2020-12-16 23:45:00
8465	1087	14	7	2020-02-06 03:15:00
8466	1087	14	7	2020-03-13 11:45:00
8467	1087	14	7	2020-09-20 01:15:00
8468	1087	14	7	2019-07-23 16:45:00
8469	1087	14	7	2020-02-01 00:30:00
8470	1087	14	7	2021-01-17 13:30:00
8471	1087	14	7	2019-08-10 05:00:00
8472	1087	14	7	2020-01-24 04:15:00
8473	1088	15	20	2017-05-21 07:15:00
8474	1088	15	20	2019-01-20 01:15:00
8475	1088	15	20	2018-06-04 09:15:00
8476	1088	15	20	2017-12-11 21:00:00
8477	1088	15	20	2018-08-16 19:45:00
8478	1088	15	20	2018-03-30 00:30:00
8479	1088	15	20	2018-05-14 05:45:00
8480	1089	4	5	2019-08-30 16:30:00
8481	1089	4	5	2020-02-07 05:00:00
8482	1089	4	5	2020-11-25 00:30:00
8483	1090	2	18	2021-05-09 09:00:00
8484	1090	2	18	2020-11-08 16:00:00
8485	1091	2	3	2021-01-25 08:45:00
8486	1091	2	3	2021-08-19 13:00:00
8487	1091	2	3	2020-04-02 14:45:00
8488	1091	2	3	2021-02-27 00:30:00
8489	1091	2	3	2020-10-08 23:45:00
8490	1091	2	3	2020-04-24 05:15:00
8491	1091	2	3	2021-01-30 12:45:00
8492	1092	10	11	2020-09-29 21:15:00
8493	1092	10	11	2020-06-27 08:45:00
8494	1092	10	11	2020-03-25 06:00:00
8495	1092	10	11	2021-08-23 15:45:00
8496	1092	10	11	2019-11-20 04:45:00
8497	1092	10	11	2020-05-14 18:30:00
8498	1092	10	11	2021-08-13 18:15:00
8499	1092	10	11	2020-02-15 05:00:00
8500	1092	10	11	2020-06-29 21:00:00
8501	1092	10	11	2020-03-08 00:45:00
8502	1092	10	11	2020-10-23 07:45:00
8503	1092	10	11	2021-09-14 02:00:00
8504	1093	2	11	2017-02-14 00:45:00
8505	1093	2	11	2017-05-05 19:30:00
8506	1093	2	11	2018-09-30 03:45:00
8507	1093	2	11	2018-08-28 22:45:00
8508	1093	2	11	2017-12-03 09:30:00
8509	1093	2	11	2019-01-21 01:45:00
8510	1093	2	11	2017-03-26 23:00:00
8511	1093	2	11	2017-06-16 11:45:00
8512	1093	2	11	2017-02-09 09:15:00
8513	1093	2	11	2018-02-24 13:45:00
8514	1093	2	11	2018-05-06 13:30:00
8515	1093	2	11	2018-06-30 12:00:00
8516	1094	7	20	2020-03-12 08:45:00
8517	1094	7	20	2020-03-05 18:15:00
8518	1094	7	20	2020-10-19 13:15:00
8519	1094	7	20	2019-11-29 20:15:00
8520	1094	7	20	2020-03-03 11:00:00
8521	1094	7	20	2020-05-03 10:30:00
8522	1094	7	20	2021-04-04 18:00:00
8523	1094	7	20	2020-08-17 16:15:00
8524	1094	7	20	2021-01-15 18:15:00
8525	1094	7	20	2021-01-16 06:30:00
8526	1094	7	20	2021-07-08 15:15:00
8527	1094	7	20	2021-07-09 00:00:00
8528	1095	12	12	2021-02-20 12:15:00
8529	1095	12	12	2021-11-13 05:45:00
8530	1095	12	12	2020-11-08 05:45:00
8531	1095	12	12	2020-01-22 22:00:00
8532	1095	12	12	2021-09-19 11:00:00
8533	1095	12	12	2020-11-17 02:15:00
8534	1095	12	12	2020-12-04 01:15:00
8535	1095	12	12	2021-11-08 05:00:00
8536	1095	12	12	2021-10-13 06:45:00
8537	1095	12	12	2021-01-24 14:00:00
8538	1095	12	12	2021-09-11 10:30:00
8539	1095	12	12	2020-12-12 09:00:00
8540	1095	12	12	2020-10-13 06:15:00
8541	1095	12	12	2020-02-09 20:00:00
8542	1096	14	9	2019-09-04 21:30:00
8543	1096	14	9	2020-10-26 20:00:00
8544	1096	14	9	2020-09-30 05:15:00
8545	1096	14	9	2019-10-17 11:00:00
8546	1097	1	1	2018-05-21 04:15:00
8547	1097	1	1	2018-03-29 17:30:00
8548	1097	1	1	2019-05-07 09:00:00
8549	1097	1	1	2019-03-08 15:00:00
8550	1098	19	12	2017-08-18 00:30:00
8551	1098	19	12	2017-10-28 14:15:00
8552	1098	19	12	2018-08-07 18:30:00
8553	1099	15	8	2019-03-04 20:15:00
8554	1099	15	8	2018-10-11 09:00:00
8555	1099	15	8	2018-06-22 18:30:00
8556	1099	15	8	2018-11-22 17:45:00
8557	1099	15	8	2018-11-24 10:45:00
8558	1099	15	8	2018-03-15 16:45:00
8559	1099	15	8	2019-01-17 10:15:00
8560	1099	15	8	2019-10-13 23:15:00
8561	1099	15	8	2018-10-12 08:30:00
8562	1099	15	8	2018-03-13 07:15:00
8563	1099	15	8	2019-07-16 11:00:00
8564	1100	20	6	2019-07-20 19:45:00
8565	1100	20	6	2019-06-15 10:45:00
8566	1100	20	6	2020-08-13 21:30:00
8567	1101	14	12	2019-07-22 08:30:00
8568	1101	14	12	2021-03-22 00:00:00
8569	1102	3	4	2019-07-09 19:00:00
8570	1102	3	4	2020-02-01 07:15:00
8571	1102	3	4	2019-07-12 16:00:00
8572	1102	3	4	2020-04-22 09:00:00
8573	1102	3	4	2021-06-03 13:15:00
8574	1102	3	4	2019-12-14 09:15:00
8575	1102	3	4	2021-03-14 14:30:00
8576	1102	3	4	2020-09-22 00:30:00
8577	1102	3	4	2019-07-22 17:00:00
8578	1102	3	4	2020-04-19 18:15:00
8579	1102	3	4	2019-11-05 21:00:00
8580	1102	3	4	2019-11-01 04:45:00
8581	1102	3	4	2020-02-15 19:00:00
8582	1102	3	4	2020-01-26 08:45:00
8583	1103	6	15	2019-03-09 15:45:00
8584	1103	6	15	2019-02-02 04:30:00
8585	1103	6	15	2020-05-11 07:45:00
8586	1103	6	15	2019-12-02 03:30:00
8587	1103	6	15	2019-12-26 23:45:00
8588	1103	6	15	2019-06-19 06:15:00
8589	1103	6	15	2018-09-24 14:15:00
8590	1103	6	15	2019-04-09 11:00:00
8591	1103	6	15	2018-07-05 15:30:00
8592	1104	17	9	2021-02-17 08:45:00
8593	1104	17	9	2020-02-04 04:45:00
8594	1104	17	9	2021-03-19 05:00:00
8595	1104	17	9	2019-09-04 13:15:00
8596	1104	17	9	2020-03-05 18:15:00
8597	1104	17	9	2019-05-01 12:00:00
8598	1104	17	9	2020-05-15 11:30:00
8599	1104	17	9	2019-10-21 07:00:00
8600	1104	17	9	2020-09-15 07:15:00
8601	1104	17	9	2021-02-22 11:30:00
8602	1104	17	9	2020-09-06 04:00:00
8603	1105	2	9	2019-10-18 21:30:00
8604	1105	2	9	2020-12-27 19:30:00
8605	1105	2	9	2019-10-28 19:30:00
8606	1105	2	9	2020-02-16 01:30:00
8607	1105	2	9	2019-09-28 07:45:00
8608	1105	2	9	2020-02-24 00:30:00
8609	1105	2	9	2020-04-28 13:45:00
8610	1105	2	9	2021-02-03 20:15:00
8611	1105	2	9	2019-12-01 09:45:00
8612	1105	2	9	2020-01-24 10:15:00
8613	1105	2	9	2019-10-04 13:15:00
8614	1106	6	12	2020-10-15 20:30:00
8615	1106	6	12	2020-08-01 00:30:00
8616	1106	6	12	2019-03-05 10:45:00
8617	1106	6	12	2020-07-20 07:15:00
8618	1106	6	12	2018-12-08 06:00:00
8619	1107	7	15	2019-06-17 12:30:00
8620	1107	7	15	2018-12-25 18:00:00
8621	1107	7	15	2019-08-11 04:30:00
8622	1107	7	15	2019-10-20 09:45:00
8623	1107	7	15	2019-07-11 21:15:00
8624	1107	7	15	2019-11-11 15:15:00
8625	1107	7	15	2019-08-05 12:45:00
8626	1107	7	15	2019-03-18 13:45:00
8627	1107	7	15	2018-10-01 11:00:00
8628	1107	7	15	2019-11-12 05:15:00
8629	1107	7	15	2019-12-24 10:45:00
8630	1107	7	15	2018-10-25 13:45:00
8631	1107	7	15	2018-02-01 12:15:00
8632	1107	7	15	2019-01-19 12:45:00
8633	1108	13	17	2018-05-04 06:00:00
8634	1108	13	17	2018-04-27 14:30:00
8635	1108	13	17	2018-03-09 07:15:00
8636	1108	13	17	2019-05-11 13:45:00
8637	1108	13	17	2019-07-30 22:45:00
8638	1108	13	17	2018-04-26 01:00:00
8639	1108	13	17	2017-12-02 01:30:00
8640	1108	13	17	2017-09-20 18:30:00
8641	1108	13	17	2018-07-21 06:00:00
8642	1108	13	17	2018-05-04 23:00:00
8643	1109	17	13	2020-09-25 11:45:00
8644	1109	17	13	2020-10-29 04:15:00
8645	1109	17	13	2020-07-10 19:00:00
8646	1109	17	13	2019-12-20 06:45:00
8647	1109	17	13	2021-09-12 03:00:00
8648	1109	17	13	2019-10-07 16:15:00
8649	1109	17	13	2021-06-27 14:30:00
8650	1109	17	13	2021-09-12 17:45:00
8651	1109	17	13	2021-08-07 00:45:00
8652	1109	17	13	2021-05-10 21:45:00
8653	1109	17	13	2020-01-06 04:15:00
8654	1109	17	13	2020-06-10 15:15:00
8655	1109	17	13	2021-06-05 01:15:00
8656	1109	17	13	2019-10-19 12:45:00
8657	1110	11	10	2017-11-15 13:00:00
8658	1110	11	10	2018-09-07 03:15:00
8659	1110	11	10	2017-06-11 16:00:00
8660	1110	11	10	2017-05-15 15:00:00
8661	1111	15	12	2018-04-26 20:45:00
8662	1112	11	3	2018-11-29 13:45:00
8663	1112	11	3	2018-08-01 16:45:00
8664	1112	11	3	2018-04-09 05:30:00
8665	1112	11	3	2019-02-21 08:15:00
8666	1112	11	3	2019-08-05 14:45:00
8667	1112	11	3	2019-10-22 07:30:00
8668	1112	11	3	2019-03-09 16:15:00
8669	1112	11	3	2019-05-25 07:00:00
8670	1112	11	3	2018-11-01 05:00:00
8671	1112	11	3	2018-04-19 16:30:00
8672	1112	11	3	2018-12-12 12:00:00
8673	1112	11	3	2019-02-18 11:45:00
8674	1112	11	3	2018-04-21 15:45:00
8675	1112	11	3	2019-01-18 04:45:00
8676	1113	20	6	2019-11-08 00:15:00
8677	1113	20	6	2019-02-25 22:45:00
8678	1113	20	6	2018-10-11 04:00:00
8679	1113	20	6	2018-06-21 01:15:00
8680	1113	20	6	2018-06-13 04:30:00
8681	1113	20	6	2019-11-11 20:00:00
8682	1113	20	6	2019-07-29 14:15:00
8683	1113	20	6	2018-05-27 23:45:00
8684	1113	20	6	2018-09-04 08:30:00
8685	1113	20	6	2018-04-07 14:15:00
8686	1113	20	6	2018-03-05 06:30:00
8687	1114	16	5	2018-03-21 19:15:00
8688	1115	3	9	2018-08-19 10:00:00
8689	1115	3	9	2017-08-23 21:15:00
8690	1115	3	9	2018-03-25 10:00:00
8691	1115	3	9	2018-06-09 18:30:00
8692	1115	3	9	2018-05-19 13:45:00
8693	1115	3	9	2018-03-01 19:15:00
8694	1115	3	9	2017-05-11 02:00:00
8695	1115	3	9	2017-08-03 07:15:00
8696	1116	6	2	2019-03-04 05:00:00
8697	1116	6	2	2019-07-26 11:15:00
8698	1116	6	2	2019-07-16 06:15:00
8699	1116	6	2	2019-07-13 07:15:00
8700	1116	6	2	2019-01-21 20:30:00
8701	1116	6	2	2018-09-07 18:30:00
8702	1116	6	2	2019-09-28 09:30:00
8703	1117	4	3	2021-06-11 14:00:00
8704	1117	4	3	2020-05-11 20:00:00
8705	1117	4	3	2021-06-04 03:00:00
8706	1117	4	3	2019-12-28 07:15:00
8707	1118	15	3	2017-10-14 11:15:00
8708	1118	15	3	2018-04-23 16:00:00
8709	1118	15	3	2019-04-24 17:45:00
8710	1118	15	3	2018-01-22 06:00:00
8711	1118	15	3	2019-02-08 02:45:00
8712	1118	15	3	2017-12-15 02:45:00
8713	1118	15	3	2019-05-29 07:45:00
8714	1119	4	4	2019-04-09 17:30:00
8715	1119	4	4	2017-12-14 13:15:00
8716	1119	4	4	2019-10-23 05:00:00
8717	1119	4	4	2018-06-02 08:00:00
8718	1119	4	4	2019-09-10 18:45:00
8719	1120	20	8	2019-02-04 01:15:00
8720	1120	20	8	2018-06-27 21:00:00
8721	1120	20	8	2019-04-11 19:15:00
8722	1120	20	8	2019-05-07 06:15:00
8723	1120	20	8	2018-12-15 09:15:00
8724	1120	20	8	2019-02-24 21:00:00
8725	1120	20	8	2018-10-10 19:15:00
8726	1120	20	8	2019-10-05 05:30:00
8727	1121	7	18	2019-11-27 02:15:00
8728	1122	17	19	2019-12-28 03:45:00
8729	1122	17	19	2019-01-21 00:15:00
8730	1122	17	19	2019-01-02 22:45:00
8731	1122	17	19	2018-05-07 12:30:00
8732	1122	17	19	2018-11-11 17:00:00
8733	1122	17	19	2018-10-30 06:00:00
8734	1122	17	19	2020-01-02 19:45:00
8735	1122	17	19	2019-03-10 14:00:00
8736	1122	17	19	2018-06-21 03:45:00
8737	1123	3	11	2019-10-08 13:45:00
8738	1123	3	11	2019-01-28 20:00:00
8739	1124	7	14	2020-01-14 23:45:00
8740	1124	7	14	2021-05-29 16:00:00
8741	1125	11	15	2019-03-01 00:15:00
8742	1126	17	13	2019-04-16 06:45:00
8743	1126	17	13	2018-04-26 01:30:00
8744	1126	17	13	2019-04-06 01:45:00
8745	1126	17	13	2018-04-17 05:30:00
8746	1126	17	13	2020-01-17 08:00:00
8747	1126	17	13	2019-03-05 18:00:00
8748	1126	17	13	2019-05-22 08:45:00
8749	1127	8	17	2020-06-10 19:15:00
8750	1127	8	17	2020-02-06 14:00:00
8751	1128	19	15	2019-06-22 14:00:00
8752	1128	19	15	2019-10-01 09:30:00
8753	1128	19	15	2018-01-09 03:30:00
8754	1128	19	15	2019-01-10 12:30:00
8755	1128	19	15	2019-03-25 01:45:00
8756	1128	19	15	2018-05-03 16:30:00
8757	1128	19	15	2018-10-29 02:00:00
8758	1128	19	15	2017-12-01 00:15:00
8759	1128	19	15	2018-11-07 10:15:00
8760	1129	11	1	2019-02-02 21:00:00
8761	1129	11	1	2019-09-03 09:15:00
8762	1129	11	1	2020-03-20 10:15:00
8763	1129	11	1	2020-06-26 20:00:00
8764	1129	11	1	2020-03-05 01:45:00
8765	1129	11	1	2020-01-08 18:30:00
8766	1129	11	1	2020-12-22 13:30:00
8767	1129	11	1	2019-11-11 07:15:00
8768	1129	11	1	2020-04-19 14:15:00
8769	1129	11	1	2019-06-07 20:45:00
8770	1129	11	1	2020-01-12 04:45:00
8771	1130	3	11	2021-04-22 08:00:00
8772	1130	3	11	2019-12-18 22:30:00
8773	1130	3	11	2021-01-09 09:15:00
8774	1130	3	11	2020-10-10 19:00:00
8775	1130	3	11	2021-05-27 04:00:00
8776	1130	3	11	2019-09-07 13:30:00
8777	1130	3	11	2021-05-09 21:15:00
8778	1130	3	11	2021-06-14 19:30:00
8779	1130	3	11	2021-02-08 06:45:00
8780	1131	6	20	2021-03-07 05:30:00
8781	1131	6	20	2021-06-03 23:00:00
8782	1131	6	20	2021-08-06 15:45:00
8783	1131	6	20	2019-11-04 22:15:00
8784	1131	6	20	2020-10-15 07:45:00
8785	1131	6	20	2020-02-04 04:30:00
8786	1131	6	20	2021-02-02 10:15:00
8787	1132	1	5	2018-10-01 03:30:00
8788	1132	1	5	2019-09-10 09:45:00
8789	1132	1	5	2018-10-15 06:45:00
8790	1132	1	5	2019-09-15 16:30:00
8791	1133	13	19	2017-07-19 06:45:00
8792	1134	10	11	2019-11-04 12:45:00
8793	1134	10	11	2018-09-01 06:30:00
8794	1134	10	11	2018-06-04 21:15:00
8795	1134	10	11	2018-12-21 10:00:00
8796	1134	10	11	2018-07-20 15:00:00
8797	1134	10	11	2020-02-08 23:30:00
8798	1134	10	11	2019-05-12 01:15:00
8799	1134	10	11	2018-05-21 15:15:00
8800	1134	10	11	2018-12-03 23:45:00
8801	1134	10	11	2018-07-29 12:45:00
8802	1134	10	11	2018-10-06 15:30:00
8803	1135	8	13	2020-08-08 12:00:00
8804	1136	4	20	2018-07-12 02:15:00
8805	1136	4	20	2020-03-10 10:45:00
8806	1136	4	20	2019-11-01 17:30:00
8807	1136	4	20	2018-10-22 22:30:00
8808	1136	4	20	2019-04-15 10:15:00
8809	1136	4	20	2020-03-10 07:15:00
8810	1136	4	20	2018-09-06 05:45:00
8811	1136	4	20	2019-08-03 19:30:00
8812	1136	4	20	2019-07-25 00:00:00
8813	1136	4	20	2020-02-03 11:15:00
8814	1136	4	20	2019-01-18 02:30:00
8815	1136	4	20	2018-11-11 20:30:00
8816	1136	4	20	2019-07-29 23:15:00
8817	1136	4	20	2020-04-08 22:00:00
8818	1137	18	3	2017-11-12 06:45:00
8819	1137	18	3	2018-08-06 17:45:00
8820	1137	18	3	2018-11-17 14:45:00
8821	1138	13	15	2021-05-21 02:45:00
8822	1138	13	15	2021-08-22 00:00:00
8823	1138	13	15	2020-12-02 14:45:00
8824	1138	13	15	2021-11-12 14:30:00
8825	1138	13	15	2020-01-07 10:15:00
8826	1138	13	15	2021-11-08 16:15:00
8827	1138	13	15	2020-10-10 00:00:00
8828	1138	13	15	2021-05-10 22:00:00
8829	1138	13	15	2020-12-10 10:45:00
8830	1138	13	15	2021-05-19 01:00:00
8831	1139	3	19	2018-04-23 20:00:00
8832	1139	3	19	2018-11-14 22:00:00
8833	1139	3	19	2017-11-14 03:45:00
8834	1139	3	19	2019-02-08 04:30:00
8835	1139	3	19	2017-11-27 07:45:00
8836	1140	19	7	2019-10-16 06:30:00
8837	1140	19	7	2020-12-05 05:15:00
8838	1140	19	7	2020-03-25 00:45:00
8839	1140	19	7	2020-02-14 11:45:00
8840	1141	12	5	2020-12-20 08:15:00
8841	1141	12	5	2021-05-13 14:15:00
8842	1141	12	5	2021-05-01 21:45:00
8843	1141	12	5	2021-05-01 19:00:00
8844	1141	12	5	2019-10-16 10:30:00
8845	1141	12	5	2020-11-15 07:15:00
8846	1141	12	5	2020-03-01 04:15:00
8847	1141	12	5	2020-01-21 10:00:00
8848	1141	12	5	2021-08-22 19:45:00
8849	1141	12	5	2021-06-04 19:00:00
8850	1142	1	15	2020-04-17 08:30:00
8851	1142	1	15	2018-10-21 15:00:00
8852	1142	1	15	2020-01-03 15:45:00
8853	1143	18	3	2018-10-25 04:45:00
8854	1143	18	3	2018-07-21 08:15:00
8855	1143	18	3	2018-02-12 18:45:00
8856	1143	18	3	2017-06-05 11:30:00
8857	1143	18	3	2017-10-08 02:00:00
8858	1143	18	3	2019-03-29 18:15:00
8859	1143	18	3	2017-11-11 11:45:00
8860	1143	18	3	2019-02-09 14:00:00
8861	1143	18	3	2019-01-02 23:00:00
8862	1144	6	4	2020-12-04 18:30:00
8863	1144	6	4	2020-07-01 21:45:00
8864	1144	6	4	2019-05-30 19:15:00
8865	1144	6	4	2019-06-29 07:00:00
8866	1145	5	9	2021-05-19 19:15:00
8867	1145	5	9	2019-08-17 12:30:00
8868	1145	5	9	2020-09-12 03:45:00
8869	1145	5	9	2021-06-08 15:00:00
8870	1145	5	9	2020-12-03 17:30:00
8871	1145	5	9	2020-03-18 15:45:00
8872	1145	5	9	2020-10-11 04:30:00
8873	1145	5	9	2020-10-28 04:00:00
8874	1145	5	9	2021-03-01 15:30:00
8875	1145	5	9	2021-05-24 09:00:00
8876	1145	5	9	2021-06-21 18:45:00
8877	1145	5	9	2019-12-28 02:30:00
8878	1145	5	9	2020-01-25 16:30:00
8879	1146	17	7	2017-09-20 11:00:00
8880	1146	17	7	2018-07-14 13:15:00
8881	1146	17	7	2017-09-05 12:30:00
8882	1146	17	7	2019-04-25 02:45:00
8883	1146	17	7	2018-06-13 23:30:00
8884	1146	17	7	2019-02-26 15:30:00
8885	1146	17	7	2017-05-21 23:00:00
8886	1146	17	7	2019-04-15 19:15:00
8887	1146	17	7	2019-04-23 07:30:00
8888	1146	17	7	2017-11-25 09:45:00
8889	1146	17	7	2017-09-11 04:15:00
8890	1147	16	8	2020-07-15 11:45:00
8891	1147	16	8	2019-11-04 08:15:00
8892	1147	16	8	2020-05-28 13:30:00
8893	1147	16	8	2019-10-22 16:15:00
8894	1148	8	11	2018-11-21 18:15:00
8895	1148	8	11	2017-12-12 00:30:00
8896	1149	12	17	2019-05-20 17:45:00
8897	1149	12	17	2019-11-13 20:15:00
8898	1149	12	17	2019-10-13 17:00:00
8899	1149	12	17	2019-03-29 00:15:00
8900	1150	18	4	2018-05-17 15:30:00
8901	1150	18	4	2018-03-14 21:00:00
8902	1150	18	4	2019-07-28 06:45:00
8903	1150	18	4	2018-11-09 19:00:00
8904	1150	18	4	2018-07-26 07:00:00
8905	1150	18	4	2019-09-06 04:00:00
8906	1150	18	4	2018-03-23 23:45:00
8907	1150	18	4	2018-03-01 21:45:00
8908	1150	18	4	2018-09-24 14:45:00
8909	1150	18	4	2018-10-18 07:45:00
8910	1150	18	4	2019-12-08 14:45:00
8911	1150	18	4	2019-10-19 09:30:00
8912	1150	18	4	2019-06-12 01:30:00
8913	1151	16	11	2017-12-12 11:00:00
8914	1151	16	11	2018-04-07 23:30:00
8915	1151	16	11	2018-01-15 12:30:00
8916	1151	16	11	2019-01-24 18:15:00
8917	1151	16	11	2017-08-02 14:15:00
8918	1151	16	11	2017-02-16 05:45:00
8919	1151	16	11	2019-01-10 23:45:00
8920	1151	16	11	2018-11-03 10:00:00
8921	1151	16	11	2017-07-07 02:30:00
8922	1152	8	8	2018-11-20 10:15:00
8923	1152	8	8	2019-05-14 15:45:00
8924	1152	8	8	2018-03-28 15:30:00
8925	1152	8	8	2019-11-06 01:30:00
8926	1152	8	8	2019-12-09 18:15:00
8927	1152	8	8	2018-02-23 18:30:00
8928	1152	8	8	2018-09-14 12:00:00
8929	1152	8	8	2018-04-09 13:45:00
8930	1152	8	8	2018-06-04 12:00:00
8931	1152	8	8	2018-02-01 18:00:00
8932	1152	8	8	2019-05-08 06:15:00
8933	1152	8	8	2018-11-01 20:30:00
8934	1152	8	8	2019-03-18 21:45:00
8935	1153	11	17	2019-06-11 12:30:00
8936	1153	11	17	2020-01-25 16:45:00
8937	1153	11	17	2020-10-25 21:30:00
8938	1153	11	17	2020-05-03 03:30:00
8939	1154	16	11	2020-12-02 10:15:00
8940	1154	16	11	2020-12-18 18:00:00
8941	1154	16	11	2019-08-01 23:45:00
8942	1154	16	11	2019-10-28 04:00:00
8943	1154	16	11	2020-04-29 02:30:00
8944	1154	16	11	2021-02-13 11:30:00
8945	1154	16	11	2019-05-22 08:30:00
8946	1154	16	11	2019-07-05 04:30:00
8947	1154	16	11	2019-05-03 07:15:00
8948	1154	16	11	2019-06-07 02:30:00
8949	1154	16	11	2019-07-18 06:45:00
8950	1154	16	11	2019-12-25 12:15:00
8951	1155	9	18	2018-12-10 06:30:00
8952	1155	9	18	2019-03-09 17:45:00
8953	1155	9	18	2019-07-24 03:45:00
8954	1155	9	18	2018-01-07 04:00:00
8955	1155	9	18	2019-07-24 11:30:00
8956	1155	9	18	2019-05-10 18:45:00
8957	1155	9	18	2018-03-04 14:00:00
8958	1155	9	18	2019-08-18 05:30:00
8959	1155	9	18	2018-06-20 05:15:00
8960	1155	9	18	2017-10-30 05:00:00
8961	1155	9	18	2018-01-27 14:15:00
8962	1155	9	18	2017-11-22 00:00:00
8963	1156	8	11	2019-01-14 05:30:00
8964	1156	8	11	2019-09-24 22:45:00
8965	1156	8	11	2018-10-14 15:45:00
8966	1156	8	11	2020-07-13 05:15:00
8967	1156	8	11	2020-04-26 13:00:00
8968	1156	8	11	2019-02-21 10:15:00
8969	1156	8	11	2018-12-26 23:00:00
8970	1156	8	11	2019-05-13 16:15:00
8971	1156	8	11	2019-03-07 15:45:00
8972	1156	8	11	2019-02-11 14:00:00
8973	1157	17	19	2019-02-15 18:00:00
8974	1157	17	19	2017-07-10 02:45:00
8975	1157	17	19	2018-06-10 12:45:00
8976	1157	17	19	2018-01-18 14:00:00
8977	1157	17	19	2018-12-25 15:15:00
8978	1157	17	19	2018-03-20 21:15:00
8979	1157	17	19	2017-09-15 16:30:00
8980	1158	8	12	2018-10-09 14:15:00
8981	1158	8	12	2018-02-14 06:15:00
8982	1158	8	12	2018-05-19 10:15:00
8983	1158	8	12	2018-06-07 23:00:00
8984	1158	8	12	2019-04-27 05:00:00
8985	1158	8	12	2018-04-18 02:00:00
8986	1158	8	12	2018-07-16 14:45:00
8987	1158	8	12	2018-04-12 09:15:00
8988	1159	15	16	2017-10-04 11:45:00
8989	1159	15	16	2018-10-06 18:00:00
8990	1159	15	16	2019-04-29 09:15:00
8991	1159	15	16	2018-04-09 12:15:00
8992	1159	15	16	2019-05-13 00:45:00
8993	1159	15	16	2019-02-04 22:30:00
8994	1159	15	16	2019-04-02 22:00:00
8995	1159	15	16	2018-02-20 14:45:00
8996	1159	15	16	2018-01-09 00:30:00
8997	1159	15	16	2017-09-09 15:00:00
8998	1159	15	16	2018-11-17 20:15:00
8999	1159	15	16	2018-09-09 16:45:00
9000	1159	15	16	2018-01-24 14:45:00
9001	1159	15	16	2019-02-03 12:00:00
9002	1160	2	6	2021-02-08 12:30:00
9003	1160	2	6	2019-10-22 23:45:00
9004	1160	2	6	2021-02-18 03:00:00
9005	1160	2	6	2020-07-19 04:00:00
9006	1160	2	6	2021-02-21 03:45:00
9007	1161	20	18	2020-06-09 05:00:00
9008	1161	20	18	2020-03-26 19:45:00
9009	1161	20	18	2020-07-27 23:00:00
9010	1161	20	18	2019-05-24 18:15:00
9011	1161	20	18	2019-12-29 20:30:00
9012	1161	20	18	2019-12-20 21:00:00
9013	1161	20	18	2020-08-09 04:15:00
9014	1161	20	18	2020-07-24 08:15:00
9015	1161	20	18	2019-08-26 20:45:00
9016	1161	20	18	2019-10-14 18:45:00
9017	1162	19	3	2019-12-10 05:45:00
9018	1162	19	3	2019-08-15 23:30:00
9019	1162	19	3	2019-09-23 10:30:00
9020	1162	19	3	2018-09-17 02:30:00
9021	1162	19	3	2019-03-28 02:30:00
9022	1163	16	5	2019-07-30 04:30:00
9023	1163	16	5	2020-02-13 21:15:00
9024	1163	16	5	2020-08-03 12:30:00
9025	1163	16	5	2019-06-07 23:45:00
9026	1163	16	5	2020-12-29 12:00:00
9027	1163	16	5	2020-06-12 15:30:00
9028	1163	16	5	2020-11-22 02:45:00
9029	1164	7	14	2019-02-01 18:45:00
9030	1164	7	14	2020-01-08 15:45:00
9031	1164	7	14	2019-06-16 05:00:00
9032	1164	7	14	2020-02-25 00:15:00
9033	1164	7	14	2019-11-03 03:00:00
9034	1164	7	14	2020-03-01 23:15:00
9035	1165	14	12	2020-09-19 07:15:00
9036	1165	14	12	2020-05-08 19:30:00
9037	1165	14	12	2020-06-21 05:30:00
9038	1165	14	12	2020-11-28 07:00:00
9039	1166	17	4	2019-07-17 11:30:00
9040	1166	17	4	2018-12-01 19:45:00
9041	1166	17	4	2019-07-16 04:00:00
9042	1166	17	4	2019-01-11 21:00:00
9043	1166	17	4	2020-08-19 03:30:00
9044	1166	17	4	2019-02-20 00:15:00
9045	1166	17	4	2020-02-12 09:00:00
9046	1166	17	4	2018-11-08 09:45:00
9047	1166	17	4	2019-10-11 09:15:00
9048	1166	17	4	2020-03-28 19:15:00
9049	1166	17	4	2020-07-21 17:00:00
9050	1166	17	4	2020-07-05 19:15:00
9051	1166	17	4	2019-07-25 14:30:00
9052	1166	17	4	2019-07-14 21:00:00
9053	1167	5	14	2021-07-28 16:00:00
9054	1167	5	14	2020-03-12 14:30:00
9055	1167	5	14	2020-02-09 20:30:00
9056	1167	5	14	2021-08-13 07:30:00
9057	1167	5	14	2020-09-17 18:15:00
9058	1167	5	14	2021-12-18 17:30:00
9059	1167	5	14	2021-06-01 15:30:00
9060	1167	5	14	2020-04-19 13:30:00
9061	1167	5	14	2021-04-29 13:45:00
9062	1167	5	14	2020-11-04 06:00:00
9063	1167	5	14	2020-01-20 11:45:00
9064	1167	5	14	2021-03-09 22:30:00
9065	1167	5	14	2021-01-06 09:00:00
9066	1167	5	14	2020-12-25 00:30:00
9067	1168	12	13	2017-04-22 16:00:00
9068	1168	12	13	2017-08-11 17:00:00
9069	1168	12	13	2018-09-02 02:30:00
9070	1168	12	13	2017-04-21 10:15:00
9071	1168	12	13	2018-08-13 20:30:00
9072	1168	12	13	2018-04-09 23:45:00
9073	1168	12	13	2018-04-24 07:15:00
9074	1168	12	13	2017-04-06 16:45:00
9075	1168	12	13	2018-01-13 04:00:00
9076	1169	1	2	2020-01-03 21:15:00
9077	1169	1	2	2020-09-01 12:00:00
9078	1169	1	2	2019-03-22 19:30:00
9079	1169	1	2	2019-12-26 01:00:00
9080	1169	1	2	2019-04-05 18:45:00
9081	1170	15	5	2019-07-08 05:00:00
9082	1170	15	5	2019-03-02 11:30:00
9083	1170	15	5	2019-12-06 12:45:00
9084	1171	1	4	2019-12-14 23:15:00
9085	1171	1	4	2019-08-12 22:15:00
9086	1171	1	4	2019-01-25 05:00:00
9087	1171	1	4	2019-05-01 22:15:00
9088	1171	1	4	2020-06-22 12:00:00
9089	1171	1	4	2019-07-20 21:00:00
9090	1171	1	4	2019-02-09 20:30:00
9091	1171	1	4	2018-11-10 01:30:00
9092	1171	1	4	2018-11-14 17:00:00
9093	1172	19	3	2019-06-18 08:45:00
9094	1172	19	3	2020-03-04 04:15:00
9095	1172	19	3	2019-12-25 15:00:00
9096	1172	19	3	2019-07-09 01:15:00
9097	1172	19	3	2019-06-11 03:15:00
9098	1172	19	3	2019-04-03 11:15:00
9099	1172	19	3	2019-08-11 11:45:00
9100	1172	19	3	2019-04-10 18:15:00
9101	1172	19	3	2019-09-12 16:45:00
9102	1172	19	3	2020-05-01 22:00:00
9103	1172	19	3	2020-02-13 09:00:00
9104	1172	19	3	2019-06-12 02:45:00
9105	1172	19	3	2019-02-11 11:45:00
9106	1173	9	16	2019-11-23 18:30:00
9107	1173	9	16	2019-03-22 08:30:00
9108	1173	9	16	2019-02-18 11:45:00
9109	1173	9	16	2018-01-30 17:30:00
9110	1173	9	16	2018-08-03 16:45:00
9111	1173	9	16	2019-12-04 08:15:00
9112	1173	9	16	2018-05-27 10:15:00
9113	1173	9	16	2018-08-23 06:00:00
9114	1173	9	16	2019-01-28 19:00:00
9115	1174	18	6	2020-12-05 18:15:00
9116	1174	18	6	2020-04-24 19:00:00
9117	1174	18	6	2020-12-25 03:00:00
9118	1174	18	6	2019-12-13 17:45:00
9119	1174	18	6	2020-02-09 22:00:00
9120	1174	18	6	2021-09-30 22:45:00
9121	1174	18	6	2019-12-09 10:00:00
9122	1174	18	6	2020-03-01 23:45:00
9123	1174	18	6	2020-09-21 17:15:00
9124	1174	18	6	2020-01-05 08:00:00
9125	1174	18	6	2020-07-23 12:45:00
9126	1174	18	6	2021-04-03 18:30:00
9127	1175	3	4	2021-01-27 14:15:00
9128	1175	3	4	2019-09-24 07:00:00
9129	1175	3	4	2019-05-04 11:30:00
9130	1175	3	4	2021-02-25 20:15:00
9131	1175	3	4	2020-01-16 18:30:00
9132	1175	3	4	2019-05-19 00:30:00
9133	1175	3	4	2019-10-21 20:45:00
9134	1175	3	4	2019-11-05 21:15:00
9135	1176	8	20	2017-04-24 09:00:00
9136	1176	8	20	2018-08-04 16:00:00
9137	1176	8	20	2018-12-13 13:30:00
9138	1177	10	13	2019-08-28 23:00:00
9139	1177	10	13	2018-06-05 06:45:00
9140	1177	10	13	2020-02-08 04:30:00
9141	1177	10	13	2019-05-19 02:00:00
9142	1177	10	13	2019-09-29 11:45:00
9143	1177	10	13	2020-02-12 17:15:00
9144	1178	9	3	2019-11-11 15:00:00
9145	1178	9	3	2020-01-14 17:00:00
9146	1178	9	3	2019-05-30 04:30:00
9147	1178	9	3	2019-03-27 09:00:00
9148	1179	14	11	2018-12-17 14:15:00
9149	1179	14	11	2018-11-14 15:15:00
9150	1179	14	11	2018-08-28 16:45:00
9151	1179	14	11	2018-05-21 03:15:00
9152	1179	14	11	2018-06-03 11:30:00
9153	1179	14	11	2018-12-11 08:30:00
9154	1179	14	11	2017-11-20 06:45:00
9155	1180	1	13	2019-11-23 21:15:00
9156	1180	1	13	2021-08-25 15:15:00
9157	1180	1	13	2020-10-19 10:15:00
9158	1180	1	13	2021-09-14 16:45:00
9159	1180	1	13	2020-01-19 22:00:00
9160	1180	1	13	2020-12-10 19:15:00
9161	1180	1	13	2020-09-25 09:00:00
9162	1180	1	13	2021-04-12 03:45:00
9163	1180	1	13	2020-06-01 01:45:00
9164	1180	1	13	2020-01-17 20:15:00
9165	1180	1	13	2021-06-01 02:15:00
9166	1180	1	13	2020-07-30 17:45:00
9167	1180	1	13	2020-06-16 10:00:00
9168	1180	1	13	2020-01-16 13:45:00
9169	1181	11	9	2018-06-21 04:00:00
9170	1181	11	9	2017-09-16 01:30:00
9171	1181	11	9	2017-08-03 05:15:00
9172	1181	11	9	2018-10-05 15:45:00
9173	1181	11	9	2018-11-30 13:30:00
9174	1181	11	9	2018-03-05 18:00:00
9175	1181	11	9	2018-10-06 07:00:00
9176	1181	11	9	2017-07-15 09:30:00
9177	1182	10	15	2017-05-08 02:00:00
9178	1182	10	15	2018-02-03 20:15:00
9179	1182	10	15	2017-12-15 15:30:00
9180	1182	10	15	2017-07-12 09:15:00
9181	1182	10	15	2017-05-18 06:45:00
9182	1182	10	15	2018-12-13 01:45:00
9183	1182	10	15	2017-11-19 17:15:00
9184	1182	10	15	2017-07-05 12:00:00
9185	1182	10	15	2018-05-15 15:15:00
9186	1183	5	3	2020-06-08 18:45:00
9187	1183	5	3	2019-10-17 04:00:00
9188	1184	7	19	2020-03-15 05:30:00
9189	1184	7	19	2019-03-04 08:15:00
9190	1184	7	19	2019-08-11 12:00:00
9191	1184	7	19	2019-09-08 11:30:00
9192	1184	7	19	2019-04-09 09:45:00
9193	1184	7	19	2018-09-01 00:00:00
9194	1184	7	19	2020-03-18 13:45:00
9195	1184	7	19	2019-12-28 21:15:00
9196	1184	7	19	2019-03-07 17:45:00
9197	1184	7	19	2018-12-19 08:00:00
9198	1184	7	19	2018-07-04 01:45:00
9199	1185	4	15	2019-06-15 15:00:00
9200	1185	4	15	2020-03-14 05:15:00
9201	1185	4	15	2019-02-12 12:30:00
9202	1185	4	15	2019-08-30 22:30:00
9203	1185	4	15	2018-06-15 21:45:00
9204	1185	4	15	2019-05-23 14:45:00
9205	1185	4	15	2019-11-20 21:45:00
9206	1185	4	15	2018-05-28 11:15:00
9207	1185	4	15	2019-06-24 06:45:00
9208	1185	4	15	2019-04-30 02:45:00
9209	1185	4	15	2019-12-21 19:30:00
9210	1185	4	15	2019-04-21 07:00:00
9211	1185	4	15	2020-01-27 16:45:00
9212	1186	2	11	2019-05-22 11:45:00
9213	1186	2	11	2021-03-01 01:00:00
9214	1186	2	11	2019-10-26 18:45:00
9215	1186	2	11	2019-07-08 11:30:00
9216	1186	2	11	2020-07-14 20:00:00
9217	1186	2	11	2019-10-16 18:30:00
9218	1186	2	11	2020-04-28 22:45:00
9219	1186	2	11	2021-01-15 21:15:00
9220	1187	1	16	2020-02-18 19:00:00
9221	1187	1	16	2019-12-01 15:00:00
9222	1187	1	16	2019-11-07 14:00:00
9223	1187	1	16	2020-06-12 13:30:00
9224	1187	1	16	2019-12-23 13:00:00
9225	1187	1	16	2018-09-07 17:15:00
9226	1187	1	16	2018-10-16 12:00:00
9227	1187	1	16	2019-10-21 01:45:00
9228	1187	1	16	2018-09-25 05:45:00
9229	1188	4	2	2020-02-25 04:30:00
9230	1188	4	2	2018-06-30 01:00:00
9231	1189	1	12	2020-01-26 22:00:00
9232	1189	1	12	2020-03-14 23:15:00
9233	1189	1	12	2020-03-04 18:15:00
9234	1189	1	12	2018-11-25 09:00:00
9235	1189	1	12	2018-05-24 00:15:00
9236	1189	1	12	2019-07-21 01:45:00
9237	1189	1	12	2020-04-11 10:30:00
9238	1189	1	12	2018-08-29 20:30:00
9239	1189	1	12	2019-12-08 16:45:00
9240	1189	1	12	2019-08-02 01:30:00
9241	1189	1	12	2018-11-04 20:45:00
9242	1189	1	12	2019-10-05 23:15:00
9243	1190	5	6	2021-02-27 12:15:00
9244	1190	5	6	2021-09-23 07:45:00
9245	1190	5	6	2021-02-19 00:30:00
9246	1190	5	6	2019-11-07 10:30:00
9247	1190	5	6	2021-02-06 15:15:00
9248	1190	5	6	2020-12-30 22:15:00
9249	1190	5	6	2021-04-18 14:45:00
9250	1190	5	6	2020-03-08 21:30:00
9251	1190	5	6	2019-12-19 16:30:00
9252	1190	5	6	2021-01-08 00:45:00
9253	1190	5	6	2020-01-30 04:15:00
9254	1190	5	6	2021-09-28 13:15:00
9255	1190	5	6	2021-06-02 13:00:00
9256	1191	10	15	2018-08-29 01:30:00
9257	1191	10	15	2018-03-12 16:00:00
9258	1191	10	15	2018-02-10 23:00:00
9259	1191	10	15	2017-05-02 17:15:00
9260	1191	10	15	2018-01-14 20:30:00
9261	1191	10	15	2018-05-20 00:45:00
9262	1191	10	15	2018-01-22 19:30:00
9263	1191	10	15	2018-01-30 06:00:00
9264	1191	10	15	2018-07-09 22:00:00
9265	1191	10	15	2018-07-29 16:00:00
9266	1191	10	15	2017-08-20 14:45:00
9267	1191	10	15	2018-06-30 15:30:00
9268	1191	10	15	2018-03-06 10:15:00
9269	1192	15	10	2019-08-04 10:30:00
9270	1192	15	10	2019-08-09 00:00:00
9271	1192	15	10	2019-08-23 17:30:00
9272	1192	15	10	2019-09-18 00:15:00
9273	1192	15	10	2019-07-28 22:45:00
9274	1192	15	10	2019-01-08 17:15:00
9275	1192	15	10	2019-01-16 12:30:00
9276	1192	15	10	2018-08-05 06:30:00
9277	1192	15	10	2018-05-04 08:45:00
9278	1192	15	10	2019-07-27 18:00:00
9279	1192	15	10	2018-05-03 16:00:00
9280	1192	15	10	2018-12-11 18:00:00
9281	1193	11	14	2018-05-01 21:30:00
9282	1193	11	14	2019-04-15 09:00:00
9283	1193	11	14	2018-11-03 09:45:00
9284	1193	11	14	2018-10-29 15:30:00
9285	1193	11	14	2018-08-22 05:00:00
9286	1193	11	14	2018-11-24 11:30:00
9287	1193	11	14	2018-08-08 01:15:00
9288	1193	11	14	2018-06-25 15:15:00
9289	1193	11	14	2019-01-19 21:00:00
9290	1193	11	14	2017-12-17 23:45:00
9291	1193	11	14	2018-10-13 02:00:00
9292	1193	11	14	2018-05-07 08:00:00
9293	1193	11	14	2017-12-18 06:45:00
9294	1194	16	8	2021-03-05 17:45:00
9295	1194	16	8	2020-08-07 20:45:00
9296	1194	16	8	2019-08-09 06:15:00
9297	1194	16	8	2020-01-04 01:00:00
9298	1194	16	8	2019-08-09 17:30:00
9299	1194	16	8	2020-05-10 18:00:00
9300	1194	16	8	2021-05-16 12:30:00
9301	1194	16	8	2020-10-20 23:30:00
9302	1194	16	8	2021-02-18 01:45:00
9303	1194	16	8	2019-12-03 19:30:00
9304	1194	16	8	2020-05-08 21:00:00
9305	1194	16	8	2019-10-08 05:30:00
9306	1195	20	1	2020-04-12 07:30:00
9307	1195	20	1	2019-12-01 02:30:00
9308	1195	20	1	2020-11-30 13:00:00
9309	1195	20	1	2020-05-23 10:00:00
9310	1195	20	1	2020-12-19 09:15:00
9311	1195	20	1	2020-06-13 04:30:00
9312	1195	20	1	2019-08-01 00:00:00
9313	1195	20	1	2019-09-09 14:30:00
9314	1195	20	1	2019-11-18 19:15:00
9315	1195	20	1	2019-07-30 18:45:00
9316	1195	20	1	2021-04-24 20:15:00
9317	1195	20	1	2019-12-22 22:30:00
9318	1195	20	1	2020-07-27 09:00:00
9319	1195	20	1	2020-05-21 15:15:00
9320	1196	10	2	2020-08-01 02:45:00
9321	1196	10	2	2020-08-22 10:15:00
9322	1196	10	2	2019-04-23 20:00:00
9323	1196	10	2	2020-08-11 10:45:00
9324	1196	10	2	2019-10-19 10:30:00
9325	1196	10	2	2019-05-03 13:15:00
9326	1196	10	2	2019-05-27 03:15:00
9327	1196	10	2	2020-05-28 05:00:00
9328	1196	10	2	2019-04-09 19:30:00
9329	1196	10	2	2019-11-19 21:15:00
9330	1197	19	2	2021-03-04 21:00:00
9331	1197	19	2	2020-08-17 10:45:00
9332	1197	19	2	2020-06-24 09:30:00
9333	1197	19	2	2021-03-19 04:00:00
9334	1197	19	2	2021-01-16 03:00:00
9335	1197	19	2	2020-05-09 06:15:00
9336	1197	19	2	2021-06-01 14:45:00
9337	1198	2	14	2017-04-27 23:15:00
9338	1198	2	14	2017-04-09 18:15:00
9339	1198	2	14	2017-09-26 21:45:00
9340	1198	2	14	2018-08-29 01:00:00
9341	1199	4	20	2019-08-22 23:30:00
9342	1199	4	20	2020-09-24 13:30:00
9343	1199	4	20	2020-12-21 01:00:00
9344	1199	4	20	2020-01-27 17:00:00
9345	1199	4	20	2020-02-10 16:30:00
9346	1199	4	20	2020-04-02 05:15:00
9347	1199	4	20	2020-05-06 02:00:00
9348	1199	4	20	2021-05-27 11:30:00
9349	1199	4	20	2020-05-20 16:45:00
9350	1199	4	20	2020-09-12 05:00:00
9351	1199	4	20	2020-06-06 15:15:00
9352	1199	4	20	2020-10-18 03:30:00
9353	1199	4	20	2019-12-14 06:15:00
9354	1199	4	20	2020-05-20 00:00:00
9355	1199	4	20	2020-10-10 22:45:00
9356	1200	11	11	2018-01-16 23:30:00
9357	1200	11	11	2017-08-02 16:45:00
9358	1200	11	11	2017-12-16 01:00:00
9359	1200	11	11	2018-10-16 14:15:00
9360	1200	11	11	2017-09-30 09:45:00
9361	1200	11	11	2019-04-17 03:15:00
9362	1200	11	11	2017-07-14 01:15:00
9363	1200	11	11	2017-08-14 12:00:00
9364	1200	11	11	2018-06-04 13:00:00
9365	1200	11	11	2018-11-26 09:30:00
9366	1200	11	11	2017-08-12 13:15:00
9367	1201	8	5	2018-03-07 00:00:00
9368	1201	8	5	2018-09-02 19:15:00
9369	1201	8	5	2018-12-10 11:45:00
9370	1201	8	5	2019-03-16 07:00:00
9371	1201	8	5	2018-11-05 23:45:00
9372	1201	8	5	2018-06-26 09:00:00
9373	1201	8	5	2019-01-01 13:30:00
9374	1201	8	5	2018-02-03 23:45:00
9375	1201	8	5	2019-07-14 21:30:00
9376	1201	8	5	2018-06-29 13:45:00
9377	1201	8	5	2019-01-08 22:45:00
9378	1201	8	5	2019-05-12 00:00:00
9379	1202	11	8	2019-07-18 09:45:00
9380	1202	11	8	2017-11-26 04:00:00
9381	1202	11	8	2018-11-29 13:30:00
9382	1202	11	8	2019-09-04 12:45:00
9383	1202	11	8	2019-07-22 12:45:00
9384	1202	11	8	2019-09-20 00:45:00
9385	1202	11	8	2018-04-21 18:45:00
9386	1202	11	8	2019-03-09 12:00:00
9387	1202	11	8	2017-11-10 11:30:00
9388	1202	11	8	2019-09-25 16:00:00
9389	1203	15	14	2021-02-24 18:00:00
9390	1203	15	14	2020-01-07 16:00:00
9391	1203	15	14	2021-08-27 08:00:00
9392	1203	15	14	2021-01-06 07:45:00
9393	1203	15	14	2021-05-09 00:00:00
9394	1203	15	14	2021-04-12 10:00:00
9395	1203	15	14	2021-09-15 04:30:00
9396	1203	15	14	2020-12-17 14:00:00
9397	1203	15	14	2019-12-14 15:15:00
9398	1203	15	14	2020-11-07 20:00:00
9399	1203	15	14	2020-11-18 00:30:00
9400	1203	15	14	2021-07-15 13:30:00
9401	1203	15	14	2020-01-13 21:45:00
9402	1203	15	14	2020-11-16 23:30:00
9403	1203	15	14	2020-05-20 22:15:00
9404	1204	11	8	2020-07-10 22:45:00
9405	1204	11	8	2021-10-03 20:15:00
9406	1204	11	8	2020-03-06 15:45:00
9407	1204	11	8	2020-08-17 15:30:00
9408	1204	11	8	2021-05-20 02:15:00
9409	1204	11	8	2019-12-14 08:15:00
9410	1204	11	8	2021-03-21 15:15:00
9411	1204	11	8	2020-07-14 13:00:00
9412	1204	11	8	2021-10-29 03:00:00
9413	1204	11	8	2021-02-13 21:30:00
9414	1204	11	8	2020-02-20 12:15:00
9415	1204	11	8	2020-12-16 02:45:00
9416	1204	11	8	2020-08-25 16:15:00
9417	1204	11	8	2020-09-17 21:00:00
9418	1204	11	8	2021-08-29 16:00:00
9419	1205	7	9	2020-04-02 06:30:00
9420	1205	7	9	2021-10-10 16:15:00
9421	1205	7	9	2021-04-22 13:00:00
9422	1206	4	10	2021-01-18 16:45:00
9423	1206	4	10	2021-06-10 08:45:00
9424	1206	4	10	2021-02-02 10:45:00
9425	1206	4	10	2020-04-13 23:00:00
9426	1206	4	10	2020-05-07 13:45:00
9427	1206	4	10	2021-07-23 22:15:00
9428	1207	10	12	2018-08-20 20:45:00
9429	1207	10	12	2018-01-20 14:45:00
9430	1207	10	12	2018-01-13 15:45:00
9431	1207	10	12	2018-09-23 10:45:00
9432	1207	10	12	2019-11-08 13:30:00
9433	1207	10	12	2018-05-16 10:45:00
9434	1207	10	12	2018-08-04 08:15:00
9435	1207	10	12	2019-11-30 00:30:00
9436	1208	7	8	2019-02-10 23:15:00
9437	1208	7	8	2019-03-15 12:30:00
9438	1208	7	8	2018-05-07 06:45:00
9439	1208	7	8	2018-12-05 17:00:00
9440	1208	7	8	2018-10-30 03:00:00
9441	1208	7	8	2018-06-16 19:00:00
9442	1208	7	8	2018-02-16 06:00:00
9443	1208	7	8	2019-11-16 04:45:00
9444	1208	7	8	2018-04-09 00:30:00
9445	1208	7	8	2019-08-20 15:15:00
9446	1208	7	8	2019-10-13 07:15:00
9447	1208	7	8	2019-07-24 09:15:00
9448	1208	7	8	2019-03-01 19:45:00
9449	1209	11	9	2020-05-20 13:45:00
9450	1209	11	9	2019-07-07 14:30:00
9451	1209	11	9	2019-01-15 17:30:00
9452	1209	11	9	2019-04-03 22:15:00
9453	1209	11	9	2019-03-16 17:00:00
9454	1209	11	9	2019-03-16 13:45:00
9455	1210	7	5	2020-05-29 21:30:00
9456	1210	7	5	2021-02-17 20:45:00
9457	1210	7	5	2020-08-22 20:00:00
9458	1210	7	5	2020-09-22 01:00:00
9459	1211	7	14	2019-04-17 05:30:00
9460	1211	7	14	2020-05-22 02:15:00
9461	1211	7	14	2019-08-21 07:00:00
9462	1211	7	14	2020-01-22 01:45:00
9463	1211	7	14	2021-01-28 04:15:00
9464	1212	20	10	2020-11-16 11:15:00
9465	1212	20	10	2020-08-16 13:45:00
9466	1212	20	10	2021-02-18 23:00:00
9467	1212	20	10	2020-09-21 14:00:00
9468	1212	20	10	2021-10-16 20:45:00
9469	1212	20	10	2021-11-12 23:00:00
9470	1212	20	10	2020-05-05 16:15:00
9471	1212	20	10	2020-03-01 19:45:00
9472	1213	18	12	2019-10-18 02:45:00
9473	1213	18	12	2018-09-28 13:30:00
9474	1213	18	12	2018-07-06 20:00:00
9475	1214	6	13	2019-05-26 16:30:00
9476	1214	6	13	2019-03-21 23:45:00
9477	1214	6	13	2020-02-17 03:00:00
9478	1214	6	13	2019-08-22 10:00:00
9479	1214	6	13	2019-07-11 23:30:00
9480	1214	6	13	2018-08-01 12:45:00
9481	1214	6	13	2019-12-21 20:00:00
9482	1214	6	13	2019-12-17 19:45:00
9483	1214	6	13	2018-07-12 18:00:00
9484	1214	6	13	2020-01-28 04:45:00
9485	1214	6	13	2019-10-02 19:45:00
9486	1215	9	15	2020-12-11 12:45:00
9487	1215	9	15	2020-10-06 16:45:00
9488	1215	9	15	2020-10-30 00:30:00
9489	1215	9	15	2020-07-13 16:30:00
9490	1215	9	15	2020-06-28 03:45:00
9491	1215	9	15	2019-11-28 15:45:00
9492	1216	9	19	2019-11-28 12:15:00
9493	1216	9	19	2019-10-05 01:45:00
9494	1216	9	19	2018-11-10 20:45:00
9495	1216	9	19	2020-10-24 11:15:00
9496	1216	9	19	2019-09-02 15:00:00
9497	1216	9	19	2020-06-20 07:45:00
9498	1216	9	19	2020-07-10 19:30:00
9499	1216	9	19	2020-05-22 05:15:00
9500	1216	9	19	2019-08-15 15:30:00
9501	1216	9	19	2019-09-04 09:00:00
9502	1216	9	19	2019-08-03 07:45:00
9503	1216	9	19	2018-11-27 00:00:00
9504	1216	9	19	2020-08-30 13:30:00
9505	1217	12	14	2019-08-22 01:00:00
9506	1217	12	14	2019-11-29 18:15:00
9507	1217	12	14	2019-02-15 11:30:00
9508	1217	12	14	2019-12-14 21:00:00
9509	1217	12	14	2019-03-09 18:45:00
9510	1217	12	14	2019-01-03 11:15:00
9511	1217	12	14	2019-01-16 01:00:00
9512	1217	12	14	2019-06-28 16:00:00
9513	1217	12	14	2018-04-26 05:00:00
9514	1218	10	12	2019-06-28 05:45:00
9515	1218	10	12	2018-08-11 20:45:00
9516	1218	10	12	2019-04-20 19:15:00
9517	1218	10	12	2019-03-01 08:30:00
9518	1219	11	6	2019-03-02 17:30:00
9519	1219	11	6	2019-06-28 08:00:00
9520	1219	11	6	2019-05-17 23:15:00
9521	1219	11	6	2020-02-03 09:45:00
9522	1219	11	6	2019-12-28 05:00:00
9523	1219	11	6	2019-07-03 03:15:00
9524	1219	11	6	2019-04-05 03:30:00
9525	1220	7	9	2020-06-11 11:45:00
9526	1220	7	9	2019-12-14 19:15:00
9527	1220	7	9	2019-12-11 01:45:00
9528	1220	7	9	2020-07-19 17:00:00
9529	1220	7	9	2019-02-03 13:45:00
9530	1220	7	9	2019-03-09 15:45:00
9531	1220	7	9	2020-04-13 18:00:00
9532	1220	7	9	2019-10-16 14:15:00
9533	1220	7	9	2020-06-29 13:00:00
9534	1220	7	9	2019-10-21 03:30:00
9535	1220	7	9	2020-04-18 21:45:00
9536	1220	7	9	2020-07-13 10:00:00
9537	1220	7	9	2020-04-27 22:15:00
9538	1221	13	10	2017-11-28 08:45:00
9539	1221	13	10	2018-01-16 12:45:00
9540	1221	13	10	2017-08-30 09:45:00
9541	1221	13	10	2018-07-01 10:15:00
9542	1222	1	5	2019-04-06 10:00:00
9543	1223	8	5	2019-04-04 05:15:00
9544	1223	8	5	2020-01-07 06:15:00
9545	1223	8	5	2018-04-07 22:30:00
9546	1223	8	5	2018-08-22 00:00:00
9547	1223	8	5	2019-12-04 06:45:00
9548	1223	8	5	2018-08-15 05:45:00
9549	1223	8	5	2019-08-26 21:45:00
9550	1223	8	5	2019-06-08 06:45:00
9551	1223	8	5	2019-04-16 17:45:00
9552	1223	8	5	2018-07-12 18:30:00
9553	1223	8	5	2019-10-18 09:00:00
9554	1224	4	3	2018-10-10 08:15:00
9555	1224	4	3	2017-04-01 05:00:00
9556	1224	4	3	2017-10-30 19:30:00
9557	1224	4	3	2019-01-24 09:00:00
9558	1225	18	2	2019-08-09 00:30:00
9559	1225	18	2	2019-07-24 11:30:00
9560	1225	18	2	2019-12-26 13:30:00
9561	1225	18	2	2020-10-03 20:15:00
9562	1225	18	2	2020-08-20 17:45:00
9563	1225	18	2	2019-09-15 22:30:00
9564	1225	18	2	2020-06-16 07:15:00
9565	1225	18	2	2020-11-15 08:45:00
9566	1225	18	2	2019-07-06 12:00:00
9567	1225	18	2	2019-01-14 11:45:00
9568	1225	18	2	2019-09-12 03:30:00
9569	1225	18	2	2020-11-13 20:15:00
9570	1226	14	10	2018-04-11 19:45:00
9571	1226	14	10	2017-09-28 22:45:00
9572	1226	14	10	2018-03-19 00:00:00
9573	1226	14	10	2018-09-22 22:30:00
9574	1226	14	10	2018-07-03 02:00:00
9575	1226	14	10	2018-01-23 15:15:00
9576	1227	16	6	2020-04-02 18:15:00
9577	1228	9	3	2019-02-13 06:15:00
9578	1228	9	3	2018-04-16 18:00:00
9579	1228	9	3	2019-01-28 01:15:00
9580	1228	9	3	2018-04-29 10:30:00
9581	1228	9	3	2018-07-10 13:45:00
9582	1228	9	3	2019-03-20 13:45:00
9583	1228	9	3	2018-07-12 07:15:00
9584	1228	9	3	2018-10-25 07:15:00
9585	1228	9	3	2017-07-04 16:30:00
9586	1228	9	3	2018-12-20 19:45:00
9587	1228	9	3	2018-09-06 14:30:00
9588	1228	9	3	2019-05-10 12:45:00
9589	1228	9	3	2017-07-27 21:15:00
9590	1228	9	3	2018-03-19 22:00:00
9591	1229	15	9	2018-11-02 09:15:00
9592	1230	20	15	2020-08-01 09:00:00
9593	1230	20	15	2019-07-03 02:15:00
9594	1230	20	15	2021-01-10 05:30:00
9595	1230	20	15	2020-05-21 20:45:00
9596	1230	20	15	2020-10-28 04:30:00
9597	1231	12	14	2020-04-24 18:30:00
9598	1231	12	14	2020-01-07 20:45:00
9599	1231	12	14	2020-02-04 21:15:00
9600	1232	16	8	2018-04-29 16:30:00
9601	1232	16	8	2017-06-21 19:00:00
9602	1232	16	8	2017-07-25 18:15:00
9603	1232	16	8	2017-03-28 22:45:00
9604	1232	16	8	2017-10-18 11:15:00
9605	1233	2	9	2019-01-04 01:30:00
9606	1233	2	9	2018-10-26 19:30:00
9607	1233	2	9	2018-05-27 10:15:00
9608	1233	2	9	2018-12-28 09:15:00
9609	1233	2	9	2019-08-23 10:45:00
9610	1233	2	9	2019-07-02 18:15:00
9611	1233	2	9	2017-10-17 23:15:00
9612	1233	2	9	2018-06-03 10:00:00
9613	1233	2	9	2018-07-29 06:00:00
9614	1233	2	9	2017-09-07 11:15:00
9615	1233	2	9	2018-04-05 15:30:00
9616	1233	2	9	2019-06-19 01:45:00
9617	1233	2	9	2019-05-09 02:45:00
9618	1234	18	10	2021-04-12 18:30:00
9619	1234	18	10	2020-03-23 00:00:00
9620	1234	18	10	2020-06-06 15:45:00
9621	1234	18	10	2020-12-23 06:15:00
9622	1234	18	10	2021-04-06 08:00:00
9623	1234	18	10	2021-05-17 18:00:00
9624	1234	18	10	2021-03-06 19:15:00
9625	1234	18	10	2019-11-20 14:30:00
9626	1234	18	10	2020-12-18 23:30:00
9627	1234	18	10	2019-06-23 20:15:00
9628	1234	18	10	2020-05-22 15:15:00
9629	1234	18	10	2021-03-13 00:00:00
9630	1234	18	10	2021-01-12 18:15:00
9631	1235	15	4	2019-09-03 15:30:00
9632	1235	15	4	2019-10-14 14:45:00
9633	1235	15	4	2019-01-28 10:45:00
9634	1235	15	4	2019-02-11 02:45:00
9635	1235	15	4	2020-01-03 06:30:00
9636	1235	15	4	2018-10-20 11:15:00
9637	1235	15	4	2019-07-25 21:45:00
9638	1235	15	4	2019-08-16 06:15:00
9639	1235	15	4	2018-08-23 12:30:00
9640	1235	15	4	2019-06-06 14:00:00
9641	1236	11	6	2020-08-29 10:15:00
9642	1236	11	6	2019-11-17 12:15:00
9643	1236	11	6	2019-06-30 04:15:00
9644	1236	11	6	2020-02-06 17:15:00
9645	1236	11	6	2019-08-18 13:15:00
9646	1236	11	6	2020-08-08 05:00:00
9647	1236	11	6	2018-12-18 08:30:00
9648	1236	11	6	2018-12-01 22:00:00
9649	1236	11	6	2019-10-11 12:30:00
9650	1236	11	6	2019-03-06 12:15:00
9651	1236	11	6	2019-11-26 02:30:00
9652	1236	11	6	2019-07-28 04:00:00
9653	1236	11	6	2019-05-29 13:15:00
9654	1237	6	9	2020-12-26 23:45:00
9655	1237	6	9	2019-01-14 10:30:00
9656	1237	6	9	2019-05-17 11:45:00
9657	1237	6	9	2020-09-09 00:15:00
9658	1238	16	7	2020-06-02 02:30:00
9659	1238	16	7	2020-07-08 05:15:00
9660	1238	16	7	2021-05-26 07:45:00
9661	1238	16	7	2021-08-27 06:00:00
9662	1238	16	7	2021-01-27 13:00:00
9663	1239	20	14	2020-07-16 11:15:00
9664	1239	20	14	2020-09-11 02:15:00
9665	1239	20	14	2019-09-01 02:15:00
9666	1239	20	14	2020-02-15 12:30:00
9667	1240	3	9	2018-11-17 12:00:00
9668	1240	3	9	2019-04-10 00:30:00
9669	1240	3	9	2018-06-20 22:45:00
9670	1240	3	9	2017-11-23 02:30:00
9671	1240	3	9	2018-04-27 19:00:00
9672	1240	3	9	2019-01-15 09:30:00
9673	1240	3	9	2019-01-06 13:30:00
9674	1241	3	16	2020-01-01 20:45:00
9675	1242	1	17	2018-12-25 00:30:00
9676	1242	1	17	2020-02-18 09:00:00
9677	1243	10	19	2019-07-10 19:30:00
9678	1243	10	19	2019-09-18 03:00:00
9679	1244	10	11	2020-04-08 01:30:00
9680	1244	10	11	2020-12-01 23:45:00
9681	1244	10	11	2020-11-04 15:45:00
9682	1244	10	11	2021-01-08 14:30:00
9683	1244	10	11	2020-12-06 09:45:00
9684	1244	10	11	2019-12-18 17:45:00
9685	1244	10	11	2020-02-03 11:30:00
9686	1244	10	11	2021-05-27 02:00:00
9687	1244	10	11	2020-04-17 01:15:00
9688	1244	10	11	2020-09-11 16:45:00
9689	1244	10	11	2020-06-28 11:15:00
9690	1244	10	11	2019-12-11 20:45:00
9691	1244	10	11	2019-11-11 14:00:00
9692	1244	10	11	2020-01-08 07:30:00
9693	1244	10	11	2020-08-01 08:15:00
9694	1245	10	15	2019-10-17 04:15:00
9695	1245	10	15	2019-06-11 13:45:00
9696	1245	10	15	2018-11-09 15:45:00
9697	1245	10	15	2018-03-08 05:45:00
9698	1245	10	15	2020-01-09 22:15:00
9699	1245	10	15	2019-09-14 12:30:00
9700	1245	10	15	2019-01-16 23:15:00
9701	1246	1	10	2020-10-30 20:30:00
9702	1247	17	20	2020-04-27 22:30:00
9703	1247	17	20	2019-08-27 17:45:00
9704	1247	17	20	2019-12-20 02:15:00
9705	1247	17	20	2020-04-13 21:00:00
9706	1247	17	20	2020-04-25 22:00:00
9707	1247	17	20	2021-03-28 19:30:00
9708	1247	17	20	2021-03-17 06:45:00
9709	1247	17	20	2021-05-11 06:45:00
9710	1247	17	20	2020-02-11 12:00:00
9711	1247	17	20	2019-09-12 13:00:00
9712	1247	17	20	2021-01-01 14:00:00
9713	1247	17	20	2019-10-05 13:30:00
9714	1248	4	5	2019-04-07 11:15:00
9715	1248	4	5	2020-10-09 16:30:00
9716	1248	4	5	2018-12-16 03:00:00
9717	1249	16	8	2020-12-02 12:30:00
9718	1249	16	8	2020-08-08 17:45:00
9719	1249	16	8	2020-05-17 01:45:00
9720	1249	16	8	2019-08-20 02:00:00
9721	1249	16	8	2021-04-22 07:15:00
9722	1249	16	8	2019-11-10 15:00:00
9723	1249	16	8	2020-02-13 04:15:00
9724	1250	18	12	2018-02-19 20:00:00
9725	1251	3	19	2021-05-17 14:30:00
9726	1251	3	19	2019-09-13 01:45:00
9727	1251	3	19	2020-09-04 04:00:00
9728	1251	3	19	2019-12-04 11:15:00
9729	1251	3	19	2019-12-13 19:45:00
9730	1251	3	19	2020-05-30 12:30:00
9731	1251	3	19	2020-12-22 02:15:00
9732	1251	3	19	2020-07-15 14:15:00
9733	1252	18	16	2020-12-30 23:30:00
9734	1252	18	16	2020-10-02 17:45:00
9735	1253	16	6	2017-06-13 14:30:00
9736	1253	16	6	2018-01-10 06:15:00
9737	1253	16	6	2018-04-17 18:45:00
9738	1253	16	6	2019-03-07 21:30:00
9739	1253	16	6	2019-02-22 18:45:00
9740	1253	16	6	2017-06-23 01:15:00
9741	1253	16	6	2019-01-22 20:15:00
9742	1253	16	6	2018-03-24 10:45:00
9743	1253	16	6	2017-12-14 18:45:00
9744	1253	16	6	2018-12-26 04:00:00
9745	1253	16	6	2018-11-30 19:15:00
9746	1254	18	18	2020-05-03 07:30:00
9747	1254	18	18	2020-05-19 21:45:00
9748	1254	18	18	2021-06-09 15:00:00
9749	1254	18	18	2020-06-06 05:00:00
9750	1254	18	18	2021-02-09 04:45:00
9751	1254	18	18	2021-10-26 09:15:00
9752	1254	18	18	2021-09-24 20:30:00
9753	1254	18	18	2020-03-11 03:00:00
9754	1254	18	18	2020-08-28 19:15:00
9755	1254	18	18	2021-07-21 16:30:00
9756	1254	18	18	2020-10-26 12:45:00
9757	1254	18	18	2021-05-18 04:30:00
9758	1255	9	6	2020-07-25 08:45:00
9759	1255	9	6	2020-09-13 18:00:00
9760	1255	9	6	2019-09-05 22:30:00
9761	1255	9	6	2020-04-04 02:00:00
9762	1255	9	6	2020-10-10 12:30:00
9763	1255	9	6	2019-04-22 18:30:00
9764	1255	9	6	2020-08-26 17:15:00
9765	1255	9	6	2020-05-16 18:30:00
9766	1255	9	6	2020-01-28 17:30:00
9767	1255	9	6	2020-06-02 18:45:00
9768	1255	9	6	2019-01-23 01:00:00
9769	1255	9	6	2020-03-06 09:15:00
9770	1255	9	6	2020-07-22 09:15:00
9771	1256	19	14	2018-04-06 19:15:00
9772	1256	19	14	2017-10-21 02:15:00
9773	1256	19	14	2018-01-14 15:30:00
9774	1256	19	14	2019-06-15 22:00:00
9775	1256	19	14	2019-03-01 11:45:00
9776	1256	19	14	2018-05-12 16:45:00
9777	1257	17	18	2018-03-13 15:15:00
9778	1257	17	18	2019-06-11 08:15:00
9779	1257	17	18	2018-06-17 21:45:00
9780	1257	17	18	2019-01-24 16:15:00
9781	1257	17	18	2019-10-07 01:15:00
9782	1257	17	18	2018-06-03 13:00:00
9783	1257	17	18	2019-07-27 08:15:00
9784	1257	17	18	2018-06-09 04:00:00
9785	1257	17	18	2018-02-09 06:00:00
9786	1257	17	18	2019-01-29 02:45:00
9787	1257	17	18	2017-12-20 21:45:00
9788	1257	17	18	2018-06-09 21:45:00
9789	1257	17	18	2018-11-04 02:00:00
9790	1257	17	18	2018-10-28 18:30:00
9791	1257	17	18	2019-06-18 04:45:00
9792	1258	8	18	2020-06-22 08:30:00
9793	1259	3	15	2020-06-15 19:15:00
9794	1259	3	15	2019-05-21 02:30:00
9795	1259	3	15	2019-01-19 07:30:00
9796	1259	3	15	2019-02-01 12:30:00
9797	1259	3	15	2020-12-29 02:00:00
9798	1260	19	20	2017-08-21 02:00:00
9799	1260	19	20	2018-09-21 02:30:00
9800	1260	19	20	2017-11-22 04:00:00
9801	1261	13	4	2018-07-29 06:00:00
9802	1261	13	4	2019-02-18 01:15:00
9803	1261	13	4	2019-02-23 16:30:00
9804	1261	13	4	2018-10-10 16:30:00
9805	1261	13	4	2017-04-02 15:00:00
9806	1261	13	4	2018-10-22 13:15:00
9807	1261	13	4	2018-09-09 10:15:00
9808	1261	13	4	2017-07-16 12:15:00
9809	1261	13	4	2018-06-19 00:30:00
9810	1261	13	4	2019-02-05 23:00:00
9811	1261	13	4	2017-08-21 13:45:00
9812	1261	13	4	2019-01-27 22:30:00
9813	1261	13	4	2018-03-03 20:30:00
9814	1261	13	4	2018-12-18 17:15:00
9815	1261	13	4	2018-11-09 18:45:00
9816	1262	9	3	2019-01-24 13:45:00
9817	1262	9	3	2019-02-26 08:30:00
9818	1262	9	3	2018-08-12 03:00:00
9819	1262	9	3	2019-09-25 13:45:00
9820	1262	9	3	2019-06-11 02:00:00
9821	1262	9	3	2019-09-03 22:30:00
9822	1262	9	3	2019-04-23 23:00:00
9823	1262	9	3	2018-01-19 08:45:00
9824	1262	9	3	2018-02-04 22:30:00
9825	1262	9	3	2017-10-07 03:15:00
9826	1263	13	4	2017-12-28 04:45:00
9827	1263	13	4	2018-08-05 19:00:00
9828	1263	13	4	2018-03-11 12:00:00
9829	1264	2	6	2017-09-06 20:30:00
9830	1264	2	6	2018-11-27 04:00:00
9831	1264	2	6	2017-05-22 20:45:00
9832	1264	2	6	2018-12-24 19:30:00
9833	1265	20	7	2018-06-01 16:30:00
9834	1265	20	7	2019-10-18 06:30:00
9835	1265	20	7	2019-11-30 17:30:00
9836	1265	20	7	2018-12-17 18:15:00
9837	1265	20	7	2018-11-11 12:30:00
9838	1265	20	7	2019-10-28 05:45:00
9839	1265	20	7	2018-05-18 08:00:00
9840	1265	20	7	2019-04-19 16:00:00
9841	1265	20	7	2018-08-21 19:15:00
9842	1265	20	7	2018-06-29 08:15:00
9843	1265	20	7	2018-07-29 02:30:00
9844	1265	20	7	2018-08-08 10:45:00
9845	1265	20	7	2018-06-08 03:45:00
9846	1265	20	7	2019-01-14 00:45:00
9847	1265	20	7	2019-08-06 09:00:00
9848	1266	11	14	2019-03-12 05:00:00
9849	1266	11	14	2019-06-28 00:30:00
9850	1266	11	14	2019-02-08 18:15:00
9851	1266	11	14	2020-05-01 11:30:00
9852	1266	11	14	2020-01-16 01:45:00
9853	1266	11	14	2020-07-17 17:00:00
9854	1266	11	14	2019-03-03 01:00:00
9855	1266	11	14	2019-07-05 07:00:00
9856	1267	13	10	2020-07-27 10:30:00
9857	1267	13	10	2020-05-27 23:00:00
9858	1267	13	10	2019-07-08 09:15:00
9859	1267	13	10	2020-04-12 01:00:00
9860	1267	13	10	2021-01-20 23:45:00
9861	1267	13	10	2019-09-09 01:45:00
9862	1267	13	10	2021-01-17 09:30:00
9863	1267	13	10	2020-06-05 02:15:00
9864	1267	13	10	2021-03-24 18:15:00
9865	1267	13	10	2021-02-09 14:45:00
9866	1268	20	18	2017-07-07 15:15:00
9867	1268	20	18	2018-11-23 01:45:00
9868	1268	20	18	2019-02-08 10:45:00
9869	1268	20	18	2018-03-14 21:45:00
9870	1268	20	18	2017-09-19 02:45:00
9871	1268	20	18	2018-04-22 19:15:00
9872	1268	20	18	2019-02-03 14:30:00
9873	1268	20	18	2018-05-12 02:00:00
9874	1268	20	18	2018-10-29 16:00:00
9875	1268	20	18	2018-09-21 01:45:00
9876	1268	20	18	2018-08-12 06:00:00
9877	1268	20	18	2018-02-11 05:00:00
9878	1268	20	18	2018-11-17 23:45:00
9879	1268	20	18	2018-06-17 15:30:00
9880	1268	20	18	2018-12-03 19:00:00
9881	1269	2	11	2019-07-18 00:30:00
9882	1269	2	11	2018-07-28 15:30:00
9883	1269	2	11	2019-06-11 10:15:00
9884	1270	2	12	2019-08-13 01:00:00
9885	1270	2	12	2020-09-25 13:15:00
9886	1271	17	1	2018-05-11 16:00:00
9887	1271	17	1	2019-04-22 21:45:00
9888	1271	17	1	2018-08-27 17:45:00
9889	1271	17	1	2018-05-23 10:30:00
9890	1271	17	1	2018-07-13 11:30:00
9891	1271	17	1	2017-07-13 17:00:00
9892	1271	17	1	2018-06-06 12:45:00
9893	1272	18	4	2020-11-13 13:30:00
9894	1272	18	4	2021-03-01 04:15:00
9895	1272	18	4	2020-06-16 14:00:00
9896	1272	18	4	2021-05-19 06:45:00
9897	1272	18	4	2020-12-16 06:15:00
9898	1272	18	4	2020-03-04 09:15:00
9899	1272	18	4	2021-02-21 22:00:00
9900	1272	18	4	2020-06-24 15:15:00
9901	1272	18	4	2019-11-08 01:30:00
9902	1272	18	4	2019-12-23 12:15:00
9903	1272	18	4	2020-02-25 22:30:00
9904	1272	18	4	2021-01-22 10:45:00
9905	1272	18	4	2019-12-08 14:15:00
9906	1272	18	4	2021-07-08 07:15:00
9907	1273	10	10	2018-04-26 14:30:00
9908	1274	11	6	2019-06-19 22:45:00
9909	1274	11	6	2019-09-16 19:00:00
9910	1274	11	6	2018-07-26 16:30:00
9911	1274	11	6	2019-01-30 21:00:00
9912	1274	11	6	2017-12-19 02:30:00
9913	1274	11	6	2019-04-02 03:45:00
9914	1274	11	6	2018-12-13 09:30:00
9915	1274	11	6	2018-11-27 01:30:00
9916	1274	11	6	2018-04-24 09:15:00
9917	1274	11	6	2019-06-27 05:15:00
9918	1275	11	15	2020-09-18 15:00:00
9919	1275	11	15	2020-02-06 01:15:00
9920	1275	11	15	2020-10-28 14:15:00
9921	1275	11	15	2019-09-03 07:45:00
9922	1275	11	15	2021-07-02 15:00:00
9923	1275	11	15	2020-04-29 01:15:00
9924	1275	11	15	2021-07-17 14:00:00
9925	1275	11	15	2020-01-26 01:15:00
9926	1276	20	11	2021-03-12 22:30:00
9927	1276	20	11	2020-12-21 09:30:00
9928	1276	20	11	2020-09-20 07:00:00
9929	1277	2	6	2017-05-26 22:45:00
9930	1277	2	6	2017-09-07 10:30:00
9931	1277	2	6	2018-09-19 13:30:00
9932	1277	2	6	2017-04-07 05:30:00
9933	1277	2	6	2017-09-20 19:30:00
9934	1277	2	6	2017-12-19 07:00:00
9935	1277	2	6	2017-07-26 17:00:00
9936	1277	2	6	2017-05-06 14:30:00
9937	1277	2	6	2018-12-17 21:00:00
9938	1277	2	6	2018-08-05 07:15:00
9939	1277	2	6	2018-01-26 19:15:00
9940	1277	2	6	2017-06-04 01:15:00
9941	1277	2	6	2017-07-10 15:45:00
9942	1277	2	6	2018-08-26 00:15:00
9943	1277	2	6	2018-12-20 12:15:00
9944	1278	9	6	2017-11-07 15:15:00
9945	1278	9	6	2019-01-12 16:45:00
9946	1278	9	6	2018-04-27 02:00:00
9947	1278	9	6	2018-01-15 09:45:00
9948	1278	9	6	2019-05-13 23:45:00
9949	1278	9	6	2019-03-06 03:00:00
9950	1278	9	6	2019-01-05 14:30:00
9951	1278	9	6	2018-04-07 06:00:00
9952	1278	9	6	2019-05-11 22:45:00
9953	1278	9	6	2018-09-27 03:15:00
9954	1278	9	6	2017-11-10 01:00:00
9955	1278	9	6	2019-05-02 02:30:00
9956	1278	9	6	2018-06-03 13:15:00
9957	1278	9	6	2017-06-03 05:00:00
9958	1279	12	20	2019-08-29 00:30:00
9959	1279	12	20	2019-05-13 05:00:00
9960	1279	12	20	2019-02-20 11:00:00
9961	1279	12	20	2020-04-12 10:15:00
9962	1279	12	20	2019-10-27 07:30:00
9963	1279	12	20	2018-10-20 05:30:00
9964	1279	12	20	2020-01-02 04:15:00
9965	1279	12	20	2018-08-23 14:00:00
9966	1279	12	20	2019-12-25 17:15:00
9967	1279	12	20	2019-10-05 18:30:00
9968	1279	12	20	2019-05-09 01:15:00
9969	1279	12	20	2019-09-26 15:45:00
9970	1279	12	20	2018-12-09 16:00:00
9971	1280	14	14	2018-08-03 04:00:00
9972	1280	14	14	2018-11-12 12:30:00
9973	1280	14	14	2019-05-04 17:15:00
9974	1280	14	14	2018-04-21 21:15:00
9975	1280	14	14	2018-01-01 06:15:00
9976	1280	14	14	2018-03-04 19:30:00
9977	1280	14	14	2017-10-17 00:30:00
9978	1280	14	14	2017-11-01 22:15:00
9979	1280	14	14	2018-10-04 12:30:00
9980	1280	14	14	2019-03-05 09:15:00
9981	1280	14	14	2017-07-04 07:45:00
9982	1280	14	14	2019-02-26 19:30:00
9983	1280	14	14	2019-04-08 19:00:00
9984	1280	14	14	2019-04-03 13:45:00
9985	1280	14	14	2017-08-06 07:15:00
9986	1281	13	11	2020-11-24 06:00:00
9987	1281	13	11	2020-04-11 22:00:00
9988	1281	13	11	2020-07-27 03:00:00
9989	1281	13	11	2019-08-03 10:00:00
9990	1281	13	11	2020-09-16 10:15:00
9991	1281	13	11	2019-02-02 06:30:00
9992	1281	13	11	2019-01-27 00:45:00
9993	1281	13	11	2019-01-06 11:15:00
9994	1281	13	11	2020-03-20 23:15:00
9995	1282	15	3	2019-09-02 18:00:00
9996	1282	15	3	2019-01-14 02:30:00
9997	1282	15	3	2019-01-23 22:15:00
9998	1282	15	3	2018-12-12 04:15:00
9999	1282	15	3	2019-06-05 04:45:00
10000	1282	15	3	2020-05-08 04:00:00
10001	1282	15	3	2020-01-09 15:45:00
10002	1282	15	3	2019-12-03 11:30:00
10003	1282	15	3	2020-02-27 15:45:00
10004	1282	15	3	2020-05-13 16:15:00
10005	1282	15	3	2018-12-15 10:00:00
10006	1282	15	3	2019-04-12 23:30:00
10007	1282	15	3	2020-01-20 02:30:00
10008	1283	9	14	2020-03-06 16:15:00
10009	1283	9	14	2019-06-29 14:15:00
10010	1283	9	14	2020-05-22 04:45:00
10011	1283	9	14	2020-01-02 07:15:00
10012	1283	9	14	2019-10-22 19:00:00
10013	1284	1	6	2020-12-16 00:15:00
10014	1284	1	6	2020-05-14 06:45:00
10015	1284	1	6	2021-01-21 11:00:00
10016	1284	1	6	2019-08-10 21:15:00
10017	1284	1	6	2020-04-03 03:45:00
10018	1285	20	4	2021-05-17 10:45:00
10019	1285	20	4	2021-06-29 02:00:00
10020	1285	20	4	2020-10-14 10:15:00
10021	1285	20	4	2020-04-17 16:00:00
10022	1285	20	4	2020-02-22 16:00:00
10023	1285	20	4	2021-07-25 09:30:00
10024	1285	20	4	2021-06-27 02:00:00
10025	1285	20	4	2021-04-10 20:00:00
10026	1285	20	4	2021-06-18 19:30:00
10027	1285	20	4	2020-07-07 18:15:00
10028	1285	20	4	2020-11-18 15:00:00
10029	1285	20	4	2021-10-29 09:00:00
10030	1285	20	4	2021-09-06 01:30:00
10031	1286	8	18	2017-07-23 08:00:00
10032	1286	8	18	2018-12-10 16:00:00
10033	1286	8	18	2017-09-14 17:15:00
10034	1286	8	18	2017-11-22 19:00:00
10035	1286	8	18	2017-10-26 17:30:00
10036	1286	8	18	2018-05-12 23:30:00
10037	1286	8	18	2019-04-26 22:45:00
10038	1287	3	6	2018-07-12 15:30:00
10039	1287	3	6	2019-11-22 08:15:00
10040	1287	3	6	2018-08-21 04:45:00
10041	1287	3	6	2019-09-11 04:45:00
10042	1287	3	6	2018-08-22 13:15:00
10043	1287	3	6	2019-01-19 08:45:00
10044	1287	3	6	2018-11-22 07:30:00
10045	1287	3	6	2019-07-05 06:15:00
10046	1287	3	6	2019-07-02 13:15:00
10047	1287	3	6	2019-04-14 17:30:00
10048	1287	3	6	2018-11-19 18:30:00
10049	1287	3	6	2020-01-19 00:45:00
10050	1288	10	4	2018-07-06 15:45:00
10051	1288	10	4	2018-08-18 19:30:00
10052	1288	10	4	2017-10-20 05:30:00
10053	1288	10	4	2018-10-11 07:30:00
10054	1288	10	4	2018-11-19 20:45:00
10055	1288	10	4	2018-03-06 12:00:00
10056	1288	10	4	2018-01-29 00:15:00
10057	1288	10	4	2017-09-11 20:15:00
10058	1288	10	4	2018-10-12 07:45:00
10059	1288	10	4	2018-04-25 03:00:00
10060	1288	10	4	2019-04-03 02:30:00
10061	1288	10	4	2018-06-14 18:00:00
10062	1288	10	4	2018-03-18 14:30:00
10063	1288	10	4	2017-09-03 11:00:00
10064	1288	10	4	2019-04-25 12:30:00
10065	1289	6	3	2019-07-25 01:00:00
10066	1289	6	3	2019-08-15 18:00:00
10067	1289	6	3	2019-10-28 09:45:00
10068	1289	6	3	2019-03-08 17:30:00
10069	1289	6	3	2018-12-06 19:30:00
10070	1290	2	13	2020-09-06 11:30:00
10071	1290	2	13	2021-12-20 22:00:00
10072	1290	2	13	2020-08-22 12:00:00
10073	1290	2	13	2020-02-11 08:45:00
10074	1290	2	13	2021-07-28 07:00:00
10075	1290	2	13	2021-07-18 04:00:00
10076	1290	2	13	2021-12-11 17:15:00
10077	1290	2	13	2021-03-25 19:30:00
10078	1290	2	13	2020-04-24 00:45:00
10079	1290	2	13	2020-03-04 07:00:00
10080	1290	2	13	2020-12-03 00:30:00
10081	1290	2	13	2021-07-03 06:00:00
10082	1290	2	13	2021-01-14 19:45:00
10083	1290	2	13	2020-02-26 13:00:00
10084	1290	2	13	2021-11-12 04:30:00
10085	1291	2	9	2021-01-22 18:00:00
10086	1292	16	1	2019-04-13 08:00:00
10087	1292	16	1	2019-10-17 20:30:00
10088	1292	16	1	2020-09-22 09:15:00
10089	1292	16	1	2021-02-06 05:15:00
10090	1292	16	1	2019-05-29 08:30:00
10091	1292	16	1	2020-11-29 08:00:00
10092	1292	16	1	2020-08-02 19:45:00
10093	1292	16	1	2019-05-13 17:00:00
10094	1292	16	1	2019-10-23 05:45:00
10095	1292	16	1	2019-06-06 15:30:00
10096	1292	16	1	2020-08-02 10:30:00
10097	1292	16	1	2021-01-14 09:15:00
10098	1292	16	1	2019-05-04 01:15:00
10099	1292	16	1	2019-11-27 23:30:00
10100	1293	16	14	2019-04-17 07:30:00
10101	1293	16	14	2018-12-04 22:30:00
10102	1293	16	14	2019-04-03 13:45:00
10103	1293	16	14	2017-06-29 21:30:00
10104	1293	16	14	2017-10-02 01:00:00
10105	1293	16	14	2018-06-24 02:00:00
10106	1293	16	14	2018-01-05 01:15:00
10107	1293	16	14	2017-08-19 18:00:00
10108	1293	16	14	2018-06-08 13:30:00
10109	1293	16	14	2017-10-11 12:30:00
10110	1293	16	14	2017-10-22 03:15:00
10111	1294	13	18	2018-03-30 20:15:00
10112	1295	7	19	2018-07-16 03:45:00
10113	1295	7	19	2019-01-21 12:00:00
10114	1295	7	19	2019-06-26 05:00:00
10115	1295	7	19	2018-07-08 06:00:00
10116	1295	7	19	2019-03-13 14:15:00
10117	1295	7	19	2018-05-10 15:00:00
10118	1296	4	6	2019-02-24 07:45:00
10119	1297	1	20	2020-07-19 17:30:00
10120	1297	1	20	2020-10-13 00:00:00
10121	1297	1	20	2021-10-18 07:45:00
10122	1297	1	20	2020-08-03 09:45:00
10123	1297	1	20	2021-06-05 02:15:00
10124	1297	1	20	2019-11-26 06:15:00
10125	1297	1	20	2020-07-27 03:15:00
10126	1297	1	20	2020-02-08 00:45:00
10127	1297	1	20	2021-06-08 07:15:00
10128	1297	1	20	2021-07-19 17:00:00
10129	1297	1	20	2020-10-03 23:30:00
10130	1297	1	20	2021-02-13 22:45:00
10131	1298	6	3	2019-02-13 07:15:00
10132	1298	6	3	2018-11-07 19:30:00
10133	1298	6	3	2019-09-28 09:00:00
10134	1298	6	3	2019-12-01 00:15:00
10135	1298	6	3	2019-04-11 04:15:00
10136	1298	6	3	2020-05-29 19:15:00
10137	1298	6	3	2020-04-17 21:45:00
10138	1298	6	3	2018-11-09 14:15:00
10139	1298	6	3	2020-06-22 01:45:00
10140	1299	11	9	2018-07-13 15:30:00
10141	1299	11	9	2019-10-06 01:00:00
10142	1299	11	9	2019-02-17 15:45:00
10143	1299	11	9	2019-10-10 21:30:00
10144	1299	11	9	2019-04-13 08:45:00
10145	1299	11	9	2018-10-18 00:30:00
10146	1300	4	20	2021-01-04 13:15:00
10147	1300	4	20	2020-02-27 20:45:00
10148	1300	4	20	2021-03-06 06:30:00
10149	1300	4	20	2019-09-19 10:45:00
10150	1300	4	20	2020-02-09 04:00:00
10151	1300	4	20	2020-11-10 13:00:00
10152	1300	4	20	2020-04-02 10:45:00
10153	1300	4	20	2020-04-05 09:15:00
10154	1300	4	20	2019-11-09 16:30:00
10155	1300	4	20	2020-11-28 01:45:00
10156	1301	10	13	2021-03-01 16:15:00
10157	1301	10	13	2021-08-19 23:00:00
10158	1301	10	13	2020-07-28 01:15:00
10159	1301	10	13	2021-09-12 15:30:00
10160	1301	10	13	2021-10-10 00:45:00
10161	1301	10	13	2020-01-16 05:30:00
10162	1301	10	13	2021-10-10 02:00:00
10163	1301	10	13	2020-06-06 07:30:00
10164	1301	10	13	2020-04-23 01:30:00
10165	1301	10	13	2021-12-01 18:00:00
10166	1301	10	13	2020-05-09 08:45:00
10167	1301	10	13	2020-09-14 04:00:00
10168	1301	10	13	2021-01-28 21:15:00
10169	1302	13	7	2019-12-12 09:00:00
10170	1302	13	7	2020-12-18 18:15:00
10171	1302	13	7	2019-07-28 04:45:00
10172	1302	13	7	2019-06-18 21:00:00
10173	1302	13	7	2019-12-20 22:45:00
10174	1302	13	7	2020-10-13 09:45:00
10175	1302	13	7	2019-09-27 15:45:00
10176	1302	13	7	2019-10-15 08:15:00
10177	1302	13	7	2020-08-24 09:45:00
10178	1302	13	7	2020-05-23 20:45:00
10179	1302	13	7	2019-08-30 01:15:00
10180	1302	13	7	2019-11-09 00:45:00
10181	1302	13	7	2020-02-09 16:15:00
10182	1302	13	7	2020-07-16 11:30:00
10183	1302	13	7	2019-11-02 13:00:00
10184	1303	9	20	2021-01-12 01:30:00
10185	1303	9	20	2020-06-17 08:45:00
10186	1303	9	20	2021-06-16 18:30:00
10187	1303	9	20	2021-08-09 05:15:00
10188	1304	14	9	2019-10-02 06:15:00
10189	1304	14	9	2019-02-17 17:30:00
10190	1304	14	9	2018-06-13 09:30:00
10191	1304	14	9	2020-02-25 20:00:00
10192	1304	14	9	2019-07-03 19:15:00
10193	1304	14	9	2020-01-18 03:45:00
10194	1304	14	9	2018-07-01 08:00:00
10195	1304	14	9	2019-06-14 19:45:00
10196	1304	14	9	2019-08-01 08:45:00
10197	1304	14	9	2018-12-07 04:45:00
10198	1304	14	9	2018-08-13 04:30:00
10199	1304	14	9	2018-05-06 08:00:00
10200	1305	19	14	2019-03-21 12:30:00
10201	1305	19	14	2018-12-19 21:00:00
10202	1305	19	14	2018-11-06 22:15:00
10203	1305	19	14	2020-06-09 09:45:00
10204	1305	19	14	2019-09-19 01:00:00
10205	1305	19	14	2020-04-30 23:30:00
10206	1305	19	14	2019-04-19 23:15:00
10207	1305	19	14	2018-11-07 07:30:00
10208	1305	19	14	2020-04-19 13:30:00
10209	1305	19	14	2019-05-12 14:15:00
10210	1305	19	14	2019-05-19 23:15:00
10211	1306	12	6	2017-11-01 18:00:00
10212	1306	12	6	2017-12-10 17:00:00
10213	1306	12	6	2018-06-11 11:15:00
10214	1306	12	6	2017-05-14 20:00:00
10215	1306	12	6	2018-01-05 12:30:00
10216	1306	12	6	2018-05-10 15:45:00
10217	1306	12	6	2018-04-21 06:45:00
10218	1306	12	6	2017-11-09 21:30:00
10219	1306	12	6	2017-07-15 17:45:00
10220	1306	12	6	2019-04-26 01:45:00
10221	1306	12	6	2019-02-06 17:15:00
10222	1307	12	9	2020-01-11 14:00:00
10223	1307	12	9	2021-07-12 18:45:00
10224	1307	12	9	2021-02-06 13:15:00
10225	1307	12	9	2021-06-16 22:30:00
10226	1307	12	9	2020-03-26 15:15:00
10227	1307	12	9	2021-03-09 18:45:00
10228	1307	12	9	2020-01-28 17:30:00
10229	1307	12	9	2020-08-02 09:00:00
10230	1307	12	9	2021-06-10 05:15:00
10231	1307	12	9	2020-12-13 23:30:00
10232	1307	12	9	2020-04-13 05:30:00
10233	1307	12	9	2020-08-13 18:45:00
10234	1307	12	9	2021-11-21 00:15:00
10235	1307	12	9	2021-01-09 22:30:00
10236	1307	12	9	2020-05-17 15:00:00
10237	1308	11	14	2019-01-26 00:00:00
10238	1308	11	14	2019-11-28 01:45:00
10239	1308	11	14	2019-03-06 00:00:00
10240	1308	11	14	2019-06-12 21:45:00
10241	1308	11	14	2019-10-17 07:15:00
10242	1308	11	14	2019-01-08 15:45:00
10243	1308	11	14	2020-06-08 19:00:00
10244	1308	11	14	2019-01-22 15:00:00
10245	1308	11	14	2020-07-01 08:30:00
10246	1308	11	14	2019-07-22 13:45:00
10247	1308	11	14	2020-02-09 15:45:00
10248	1308	11	14	2020-11-14 14:15:00
10249	1308	11	14	2020-07-05 21:15:00
10250	1309	10	10	2020-09-05 09:00:00
10251	1309	10	10	2019-07-24 06:30:00
10252	1309	10	10	2021-04-13 16:30:00
10253	1309	10	10	2020-05-08 17:30:00
10254	1309	10	10	2020-12-25 08:15:00
10255	1309	10	10	2020-07-28 18:15:00
10256	1310	8	8	2020-01-16 02:30:00
10257	1310	8	8	2020-10-02 02:30:00
10258	1310	8	8	2020-07-03 05:45:00
10259	1310	8	8	2020-03-15 01:15:00
10260	1310	8	8	2020-08-26 18:30:00
10261	1310	8	8	2020-04-18 15:45:00
10262	1311	2	18	2019-06-12 18:45:00
10263	1311	2	18	2018-01-07 08:45:00
10264	1311	2	18	2019-03-12 10:45:00
10265	1311	2	18	2018-03-11 17:30:00
10266	1311	2	18	2017-12-01 19:45:00
10267	1311	2	18	2019-03-24 17:15:00
10268	1311	2	18	2018-03-14 04:45:00
10269	1311	2	18	2019-03-18 13:45:00
10270	1311	2	18	2017-11-24 05:15:00
10271	1312	16	7	2019-12-30 22:30:00
10272	1312	16	7	2019-11-11 00:00:00
10273	1312	16	7	2019-05-25 21:00:00
10274	1312	16	7	2020-10-17 19:00:00
10275	1312	16	7	2019-04-26 12:00:00
10276	1312	16	7	2020-10-14 03:00:00
10277	1312	16	7	2019-10-27 01:15:00
10278	1312	16	7	2019-03-25 22:15:00
10279	1312	16	7	2019-06-16 07:00:00
10280	1312	16	7	2020-01-10 11:30:00
10281	1313	14	5	2017-11-09 06:45:00
10282	1313	14	5	2019-10-01 14:00:00
10283	1313	14	5	2017-12-17 04:15:00
10284	1314	17	11	2019-12-15 18:30:00
10285	1314	17	11	2020-12-07 01:45:00
10286	1314	17	11	2021-03-13 19:45:00
10287	1314	17	11	2020-03-04 04:45:00
10288	1314	17	11	2020-11-11 07:15:00
10289	1314	17	11	2020-07-28 19:00:00
10290	1314	17	11	2020-10-15 12:45:00
10291	1314	17	11	2020-11-04 01:45:00
10292	1314	17	11	2021-04-30 12:30:00
10293	1314	17	11	2019-12-08 09:45:00
10294	1314	17	11	2019-12-25 04:45:00
10295	1314	17	11	2019-12-12 14:30:00
10296	1314	17	11	2020-07-06 05:30:00
10297	1315	3	4	2017-11-09 02:00:00
10298	1315	3	4	2018-02-19 10:30:00
10299	1315	3	4	2018-07-16 09:45:00
10300	1316	17	3	2017-09-02 12:00:00
10301	1316	17	3	2017-09-18 19:30:00
10302	1316	17	3	2017-12-05 10:15:00
10303	1316	17	3	2018-06-01 04:15:00
10304	1316	17	3	2017-12-25 07:45:00
10305	1316	17	3	2019-03-17 14:00:00
10306	1317	20	12	2018-04-24 08:30:00
10307	1317	20	12	2018-08-07 04:00:00
10308	1317	20	12	2018-03-23 03:45:00
10309	1317	20	12	2018-11-30 11:15:00
10310	1317	20	12	2018-01-10 23:30:00
10311	1317	20	12	2018-11-03 08:15:00
10312	1317	20	12	2018-12-27 16:30:00
10313	1318	2	2	2018-11-22 18:00:00
10314	1318	2	2	2018-11-11 06:30:00
10315	1318	2	2	2020-02-04 14:15:00
10316	1318	2	2	2018-06-01 08:15:00
10317	1318	2	2	2018-09-02 05:00:00
10318	1318	2	2	2018-12-15 16:45:00
10319	1318	2	2	2019-12-30 00:00:00
10320	1318	2	2	2018-04-26 20:45:00
10321	1319	12	10	2018-05-08 17:00:00
10322	1319	12	10	2018-11-22 06:00:00
10323	1319	12	10	2018-11-10 07:00:00
10324	1319	12	10	2018-06-20 09:45:00
10325	1319	12	10	2018-01-24 15:30:00
10326	1319	12	10	2019-10-04 11:45:00
10327	1320	12	1	2018-10-01 22:15:00
10328	1320	12	1	2017-02-16 11:00:00
10329	1320	12	1	2017-05-10 16:30:00
10330	1320	12	1	2017-12-22 22:15:00
10331	1320	12	1	2018-09-23 05:45:00
10332	1320	12	1	2017-07-07 13:15:00
10333	1320	12	1	2018-05-18 00:15:00
10334	1320	12	1	2018-06-22 05:30:00
10335	1320	12	1	2017-04-23 16:00:00
10336	1320	12	1	2017-07-29 20:15:00
10337	1320	12	1	2017-09-25 01:45:00
10338	1320	12	1	2018-01-24 12:00:00
10339	1320	12	1	2017-08-19 23:30:00
10340	1320	12	1	2017-09-15 05:45:00
10341	1320	12	1	2017-11-16 05:15:00
10342	1321	19	2	2019-10-07 05:00:00
10343	1321	19	2	2021-07-20 13:45:00
10344	1321	19	2	2020-05-08 14:15:00
10345	1322	4	6	2019-02-20 08:15:00
10346	1322	4	6	2017-11-10 15:30:00
10347	1322	4	6	2017-10-07 07:00:00
10348	1323	6	10	2018-09-11 05:00:00
10349	1323	6	10	2018-05-04 06:00:00
10350	1323	6	10	2018-08-28 12:15:00
10351	1324	9	8	2018-12-23 02:15:00
10352	1324	9	8	2017-11-13 16:45:00
10353	1324	9	8	2019-10-04 06:15:00
10354	1324	9	8	2018-07-19 16:45:00
10355	1324	9	8	2018-03-17 04:15:00
10356	1325	15	16	2019-04-03 11:15:00
10357	1325	15	16	2020-04-24 16:45:00
10358	1325	15	16	2019-02-06 08:00:00
10359	1325	15	16	2018-11-23 03:00:00
10360	1325	15	16	2019-07-17 00:30:00
10361	1325	15	16	2020-01-04 01:45:00
10362	1325	15	16	2019-11-12 18:00:00
10363	1325	15	16	2019-02-03 15:00:00
10364	1325	15	16	2020-08-01 10:00:00
10365	1325	15	16	2019-04-06 05:45:00
10366	1325	15	16	2019-11-24 20:15:00
10367	1325	15	16	2019-06-15 10:45:00
10368	1325	15	16	2019-12-28 01:45:00
10369	1326	8	9	2019-06-30 20:45:00
10370	1326	8	9	2019-02-03 04:45:00
10371	1326	8	9	2018-06-30 09:45:00
10372	1326	8	9	2018-07-14 15:15:00
10373	1326	8	9	2019-06-16 18:00:00
10374	1326	8	9	2018-08-26 12:30:00
10375	1327	1	12	2017-03-23 03:45:00
10376	1327	1	12	2018-07-27 21:00:00
10377	1327	1	12	2018-03-09 20:00:00
10378	1327	1	12	2017-11-02 05:15:00
10379	1327	1	12	2018-02-27 21:45:00
10380	1327	1	12	2018-04-16 10:15:00
10381	1328	4	20	2018-02-10 17:00:00
10382	1328	4	20	2017-11-16 02:45:00
10383	1328	4	20	2018-04-05 06:45:00
10384	1328	4	20	2017-08-30 07:15:00
10385	1328	4	20	2019-01-06 05:30:00
10386	1328	4	20	2018-07-26 03:45:00
10387	1328	4	20	2017-10-28 02:45:00
10388	1328	4	20	2019-02-08 05:45:00
10389	1328	4	20	2017-05-02 14:00:00
10390	1328	4	20	2019-01-03 05:30:00
10391	1328	4	20	2018-03-02 12:45:00
10392	1328	4	20	2018-01-20 11:45:00
10393	1328	4	20	2018-04-15 15:00:00
10394	1329	12	1	2019-04-26 23:30:00
10395	1329	12	1	2019-05-22 03:30:00
10396	1330	4	17	2019-06-02 06:00:00
10397	1330	4	17	2019-04-05 04:00:00
10398	1330	4	17	2019-12-13 18:30:00
10399	1330	4	17	2019-05-14 03:00:00
10400	1330	4	17	2019-03-20 00:45:00
10401	1330	4	17	2019-02-25 15:15:00
10402	1331	10	13	2021-02-26 08:30:00
10403	1331	10	13	2020-07-04 14:15:00
10404	1331	10	13	2020-10-30 22:30:00
10405	1331	10	13	2019-12-17 15:15:00
10406	1331	10	13	2021-02-26 18:30:00
10407	1331	10	13	2019-12-13 00:00:00
10408	1331	10	13	2021-02-05 04:15:00
10409	1331	10	13	2021-06-02 14:30:00
10410	1331	10	13	2020-03-15 20:00:00
10411	1331	10	13	2021-03-20 20:00:00
10412	1331	10	13	2020-02-02 20:45:00
10413	1331	10	13	2019-11-15 21:45:00
10414	1332	12	7	2020-08-27 03:30:00
10415	1332	12	7	2019-03-05 05:15:00
10416	1332	12	7	2020-04-11 09:00:00
10417	1332	12	7	2020-02-12 22:30:00
10418	1332	12	7	2019-09-13 15:00:00
10419	1332	12	7	2020-01-06 20:30:00
10420	1332	12	7	2020-02-11 12:30:00
10421	1332	12	7	2020-03-07 19:45:00
10422	1332	12	7	2019-01-10 14:45:00
10423	1332	12	7	2020-07-13 15:30:00
10424	1332	12	7	2020-07-02 04:45:00
10425	1332	12	7	2020-02-03 20:00:00
10426	1332	12	7	2019-01-01 17:45:00
10427	1332	12	7	2020-01-10 16:30:00
10428	1333	5	8	2018-10-29 05:15:00
10429	1333	5	8	2017-05-12 07:00:00
10430	1334	13	1	2017-11-15 00:00:00
10431	1334	13	1	2018-03-09 08:15:00
10432	1334	13	1	2019-01-27 09:00:00
10433	1334	13	1	2017-11-30 21:15:00
10434	1335	7	16	2019-05-15 09:45:00
10435	1335	7	16	2018-11-08 20:30:00
10436	1335	7	16	2020-08-20 14:15:00
10437	1335	7	16	2019-02-08 14:45:00
10438	1336	6	15	2020-03-29 05:15:00
10439	1336	6	15	2020-02-04 14:15:00
10440	1336	6	15	2020-06-09 15:15:00
10441	1336	6	15	2020-05-19 05:45:00
10442	1337	17	1	2020-06-05 14:15:00
10443	1337	17	1	2020-05-06 06:15:00
10444	1337	17	1	2020-07-26 07:00:00
10445	1337	17	1	2020-01-01 11:45:00
10446	1337	17	1	2019-07-28 06:00:00
10447	1337	17	1	2019-01-02 13:15:00
10448	1338	3	13	2020-07-14 20:15:00
10449	1338	3	13	2019-08-03 19:30:00
10450	1339	6	19	2019-11-26 21:30:00
10451	1339	6	19	2021-09-11 02:15:00
10452	1339	6	19	2021-04-23 08:45:00
10453	1340	7	3	2020-04-15 07:45:00
10454	1340	7	3	2020-03-09 23:00:00
10455	1340	7	3	2020-01-13 21:30:00
10456	1340	7	3	2020-10-02 06:45:00
10457	1340	7	3	2020-02-21 01:00:00
10458	1340	7	3	2019-09-14 14:30:00
10459	1340	7	3	2019-08-01 02:00:00
10460	1340	7	3	2019-06-04 18:15:00
10461	1340	7	3	2020-02-03 22:15:00
10462	1340	7	3	2019-06-10 14:30:00
10463	1340	7	3	2019-09-18 11:00:00
10464	1341	9	5	2018-04-25 17:00:00
10465	1341	9	5	2018-11-22 07:00:00
10466	1341	9	5	2017-12-26 00:30:00
10467	1341	9	5	2019-07-26 14:45:00
10468	1341	9	5	2017-10-28 10:45:00
10469	1341	9	5	2019-07-25 04:45:00
10470	1341	9	5	2018-05-01 14:30:00
10471	1341	9	5	2019-03-09 09:15:00
10472	1341	9	5	2019-04-28 20:30:00
10473	1341	9	5	2019-04-15 09:30:00
10474	1341	9	5	2019-02-05 03:00:00
10475	1341	9	5	2018-01-24 06:30:00
10476	1341	9	5	2018-02-24 02:45:00
10477	1341	9	5	2018-08-19 21:00:00
10478	1342	5	17	2020-01-04 11:15:00
10479	1342	5	17	2019-08-23 13:15:00
10480	1342	5	17	2018-04-10 00:30:00
10481	1343	18	10	2018-03-11 14:30:00
10482	1343	18	10	2018-05-05 08:45:00
10483	1343	18	10	2018-09-12 12:00:00
10484	1343	18	10	2018-12-27 12:15:00
10485	1343	18	10	2018-09-25 17:15:00
10486	1343	18	10	2019-06-30 09:30:00
10487	1344	6	17	2018-07-07 06:45:00
10488	1344	6	17	2020-02-18 14:00:00
10489	1344	6	17	2019-04-18 13:15:00
10490	1344	6	17	2020-01-08 05:15:00
10491	1344	6	17	2019-02-02 21:15:00
10492	1344	6	17	2019-12-02 14:15:00
10493	1345	8	18	2019-08-15 15:30:00
10494	1345	8	18	2018-09-13 00:15:00
10495	1345	8	18	2019-11-19 20:00:00
10496	1345	8	18	2019-02-05 18:15:00
10497	1345	8	18	2018-11-18 06:30:00
10498	1345	8	18	2018-08-25 02:45:00
10499	1345	8	18	2018-11-28 08:45:00
10500	1345	8	18	2019-04-27 19:30:00
10501	1345	8	18	2018-10-07 07:45:00
10502	1345	8	18	2018-06-12 07:00:00
10503	1345	8	18	2019-05-18 21:15:00
10504	1345	8	18	2019-09-01 16:15:00
10505	1345	8	18	2018-11-11 02:30:00
10506	1345	8	18	2019-09-26 07:00:00
10507	1346	2	10	2018-01-06 17:00:00
10508	1346	2	10	2018-11-12 01:30:00
10509	1346	2	10	2018-12-26 22:00:00
10510	1346	2	10	2018-03-26 14:00:00
10511	1346	2	10	2018-11-23 08:45:00
10512	1346	2	10	2019-03-27 00:00:00
10513	1346	2	10	2019-05-06 22:00:00
10514	1346	2	10	2017-11-16 16:30:00
10515	1346	2	10	2019-04-23 10:15:00
10516	1346	2	10	2018-02-26 22:15:00
10517	1346	2	10	2017-09-20 09:15:00
10518	1346	2	10	2018-03-04 16:45:00
10519	1347	20	8	2019-10-24 10:30:00
10520	1347	20	8	2020-08-17 04:00:00
10521	1347	20	8	2020-10-03 08:45:00
10522	1348	10	2	2017-11-25 03:45:00
10523	1348	10	2	2017-12-11 05:15:00
10524	1348	10	2	2018-08-23 06:45:00
10525	1348	10	2	2019-09-05 04:45:00
10526	1349	18	8	2018-10-01 14:30:00
10527	1349	18	8	2019-09-26 02:00:00
10528	1350	9	2	2020-04-12 18:45:00
10529	1350	9	2	2019-01-26 03:45:00
10530	1350	9	2	2019-03-22 00:30:00
10531	1350	9	2	2019-12-14 21:45:00
10532	1350	9	2	2019-03-21 00:45:00
10533	1350	9	2	2020-01-08 08:30:00
10534	1350	9	2	2020-03-17 13:00:00
10535	1350	9	2	2020-03-07 18:30:00
10536	1350	9	2	2019-08-15 08:30:00
10537	1351	11	20	2018-10-25 19:15:00
10538	1351	11	20	2019-12-27 23:00:00
10539	1351	11	20	2020-01-27 04:00:00
10540	1351	11	20	2020-07-12 19:15:00
10541	1351	11	20	2018-08-25 01:15:00
10542	1351	11	20	2020-05-28 16:15:00
10543	1351	11	20	2020-02-04 07:30:00
10544	1352	20	19	2021-02-08 17:45:00
10545	1352	20	19	2020-11-25 10:30:00
10546	1352	20	19	2020-06-24 11:15:00
10547	1352	20	19	2021-01-09 00:15:00
10548	1352	20	19	2019-06-15 14:30:00
10549	1352	20	19	2019-08-21 05:45:00
10550	1352	20	19	2020-09-02 01:15:00
10551	1352	20	19	2021-03-28 03:45:00
10552	1352	20	19	2021-05-29 05:30:00
10553	1353	8	13	2019-06-19 19:45:00
10554	1353	8	13	2020-04-13 05:00:00
10555	1353	8	13	2019-06-02 06:45:00
10556	1353	8	13	2019-03-01 11:00:00
10557	1353	8	13	2020-04-09 09:00:00
10558	1353	8	13	2019-06-03 06:15:00
10559	1353	8	13	2018-11-27 21:00:00
10560	1353	8	13	2019-09-23 06:15:00
10561	1353	8	13	2019-07-18 14:45:00
10562	1354	19	20	2018-07-19 02:15:00
10563	1354	19	20	2019-02-03 14:45:00
10564	1354	19	20	2019-02-14 12:30:00
10565	1354	19	20	2018-09-30 12:30:00
10566	1354	19	20	2018-07-19 13:15:00
10567	1354	19	20	2018-08-25 12:30:00
10568	1354	19	20	2018-08-16 18:15:00
10569	1354	19	20	2018-01-06 15:15:00
10570	1354	19	20	2019-01-06 21:45:00
10571	1354	19	20	2018-05-22 06:15:00
10572	1355	2	6	2017-05-29 05:15:00
10573	1355	2	6	2018-11-10 09:15:00
10574	1355	2	6	2018-05-26 13:00:00
10575	1355	2	6	2018-04-07 09:00:00
10576	1355	2	6	2017-12-22 15:00:00
10577	1355	2	6	2017-12-18 18:00:00
10578	1355	2	6	2017-07-15 01:45:00
10579	1355	2	6	2017-04-13 22:00:00
10580	1355	2	6	2017-11-29 18:30:00
10581	1355	2	6	2017-04-27 12:45:00
10582	1355	2	6	2017-04-24 00:30:00
10583	1355	2	6	2018-05-04 02:00:00
10584	1355	2	6	2018-11-16 22:15:00
10585	1355	2	6	2017-12-17 14:30:00
10586	1356	3	15	2019-12-23 19:30:00
10587	1356	3	15	2020-12-19 03:00:00
10588	1356	3	15	2019-07-17 07:30:00
10589	1356	3	15	2019-04-25 18:15:00
10590	1356	3	15	2020-11-17 04:15:00
10591	1356	3	15	2020-12-07 00:30:00
10592	1356	3	15	2019-07-19 07:00:00
10593	1357	6	5	2020-02-01 01:15:00
10594	1357	6	5	2020-10-27 04:15:00
10595	1357	6	5	2019-09-16 01:00:00
10596	1357	6	5	2020-02-02 03:15:00
10597	1357	6	5	2020-03-05 04:00:00
10598	1357	6	5	2021-01-12 08:15:00
10599	1358	1	1	2019-12-19 10:30:00
10600	1358	1	1	2020-01-12 04:00:00
10601	1358	1	1	2020-01-09 20:15:00
10602	1358	1	1	2018-12-01 11:00:00
10603	1358	1	1	2019-08-23 18:00:00
10604	1359	14	16	2019-08-29 12:30:00
10605	1359	14	16	2020-08-08 18:30:00
10606	1359	14	16	2019-04-03 11:15:00
10607	1359	14	16	2019-10-21 12:30:00
10608	1359	14	16	2019-12-16 02:30:00
10609	1359	14	16	2019-09-07 21:15:00
10610	1360	7	12	2020-02-06 04:00:00
10611	1360	7	12	2019-10-29 10:15:00
10612	1360	7	12	2018-10-15 18:00:00
10613	1360	7	12	2018-06-01 22:45:00
10614	1360	7	12	2019-07-10 02:30:00
10615	1360	7	12	2019-06-01 07:30:00
10616	1360	7	12	2020-02-14 12:15:00
10617	1360	7	12	2020-01-13 23:15:00
10618	1360	7	12	2018-04-03 23:45:00
10619	1360	7	12	2019-05-30 03:45:00
10620	1361	14	7	2019-06-19 16:15:00
10621	1361	14	7	2019-08-02 15:00:00
10622	1361	14	7	2019-12-19 13:45:00
10623	1361	14	7	2020-04-04 05:00:00
10624	1361	14	7	2019-09-03 01:15:00
10625	1361	14	7	2019-12-30 20:30:00
10626	1361	14	7	2020-03-12 16:30:00
10627	1361	14	7	2019-11-04 15:15:00
10628	1361	14	7	2019-03-09 03:00:00
10629	1361	14	7	2018-06-27 21:15:00
10630	1361	14	7	2018-11-14 11:15:00
10631	1362	2	4	2019-03-14 21:30:00
10632	1362	2	4	2019-10-21 04:45:00
10633	1362	2	4	2020-01-19 20:15:00
10634	1362	2	4	2020-04-30 01:45:00
10635	1362	2	4	2019-07-02 15:15:00
10636	1362	2	4	2018-12-16 04:45:00
10637	1363	16	6	2019-11-10 02:00:00
10638	1363	16	6	2020-02-01 14:45:00
10639	1363	16	6	2020-05-03 11:45:00
10640	1363	16	6	2020-06-04 09:45:00
10641	1363	16	6	2019-09-14 04:00:00
10642	1363	16	6	2019-05-14 10:15:00
10643	1363	16	6	2020-07-19 14:30:00
10644	1363	16	6	2018-09-14 01:45:00
10645	1363	16	6	2018-09-06 21:30:00
10646	1363	16	6	2018-09-24 07:45:00
10647	1363	16	6	2018-12-16 05:30:00
10648	1364	4	18	2019-10-18 23:15:00
10649	1364	4	18	2019-02-03 11:00:00
10650	1365	7	2	2020-04-16 12:00:00
10651	1365	7	2	2019-02-19 12:30:00
10652	1365	7	2	2020-10-26 00:15:00
10653	1365	7	2	2020-08-03 22:00:00
10654	1365	7	2	2020-08-08 21:45:00
10655	1366	2	5	2019-04-02 08:15:00
10656	1366	2	5	2019-08-15 06:30:00
10657	1366	2	5	2019-07-22 12:45:00
10658	1366	2	5	2020-01-09 20:30:00
10659	1366	2	5	2018-12-11 05:30:00
10660	1366	2	5	2019-11-18 06:45:00
10661	1367	6	20	2021-04-20 07:30:00
10662	1367	6	20	2020-11-26 12:15:00
10663	1367	6	20	2021-03-05 02:30:00
10664	1367	6	20	2021-02-23 13:00:00
10665	1367	6	20	2021-05-28 06:30:00
10666	1367	6	20	2021-08-29 23:45:00
10667	1367	6	20	2021-01-26 05:15:00
10668	1367	6	20	2021-07-12 11:15:00
10669	1367	6	20	2021-02-18 12:00:00
10670	1367	6	20	2020-01-09 02:15:00
10671	1367	6	20	2020-09-16 17:45:00
10672	1367	6	20	2020-01-18 15:00:00
10673	1368	11	2	2020-08-11 17:30:00
10674	1368	11	2	2019-07-22 16:45:00
10675	1368	11	2	2020-04-30 04:30:00
10676	1368	11	2	2020-05-11 08:45:00
10677	1368	11	2	2020-07-27 07:00:00
10678	1368	11	2	2019-09-05 21:15:00
10679	1368	11	2	2019-06-22 22:45:00
10680	1368	11	2	2019-09-20 15:45:00
10681	1368	11	2	2019-10-18 16:45:00
10682	1368	11	2	2020-02-12 10:45:00
10683	1368	11	2	2019-10-30 17:45:00
10684	1368	11	2	2021-03-24 10:30:00
10685	1368	11	2	2019-06-01 02:00:00
10686	1368	11	2	2020-11-29 03:30:00
10687	1368	11	2	2020-05-23 20:00:00
10688	1369	11	20	2019-07-06 23:00:00
10689	1369	11	20	2020-03-21 15:45:00
10690	1369	11	20	2019-02-27 23:30:00
10691	1369	11	20	2020-02-20 00:00:00
10692	1369	11	20	2019-03-23 08:15:00
10693	1369	11	20	2018-12-24 02:30:00
10694	1369	11	20	2019-12-18 23:30:00
10695	1369	11	20	2019-03-01 14:00:00
10696	1369	11	20	2019-07-06 13:15:00
10697	1369	11	20	2019-01-28 14:45:00
10698	1370	7	1	2018-07-14 02:00:00
10699	1370	7	1	2019-03-21 00:00:00
10700	1370	7	1	2018-12-27 15:15:00
10701	1370	7	1	2019-11-04 23:00:00
10702	1370	7	1	2019-08-08 14:30:00
10703	1370	7	1	2019-04-21 22:00:00
10704	1370	7	1	2018-03-29 09:00:00
10705	1370	7	1	2019-04-07 01:00:00
10706	1370	7	1	2018-11-27 22:45:00
10707	1370	7	1	2019-08-20 04:30:00
10708	1370	7	1	2019-06-28 08:30:00
10709	1371	19	18	2018-10-24 13:45:00
10710	1371	19	18	2019-02-01 10:00:00
10711	1371	19	18	2020-01-18 11:30:00
10712	1371	19	18	2018-09-12 01:15:00
10713	1371	19	18	2019-08-22 08:00:00
10714	1371	19	18	2019-11-09 09:45:00
10715	1371	19	18	2019-05-16 17:30:00
10716	1372	2	12	2019-02-23 22:15:00
10717	1373	15	12	2017-10-03 18:00:00
10718	1373	15	12	2019-03-16 03:15:00
10719	1373	15	12	2019-08-28 20:15:00
10720	1373	15	12	2018-11-25 20:00:00
10721	1374	11	18	2019-10-17 20:45:00
10722	1374	11	18	2019-12-05 09:15:00
10723	1374	11	18	2020-02-11 10:00:00
10724	1374	11	18	2020-08-30 23:30:00
10725	1374	11	18	2019-02-04 14:30:00
10726	1374	11	18	2019-09-01 05:45:00
10727	1374	11	18	2019-12-07 17:30:00
10728	1374	11	18	2018-10-27 03:15:00
10729	1374	11	18	2019-10-13 04:45:00
10730	1375	12	14	2018-09-02 18:00:00
10731	1375	12	14	2018-07-04 11:30:00
10732	1376	3	5	2017-12-06 08:15:00
10733	1376	3	5	2018-01-03 21:45:00
10734	1376	3	5	2018-06-14 03:30:00
10735	1376	3	5	2019-01-24 07:00:00
10736	1376	3	5	2018-04-21 09:30:00
10737	1376	3	5	2017-12-19 12:30:00
10738	1377	11	4	2018-11-13 16:30:00
10739	1377	11	4	2018-10-18 08:45:00
10740	1377	11	4	2017-11-29 01:00:00
10741	1377	11	4	2018-11-07 23:30:00
10742	1377	11	4	2017-08-01 04:00:00
10743	1377	11	4	2018-03-13 09:00:00
10744	1377	11	4	2017-07-21 01:15:00
10745	1377	11	4	2018-12-12 06:00:00
10746	1377	11	4	2017-09-10 13:00:00
10747	1377	11	4	2018-05-21 21:45:00
10748	1377	11	4	2017-09-19 17:00:00
10749	1377	11	4	2018-12-28 18:30:00
10750	1377	11	4	2017-10-26 13:45:00
10751	1378	3	19	2020-12-20 01:45:00
10752	1378	3	19	2020-12-06 04:00:00
10753	1378	3	19	2019-06-26 02:15:00
10754	1378	3	19	2021-01-14 11:30:00
10755	1378	3	19	2020-02-16 03:00:00
10756	1378	3	19	2019-08-18 22:15:00
10757	1378	3	19	2020-11-14 08:15:00
10758	1379	4	2	2018-09-16 02:00:00
10759	1379	4	2	2020-02-07 22:45:00
10760	1379	4	2	2018-12-27 12:30:00
10761	1379	4	2	2020-03-13 03:30:00
10762	1380	14	3	2019-05-18 18:00:00
10763	1380	14	3	2019-05-04 08:30:00
10764	1380	14	3	2020-03-10 04:00:00
10765	1380	14	3	2018-10-17 01:15:00
10766	1380	14	3	2020-03-04 17:45:00
10767	1380	14	3	2018-08-11 05:00:00
10768	1380	14	3	2018-10-27 11:30:00
10769	1380	14	3	2018-12-29 01:15:00
10770	1380	14	3	2018-08-23 21:30:00
10771	1380	14	3	2019-07-28 01:45:00
10772	1380	14	3	2019-01-03 20:30:00
10773	1380	14	3	2019-12-20 12:30:00
10774	1381	10	1	2018-08-23 08:45:00
10775	1381	10	1	2020-06-21 09:00:00
10776	1381	10	1	2019-04-16 06:00:00
10777	1381	10	1	2020-03-06 01:30:00
10778	1381	10	1	2018-08-15 16:15:00
10779	1381	10	1	2018-12-23 09:00:00
10780	1381	10	1	2020-01-30 04:00:00
10781	1381	10	1	2019-08-07 13:45:00
10782	1381	10	1	2019-02-23 06:45:00
10783	1381	10	1	2019-01-28 03:30:00
10784	1381	10	1	2020-01-21 12:15:00
10785	1381	10	1	2019-01-20 00:30:00
10786	1381	10	1	2019-03-20 17:15:00
10787	1382	7	9	2018-08-25 09:45:00
10788	1382	7	9	2019-11-26 21:00:00
10789	1382	7	9	2019-07-29 03:15:00
10790	1382	7	9	2018-09-21 08:15:00
10791	1382	7	9	2018-10-23 19:45:00
10792	1383	10	8	2017-09-02 20:00:00
10793	1383	10	8	2017-07-17 16:15:00
10794	1384	1	7	2020-04-01 12:00:00
10795	1384	1	7	2019-04-01 06:30:00
10796	1384	1	7	2019-01-02 05:30:00
10797	1384	1	7	2019-09-08 10:00:00
10798	1384	1	7	2019-05-27 04:45:00
10799	1384	1	7	2020-06-08 15:45:00
10800	1384	1	7	2019-05-17 09:45:00
10801	1384	1	7	2019-02-06 12:30:00
10802	1384	1	7	2019-06-22 11:30:00
10803	1385	18	15	2019-10-18 14:15:00
10804	1385	18	15	2019-07-25 05:15:00
10805	1385	18	15	2018-02-03 18:45:00
10806	1385	18	15	2019-10-18 12:45:00
10807	1386	14	15	2018-11-29 08:30:00
10808	1386	14	15	2018-01-26 21:00:00
10809	1386	14	15	2019-08-05 16:00:00
10810	1386	14	15	2019-11-01 13:30:00
10811	1386	14	15	2019-10-10 10:15:00
10812	1386	14	15	2019-01-26 05:30:00
10813	1386	14	15	2019-09-18 23:45:00
10814	1386	14	15	2019-02-03 21:30:00
10815	1387	19	4	2021-02-11 20:45:00
10816	1388	7	12	2018-10-16 20:45:00
10817	1388	7	12	2018-03-15 00:00:00
10818	1388	7	12	2019-07-05 00:00:00
10819	1388	7	12	2019-11-16 13:30:00
10820	1388	7	12	2019-10-14 04:15:00
10821	1388	7	12	2018-02-20 17:30:00
10822	1389	12	13	2021-03-19 05:15:00
10823	1389	12	13	2020-05-27 11:45:00
10824	1389	12	13	2020-02-01 17:45:00
10825	1389	12	13	2020-06-17 10:45:00
10826	1389	12	13	2021-01-17 12:00:00
10827	1389	12	13	2020-03-02 04:15:00
10828	1389	12	13	2020-11-26 08:15:00
10829	1389	12	13	2021-01-01 11:00:00
10830	1389	12	13	2020-09-24 07:00:00
10831	1390	17	6	2021-01-11 11:15:00
10832	1390	17	6	2020-10-04 16:15:00
10833	1390	17	6	2020-12-25 09:15:00
10834	1390	17	6	2021-01-27 03:15:00
10835	1390	17	6	2020-04-02 20:30:00
10836	1390	17	6	2019-09-20 16:30:00
10837	1390	17	6	2019-05-06 09:15:00
10838	1390	17	6	2020-03-28 08:00:00
10839	1390	17	6	2019-04-07 22:15:00
10840	1390	17	6	2020-01-12 03:15:00
10841	1390	17	6	2019-06-28 01:45:00
10842	1390	17	6	2020-02-17 22:30:00
10843	1391	16	2	2019-08-11 22:45:00
10844	1391	16	2	2021-01-26 18:45:00
10845	1391	16	2	2019-10-06 05:45:00
10846	1391	16	2	2021-03-08 09:00:00
10847	1391	16	2	2020-09-04 02:30:00
10848	1391	16	2	2021-02-18 15:15:00
10849	1391	16	2	2019-08-12 20:45:00
10850	1391	16	2	2019-10-15 13:45:00
10851	1392	1	7	2020-09-15 02:00:00
10852	1392	1	7	2021-05-04 21:30:00
10853	1392	1	7	2020-03-16 08:30:00
10854	1392	1	7	2021-01-03 12:00:00
10855	1392	1	7	2020-06-30 21:15:00
10856	1392	1	7	2019-08-01 16:30:00
10857	1393	7	6	2017-11-21 15:15:00
10858	1393	7	6	2018-07-04 02:30:00
10859	1393	7	6	2018-11-18 19:15:00
10860	1393	7	6	2019-08-08 11:45:00
10861	1393	7	6	2017-12-19 22:00:00
10862	1393	7	6	2018-10-12 07:30:00
10863	1393	7	6	2018-04-27 13:30:00
10864	1393	7	6	2019-04-12 21:30:00
10865	1393	7	6	2019-06-26 20:15:00
10866	1393	7	6	2018-08-20 04:15:00
10867	1393	7	6	2018-01-26 00:00:00
10868	1394	8	6	2018-07-04 06:00:00
10869	1394	8	6	2019-06-12 23:00:00
10870	1394	8	6	2019-12-19 06:45:00
10871	1395	16	10	2020-05-20 03:45:00
10872	1395	16	10	2019-03-12 04:00:00
10873	1395	16	10	2019-04-29 13:15:00
10874	1395	16	10	2019-10-14 07:15:00
10875	1395	16	10	2020-04-28 19:00:00
10876	1395	16	10	2020-10-28 18:00:00
10877	1395	16	10	2019-06-05 01:45:00
10878	1395	16	10	2020-05-06 22:45:00
10879	1395	16	10	2020-05-30 00:45:00
10880	1396	18	3	2021-05-20 07:15:00
10881	1396	18	3	2020-11-05 08:00:00
10882	1396	18	3	2020-03-28 19:45:00
10883	1396	18	3	2021-06-29 00:00:00
10884	1396	18	3	2019-11-12 12:15:00
10885	1396	18	3	2020-02-04 22:15:00
10886	1396	18	3	2020-02-02 12:30:00
10887	1397	20	4	2019-08-06 02:00:00
10888	1397	20	4	2019-03-17 23:00:00
10889	1398	15	4	2018-11-24 11:15:00
10890	1398	15	4	2019-06-09 14:15:00
10891	1398	15	4	2018-05-21 02:15:00
10892	1398	15	4	2019-02-20 12:15:00
10893	1398	15	4	2018-05-08 22:15:00
10894	1398	15	4	2017-12-20 03:00:00
10895	1398	15	4	2019-01-29 23:00:00
10896	1398	15	4	2019-02-25 21:45:00
10897	1398	15	4	2018-10-13 08:15:00
10898	1399	7	6	2018-07-26 07:45:00
10899	1399	7	6	2018-10-17 20:15:00
10900	1399	7	6	2017-07-02 23:30:00
10901	1400	17	10	2020-01-24 02:15:00
10902	1400	17	10	2020-07-02 11:15:00
10903	1400	17	10	2021-02-07 15:15:00
10904	1400	17	10	2020-12-04 09:30:00
10905	1401	7	11	2018-05-02 04:30:00
10906	1401	7	11	2019-06-03 13:15:00
10907	1401	7	11	2018-12-13 18:30:00
10908	1402	3	6	2020-11-21 08:15:00
10909	1402	3	6	2019-02-18 11:15:00
10910	1402	3	6	2019-09-04 20:30:00
10911	1402	3	6	2019-06-02 08:45:00
10912	1402	3	6	2019-04-07 10:45:00
10913	1402	3	6	2019-12-25 22:30:00
10914	1402	3	6	2020-04-21 17:00:00
10915	1402	3	6	2020-10-30 00:15:00
10916	1402	3	6	2019-08-11 12:45:00
10917	1402	3	6	2020-05-01 17:00:00
10918	1403	2	12	2018-11-02 16:00:00
10919	1403	2	12	2019-07-06 05:30:00
10920	1403	2	12	2018-08-10 23:30:00
10921	1403	2	12	2018-07-13 02:45:00
10922	1404	12	17	2018-11-19 22:15:00
10923	1404	12	17	2019-04-22 10:45:00
10924	1404	12	17	2019-04-09 04:45:00
10925	1404	12	17	2018-11-08 04:15:00
10926	1404	12	17	2019-07-30 04:30:00
10927	1404	12	17	2018-10-26 14:30:00
10928	1404	12	17	2019-02-14 16:30:00
10929	1404	12	17	2018-01-10 15:15:00
10930	1404	12	17	2017-12-15 00:45:00
10931	1404	12	17	2018-06-01 07:15:00
10932	1405	12	3	2019-12-22 11:15:00
10933	1405	12	3	2021-01-24 21:15:00
10934	1405	12	3	2019-08-18 20:30:00
10935	1405	12	3	2021-06-13 02:15:00
10936	1405	12	3	2021-07-06 12:00:00
10937	1405	12	3	2019-09-02 05:00:00
10938	1405	12	3	2021-06-17 22:00:00
10939	1406	1	17	2018-07-01 13:45:00
10940	1407	9	11	2020-11-27 02:45:00
10941	1407	9	11	2021-11-08 17:30:00
10942	1408	6	11	2020-06-01 12:45:00
10943	1408	6	11	2019-05-18 16:00:00
10944	1408	6	11	2021-01-15 02:30:00
10945	1408	6	11	2019-06-15 04:30:00
10946	1408	6	11	2019-11-12 19:45:00
10947	1408	6	11	2020-06-14 14:45:00
10948	1408	6	11	2020-06-29 16:00:00
10949	1408	6	11	2019-09-01 01:00:00
10950	1408	6	11	2019-06-22 14:30:00
10951	1408	6	11	2020-05-08 07:15:00
10952	1408	6	11	2020-09-03 03:15:00
10953	1408	6	11	2020-07-25 00:15:00
10954	1408	6	11	2019-06-29 13:00:00
10955	1409	16	7	2017-10-07 07:30:00
10956	1409	16	7	2019-02-12 05:30:00
10957	1409	16	7	2017-03-06 00:30:00
10958	1409	16	7	2018-12-13 12:30:00
10959	1409	16	7	2017-10-09 23:30:00
10960	1410	20	8	2018-02-12 06:30:00
10961	1410	20	8	2017-11-26 11:45:00
10962	1410	20	8	2017-10-12 13:00:00
10963	1410	20	8	2018-02-02 13:15:00
10964	1410	20	8	2017-12-27 01:30:00
10965	1410	20	8	2018-11-13 22:45:00
10966	1410	20	8	2017-11-10 22:45:00
10967	1410	20	8	2017-08-01 11:15:00
10968	1410	20	8	2018-12-02 23:30:00
10969	1410	20	8	2018-12-30 13:45:00
10970	1410	20	8	2017-08-03 21:15:00
10971	1410	20	8	2018-07-11 15:30:00
10972	1410	20	8	2018-04-16 18:45:00
10973	1410	20	8	2019-01-13 21:30:00
10974	1410	20	8	2019-03-07 05:45:00
10975	1411	7	18	2019-04-13 01:00:00
10976	1411	7	18	2019-01-14 09:30:00
10977	1411	7	18	2020-04-14 11:45:00
10978	1411	7	18	2019-06-13 16:30:00
10979	1411	7	18	2020-07-14 16:45:00
10980	1411	7	18	2020-08-04 08:00:00
10981	1411	7	18	2019-07-26 18:30:00
10982	1411	7	18	2020-06-28 17:15:00
10983	1411	7	18	2020-05-25 05:45:00
10984	1411	7	18	2019-06-21 04:15:00
10985	1411	7	18	2018-12-15 21:45:00
10986	1412	3	16	2018-12-22 15:15:00
10987	1412	3	16	2020-08-28 07:30:00
10988	1412	3	16	2019-08-16 09:45:00
10989	1412	3	16	2019-04-25 00:15:00
10990	1412	3	16	2019-05-21 04:00:00
10991	1412	3	16	2019-02-04 11:45:00
10992	1412	3	16	2020-06-12 09:30:00
10993	1412	3	16	2020-04-16 06:30:00
10994	1412	3	16	2019-02-03 10:00:00
10995	1412	3	16	2019-11-28 02:30:00
10996	1412	3	16	2018-11-08 01:30:00
10997	1412	3	16	2020-01-06 21:00:00
10998	1412	3	16	2020-03-06 10:45:00
10999	1412	3	16	2019-08-25 04:45:00
11000	1412	3	16	2019-03-01 08:00:00
11001	1413	1	20	2020-03-11 08:30:00
11002	1413	1	20	2019-11-02 08:00:00
11003	1413	1	20	2019-11-01 17:15:00
11004	1413	1	20	2019-11-15 07:15:00
11005	1413	1	20	2018-09-23 12:45:00
11006	1413	1	20	2019-02-16 20:30:00
11007	1414	12	4	2020-06-26 11:00:00
11008	1414	12	4	2020-04-11 09:15:00
11009	1414	12	4	2020-06-01 21:30:00
11010	1415	17	4	2020-03-19 16:00:00
11011	1415	17	4	2020-03-01 06:30:00
11012	1415	17	4	2020-02-14 14:30:00
11013	1415	17	4	2019-11-27 19:45:00
11014	1415	17	4	2019-06-29 05:30:00
11015	1415	17	4	2019-10-25 17:45:00
11016	1415	17	4	2019-11-11 17:45:00
11017	1415	17	4	2020-03-10 08:15:00
11018	1415	17	4	2020-01-16 11:30:00
11019	1416	15	6	2019-12-28 14:45:00
11020	1416	15	6	2020-01-19 16:30:00
11021	1416	15	6	2020-10-16 05:15:00
11022	1416	15	6	2020-05-30 11:15:00
11023	1416	15	6	2019-04-28 22:00:00
11024	1416	15	6	2020-10-24 15:00:00
11025	1416	15	6	2020-07-24 05:30:00
11026	1416	15	6	2020-09-16 04:45:00
11027	1416	15	6	2020-08-01 10:00:00
11028	1417	11	14	2019-03-15 02:30:00
11029	1417	11	14	2018-08-23 11:15:00
11030	1417	11	14	2019-07-19 19:00:00
11031	1417	11	14	2019-02-18 09:00:00
11032	1417	11	14	2019-06-27 21:15:00
11033	1417	11	14	2018-11-18 06:45:00
11034	1418	16	2	2020-09-16 04:30:00
11035	1418	16	2	2020-07-24 09:15:00
11036	1418	16	2	2019-10-07 12:45:00
11037	1418	16	2	2019-09-23 09:30:00
11038	1418	16	2	2019-09-13 12:30:00
11039	1418	16	2	2020-02-03 16:30:00
11040	1419	7	5	2018-08-19 22:00:00
11041	1419	7	5	2019-04-17 02:30:00
11042	1419	7	5	2018-06-09 01:15:00
11043	1419	7	5	2018-06-26 04:45:00
11044	1420	3	8	2019-02-23 18:00:00
11045	1420	3	8	2019-03-08 08:30:00
11046	1420	3	8	2020-02-14 01:30:00
11047	1420	3	8	2020-10-26 22:45:00
11048	1420	3	8	2020-11-03 04:15:00
11049	1420	3	8	2020-07-27 11:45:00
11050	1420	3	8	2019-05-08 21:15:00
11051	1421	18	15	2018-10-02 15:15:00
11052	1421	18	15	2018-02-08 05:30:00
11053	1421	18	15	2018-09-21 13:15:00
11054	1421	18	15	2018-09-17 00:00:00
11055	1421	18	15	2017-09-25 07:30:00
11056	1421	18	15	2018-08-02 12:45:00
11057	1421	18	15	2018-12-08 22:30:00
11058	1421	18	15	2018-02-11 17:00:00
11059	1421	18	15	2018-05-08 00:00:00
11060	1421	18	15	2019-05-14 00:15:00
11061	1421	18	15	2018-09-16 05:15:00
11062	1421	18	15	2019-06-17 02:00:00
11063	1421	18	15	2018-07-05 08:15:00
11064	1421	18	15	2018-07-27 21:45:00
11065	1421	18	15	2018-04-12 15:00:00
11066	1422	9	12	2019-05-15 14:30:00
11067	1422	9	12	2019-04-13 17:00:00
11068	1422	9	12	2019-10-08 06:45:00
11069	1422	9	12	2018-11-26 05:15:00
11070	1423	10	14	2020-06-11 22:00:00
11071	1423	10	14	2019-05-07 04:30:00
11072	1424	11	5	2018-12-14 01:45:00
11073	1424	11	5	2018-01-30 11:15:00
11074	1424	11	5	2018-06-26 13:30:00
11075	1424	11	5	2017-11-06 20:45:00
11076	1424	11	5	2018-08-22 13:15:00
11077	1424	11	5	2018-08-09 15:00:00
11078	1424	11	5	2019-09-02 13:00:00
11079	1424	11	5	2019-07-30 10:15:00
11080	1424	11	5	2019-09-02 18:30:00
11081	1424	11	5	2019-06-19 14:15:00
11082	1424	11	5	2018-01-18 04:15:00
11083	1425	12	20	2018-12-23 06:00:00
11084	1425	12	20	2020-06-23 00:45:00
11085	1425	12	20	2019-06-09 13:30:00
11086	1425	12	20	2020-03-13 06:45:00
11087	1425	12	20	2019-02-22 03:45:00
11088	1425	12	20	2018-08-09 21:45:00
11089	1425	12	20	2020-04-08 01:45:00
11090	1425	12	20	2019-05-13 03:30:00
11091	1425	12	20	2019-07-02 06:30:00
11092	1426	6	16	2018-08-01 22:00:00
11093	1426	6	16	2018-05-28 21:30:00
11094	1426	6	16	2018-02-10 23:30:00
11095	1426	6	16	2019-03-14 23:15:00
11096	1426	6	16	2018-03-12 13:00:00
11097	1426	6	16	2019-05-24 06:00:00
11098	1426	6	16	2017-08-27 19:15:00
11099	1427	2	13	2017-10-14 18:45:00
11100	1427	2	13	2018-12-12 05:00:00
11101	1427	2	13	2019-02-09 17:30:00
11102	1428	12	13	2018-06-05 01:00:00
11103	1428	12	13	2018-08-13 19:00:00
11104	1428	12	13	2018-10-14 08:45:00
11105	1428	12	13	2018-05-22 17:15:00
11106	1428	12	13	2018-09-26 12:45:00
11107	1428	12	13	2019-09-03 17:30:00
11108	1428	12	13	2018-10-25 06:00:00
11109	1428	12	13	2018-11-18 02:30:00
11110	1428	12	13	2019-02-02 03:15:00
11111	1428	12	13	2018-11-05 22:45:00
11112	1428	12	13	2018-06-28 18:15:00
11113	1429	16	16	2019-02-21 12:45:00
11114	1429	16	16	2017-11-23 01:15:00
11115	1430	3	4	2018-06-21 20:00:00
11116	1430	3	4	2019-06-06 23:45:00
11117	1430	3	4	2019-03-19 11:45:00
11118	1430	3	4	2018-09-17 01:15:00
11119	1430	3	4	2018-09-26 13:30:00
11120	1430	3	4	2019-02-20 06:15:00
11121	1431	15	7	2020-01-08 12:00:00
11122	1431	15	7	2019-10-24 19:30:00
11123	1431	15	7	2020-03-22 12:15:00
11124	1431	15	7	2019-04-12 22:30:00
11125	1431	15	7	2019-11-29 12:00:00
11126	1431	15	7	2018-11-24 08:30:00
11127	1431	15	7	2018-09-16 13:15:00
11128	1431	15	7	2019-08-15 23:30:00
11129	1431	15	7	2018-07-15 20:00:00
11130	1431	15	7	2018-06-25 19:15:00
11131	1431	15	7	2019-01-19 06:15:00
11132	1432	15	11	2017-11-26 10:30:00
11133	1432	15	11	2017-10-27 05:15:00
11134	1432	15	11	2019-01-15 16:15:00
11135	1432	15	11	2018-03-02 10:15:00
11136	1432	15	11	2019-05-21 15:30:00
11137	1432	15	11	2017-12-19 11:30:00
11138	1432	15	11	2019-02-07 00:45:00
11139	1432	15	11	2019-02-19 22:00:00
11140	1432	15	11	2017-09-05 10:30:00
11141	1432	15	11	2018-12-14 13:00:00
11142	1432	15	11	2018-04-17 15:15:00
11143	1432	15	11	2018-07-04 22:00:00
11144	1432	15	11	2018-10-22 23:00:00
11145	1432	15	11	2019-03-15 05:30:00
11146	1433	17	11	2018-10-15 13:45:00
11147	1433	17	11	2019-08-24 11:15:00
11148	1433	17	11	2020-07-11 21:15:00
11149	1434	19	15	2020-12-02 03:45:00
11150	1434	19	15	2019-10-29 08:00:00
11151	1434	19	15	2020-05-26 16:00:00
11152	1434	19	15	2020-09-25 01:00:00
11153	1434	19	15	2020-12-30 12:15:00
11154	1434	19	15	2020-10-06 00:15:00
11155	1434	19	15	2019-12-22 05:45:00
11156	1434	19	15	2019-11-11 01:15:00
11157	1434	19	15	2019-12-07 18:15:00
11158	1434	19	15	2019-03-22 10:15:00
11159	1435	5	3	2020-12-02 06:30:00
11160	1435	5	3	2020-01-06 14:15:00
11161	1435	5	3	2019-10-02 23:45:00
11162	1435	5	3	2020-06-04 23:00:00
11163	1435	5	3	2020-03-10 13:30:00
11164	1435	5	3	2020-04-20 07:15:00
11165	1435	5	3	2021-03-03 04:00:00
11166	1435	5	3	2019-08-15 23:00:00
11167	1435	5	3	2020-07-18 09:00:00
11168	1435	5	3	2019-09-04 15:45:00
11169	1435	5	3	2020-10-21 10:30:00
11170	1435	5	3	2020-03-18 14:45:00
11171	1436	7	12	2019-01-15 08:15:00
11172	1436	7	12	2018-09-24 05:30:00
11173	1436	7	12	2018-02-07 16:45:00
11174	1436	7	12	2018-11-24 04:30:00
11175	1436	7	12	2017-08-01 14:15:00
11176	1436	7	12	2019-03-14 20:45:00
11177	1436	7	12	2019-05-09 10:45:00
11178	1437	9	5	2021-01-19 18:30:00
11179	1437	9	5	2020-09-15 13:00:00
11180	1437	9	5	2020-10-28 18:30:00
11181	1437	9	5	2019-04-21 23:30:00
11182	1437	9	5	2019-09-29 03:00:00
11183	1437	9	5	2020-12-08 11:45:00
11184	1437	9	5	2019-10-21 07:00:00
11185	1437	9	5	2019-02-19 07:30:00
11186	1437	9	5	2019-10-01 00:45:00
11187	1437	9	5	2020-10-16 03:15:00
11188	1437	9	5	2019-03-20 22:30:00
11189	1437	9	5	2020-05-06 15:15:00
11190	1437	9	5	2019-05-22 17:00:00
11191	1438	11	12	2019-10-18 16:30:00
11192	1438	11	12	2019-06-11 01:30:00
11193	1438	11	12	2019-04-16 00:45:00
11194	1438	11	12	2018-03-02 17:15:00
11195	1438	11	12	2019-05-11 12:15:00
11196	1438	11	12	2019-04-10 19:45:00
11197	1438	11	12	2018-02-10 11:00:00
11198	1438	11	12	2018-02-09 15:00:00
11199	1438	11	12	2018-11-14 22:00:00
11200	1438	11	12	2018-12-05 06:45:00
11201	1438	11	12	2018-07-11 05:30:00
11202	1438	11	12	2019-10-28 15:30:00
11203	1439	19	18	2018-08-25 06:45:00
11204	1439	19	18	2019-04-17 12:00:00
11205	1439	19	18	2018-09-10 00:45:00
11206	1440	7	5	2020-06-27 06:30:00
11207	1440	7	5	2020-10-14 23:00:00
11208	1440	7	5	2020-05-21 09:30:00
11209	1441	9	16	2018-02-09 23:30:00
11210	1441	9	16	2018-08-26 12:15:00
11211	1441	9	16	2017-04-10 20:00:00
11212	1441	9	16	2018-12-25 17:45:00
11213	1441	9	16	2018-05-19 15:00:00
11214	1441	9	16	2018-01-21 08:45:00
11215	1441	9	16	2017-07-16 21:00:00
11216	1441	9	16	2018-12-14 22:30:00
11217	1441	9	16	2017-06-16 04:45:00
11218	1441	9	16	2017-03-16 09:30:00
11219	1441	9	16	2017-03-14 09:00:00
11220	1441	9	16	2017-04-11 19:45:00
11221	1441	9	16	2017-07-16 03:45:00
11222	1441	9	16	2017-04-15 15:45:00
11223	1442	18	19	2020-11-02 06:15:00
11224	1442	18	19	2021-03-17 07:00:00
11225	1442	18	19	2020-04-24 15:15:00
11226	1442	18	19	2020-09-14 18:45:00
11227	1442	18	19	2020-11-10 11:15:00
11228	1442	18	19	2020-12-09 20:15:00
11229	1442	18	19	2020-10-06 04:45:00
11230	1442	18	19	2020-10-28 07:00:00
11231	1442	18	19	2020-12-26 06:00:00
11232	1442	18	19	2021-05-17 19:30:00
11233	1442	18	19	2019-07-16 16:15:00
11234	1442	18	19	2019-07-01 03:45:00
11235	1443	13	10	2020-01-02 11:45:00
11236	1443	13	10	2020-09-07 06:15:00
11237	1444	18	2	2020-07-15 10:45:00
11238	1444	18	2	2020-12-24 20:15:00
11239	1444	18	2	2021-02-25 07:45:00
11240	1444	18	2	2020-02-02 08:30:00
11241	1444	18	2	2020-01-04 11:00:00
11242	1444	18	2	2020-05-15 20:45:00
11243	1444	18	2	2020-01-05 14:45:00
11244	1444	18	2	2020-03-19 04:45:00
11245	1444	18	2	2021-10-16 17:45:00
11246	1444	18	2	2020-02-04 07:30:00
11247	1444	18	2	2021-01-01 16:30:00
11248	1444	18	2	2020-07-02 01:45:00
11249	1445	17	2	2021-12-29 12:15:00
11250	1445	17	2	2020-09-01 10:15:00
11251	1445	17	2	2021-05-24 04:15:00
11252	1445	17	2	2020-07-17 03:45:00
11253	1445	17	2	2021-06-03 16:15:00
11254	1445	17	2	2020-12-28 21:30:00
11255	1445	17	2	2020-10-17 12:00:00
11256	1446	11	18	2019-07-03 07:30:00
11257	1446	11	18	2019-09-26 22:15:00
11258	1446	11	18	2020-02-27 20:00:00
11259	1446	11	18	2019-08-26 01:45:00
11260	1446	11	18	2020-08-30 23:45:00
11261	1446	11	18	2019-06-02 02:45:00
11262	1446	11	18	2020-12-15 03:30:00
11263	1446	11	18	2020-05-26 23:15:00
11264	1446	11	18	2019-10-24 02:30:00
11265	1447	1	12	2019-03-15 05:15:00
11266	1447	1	12	2017-10-08 05:00:00
11267	1447	1	12	2018-10-28 17:15:00
11268	1447	1	12	2018-06-28 09:45:00
11269	1447	1	12	2019-09-28 01:45:00
11270	1447	1	12	2018-12-30 08:15:00
11271	1448	2	1	2017-06-04 17:15:00
11272	1448	2	1	2017-12-05 23:15:00
11273	1448	2	1	2019-01-22 04:45:00
11274	1449	20	6	2019-10-08 01:30:00
11275	1449	20	6	2019-06-24 03:45:00
11276	1449	20	6	2019-08-27 19:15:00
11277	1449	20	6	2020-04-19 21:30:00
11278	1449	20	6	2018-10-18 13:00:00
11279	1449	20	6	2018-09-03 20:00:00
11280	1450	8	2	2021-09-18 19:15:00
11281	1450	8	2	2020-08-12 16:30:00
11282	1450	8	2	2021-05-24 01:00:00
11283	1450	8	2	2020-10-22 17:15:00
11284	1450	8	2	2021-08-22 14:15:00
11285	1450	8	2	2020-11-28 07:30:00
11286	1450	8	2	2020-06-15 02:30:00
11287	1451	14	19	2020-04-07 12:45:00
11288	1451	14	19	2021-04-13 13:00:00
11289	1451	14	19	2021-02-06 21:45:00
11290	1451	14	19	2021-04-13 16:00:00
11291	1451	14	19	2019-12-07 10:45:00
11292	1451	14	19	2019-08-20 22:00:00
11293	1451	14	19	2020-04-03 00:45:00
11294	1451	14	19	2020-12-20 19:15:00
11295	1451	14	19	2020-06-16 13:45:00
11296	1452	12	16	2019-07-29 17:15:00
11297	1452	12	16	2019-10-24 08:45:00
11298	1453	11	8	2017-11-22 17:45:00
11299	1453	11	8	2018-01-05 03:30:00
11300	1453	11	8	2019-04-15 02:30:00
11301	1453	11	8	2018-12-19 01:15:00
11302	1453	11	8	2019-02-20 15:15:00
11303	1453	11	8	2019-07-25 14:30:00
11304	1454	6	20	2018-06-03 06:00:00
11305	1454	6	20	2018-11-23 05:45:00
11306	1454	6	20	2017-09-24 23:00:00
11307	1454	6	20	2017-09-04 23:15:00
11308	1454	6	20	2018-09-11 03:00:00
11309	1454	6	20	2017-06-25 12:30:00
11310	1454	6	20	2018-04-29 21:15:00
11311	1454	6	20	2018-04-13 18:00:00
11312	1454	6	20	2018-04-23 11:00:00
11313	1454	6	20	2017-11-29 04:00:00
11314	1454	6	20	2018-03-18 11:15:00
11315	1454	6	20	2017-09-24 12:30:00
11316	1454	6	20	2017-06-22 17:15:00
11317	1455	17	7	2019-08-03 18:45:00
11318	1455	17	7	2020-05-15 04:15:00
11319	1455	17	7	2019-02-03 07:00:00
11320	1456	8	10	2017-10-21 10:30:00
11321	1456	8	10	2018-08-07 05:45:00
11322	1456	8	10	2019-06-27 22:15:00
11323	1456	8	10	2018-04-30 05:45:00
11324	1456	8	10	2017-11-17 09:15:00
11325	1456	8	10	2018-09-20 12:30:00
11326	1456	8	10	2018-05-28 14:30:00
11327	1456	8	10	2018-02-04 11:30:00
11328	1456	8	10	2019-04-05 18:45:00
11329	1456	8	10	2017-09-02 21:15:00
11330	1457	2	20	2021-01-22 05:45:00
11331	1457	2	20	2021-04-04 07:15:00
11332	1457	2	20	2021-09-30 18:30:00
11333	1457	2	20	2021-06-26 07:45:00
11334	1457	2	20	2020-11-11 21:15:00
11335	1457	2	20	2020-05-04 01:30:00
11336	1457	2	20	2020-06-18 09:15:00
11337	1458	16	19	2020-10-22 00:00:00
11338	1458	16	19	2020-10-23 14:00:00
11339	1458	16	19	2021-02-11 12:15:00
11340	1458	16	19	2020-02-26 03:00:00
11341	1458	16	19	2021-09-04 07:30:00
11342	1458	16	19	2019-10-07 21:30:00
11343	1458	16	19	2020-12-05 09:30:00
11344	1458	16	19	2020-07-02 20:00:00
11345	1458	16	19	2021-07-03 10:00:00
11346	1458	16	19	2020-12-06 08:45:00
11347	1459	11	10	2017-11-17 00:00:00
11348	1459	11	10	2018-01-21 10:30:00
11349	1459	11	10	2018-06-29 20:45:00
11350	1460	3	11	2017-08-16 22:00:00
11351	1460	3	11	2017-04-26 03:30:00
11352	1460	3	11	2017-11-29 14:00:00
11353	1460	3	11	2018-02-23 03:15:00
11354	1460	3	11	2018-03-17 17:30:00
11355	1460	3	11	2017-06-30 03:15:00
11356	1460	3	11	2017-09-07 14:15:00
11357	1460	3	11	2018-05-25 02:45:00
11358	1460	3	11	2018-01-19 23:00:00
11359	1460	3	11	2018-06-18 03:45:00
11360	1460	3	11	2018-11-21 09:15:00
11361	1460	3	11	2017-09-11 19:45:00
11362	1460	3	11	2019-01-17 07:45:00
11363	1461	7	20	2019-10-06 20:30:00
11364	1461	7	20	2018-04-13 16:15:00
11365	1461	7	20	2019-03-18 07:15:00
11366	1461	7	20	2019-09-21 09:15:00
11367	1461	7	20	2019-06-29 15:15:00
11368	1461	7	20	2018-11-25 18:45:00
11369	1461	7	20	2018-06-18 22:30:00
11370	1461	7	20	2018-07-15 12:45:00
11371	1461	7	20	2019-06-09 06:00:00
11372	1461	7	20	2019-11-10 02:45:00
11373	1462	19	10	2019-03-04 11:45:00
11374	1462	19	10	2019-10-27 19:15:00
11375	1462	19	10	2018-11-08 19:45:00
11376	1463	15	8	2019-02-03 01:30:00
11377	1463	15	8	2017-11-18 17:15:00
11378	1463	15	8	2018-12-02 19:45:00
11379	1463	15	8	2019-01-22 09:15:00
11380	1463	15	8	2018-05-21 20:45:00
11381	1463	15	8	2018-06-29 17:45:00
11382	1463	15	8	2018-12-24 18:00:00
11383	1463	15	8	2018-11-10 12:15:00
11384	1463	15	8	2018-12-22 22:45:00
11385	1463	15	8	2017-10-06 13:15:00
11386	1464	6	18	2021-02-07 01:00:00
11387	1465	6	7	2017-12-29 01:00:00
11388	1465	6	7	2017-07-18 08:00:00
11389	1465	6	7	2017-05-15 10:15:00
11390	1465	6	7	2018-03-28 09:15:00
11391	1465	6	7	2017-07-11 23:45:00
11392	1465	6	7	2017-09-22 05:00:00
11393	1465	6	7	2019-02-10 04:30:00
11394	1465	6	7	2017-11-02 06:00:00
11395	1465	6	7	2017-04-20 08:30:00
11396	1465	6	7	2019-03-02 22:15:00
11397	1465	6	7	2018-10-27 20:15:00
11398	1465	6	7	2017-12-10 23:00:00
11399	1465	6	7	2017-12-08 04:30:00
11400	1465	6	7	2018-06-11 00:45:00
11401	1466	5	17	2019-08-28 22:45:00
11402	1466	5	17	2019-12-13 13:00:00
11403	1466	5	17	2019-11-25 09:00:00
11404	1466	5	17	2019-05-10 10:30:00
11405	1466	5	17	2019-11-26 15:30:00
11406	1466	5	17	2020-06-22 16:45:00
11407	1466	5	17	2018-11-07 06:30:00
11408	1466	5	17	2020-09-29 21:15:00
11409	1466	5	17	2019-11-27 19:45:00
11410	1466	5	17	2019-08-16 11:00:00
11411	1467	6	16	2019-09-05 06:45:00
11412	1467	6	16	2017-10-09 05:45:00
11413	1467	6	16	2018-08-25 23:00:00
11414	1467	6	16	2017-12-20 20:15:00
11415	1468	7	15	2019-06-08 04:30:00
11416	1468	7	15	2019-03-05 11:45:00
11417	1468	7	15	2019-05-29 16:45:00
11418	1468	7	15	2019-10-14 15:45:00
11419	1468	7	15	2020-07-13 04:30:00
11420	1468	7	15	2020-01-06 15:15:00
11421	1468	7	15	2019-10-06 09:45:00
11422	1468	7	15	2019-10-26 18:30:00
11423	1468	7	15	2020-04-18 19:45:00
11424	1468	7	15	2020-04-28 17:00:00
11425	1468	7	15	2019-04-22 20:00:00
11426	1468	7	15	2018-09-14 07:00:00
11427	1468	7	15	2019-02-03 10:45:00
11428	1468	7	15	2018-09-17 16:00:00
11429	1468	7	15	2019-11-30 07:15:00
11430	1469	6	2	2019-10-05 07:00:00
11431	1470	17	8	2019-07-09 20:15:00
11432	1470	17	8	2020-04-20 12:00:00
11433	1470	17	8	2018-07-22 03:00:00
11434	1470	17	8	2018-07-24 03:45:00
11435	1470	17	8	2020-05-13 01:15:00
11436	1470	17	8	2020-03-06 09:45:00
11437	1470	17	8	2019-02-09 15:15:00
11438	1470	17	8	2019-05-25 01:45:00
11439	1470	17	8	2020-03-07 18:00:00
11440	1470	17	8	2020-01-29 01:45:00
11441	1470	17	8	2019-02-04 23:15:00
11442	1470	17	8	2020-06-23 04:15:00
11443	1470	17	8	2018-09-08 13:30:00
11444	1471	2	8	2021-05-22 01:15:00
11445	1471	2	8	2020-12-23 13:00:00
11446	1471	2	8	2020-08-09 06:30:00
11447	1471	2	8	2019-11-18 10:30:00
11448	1471	2	8	2019-12-02 03:00:00
11449	1471	2	8	2020-06-06 19:30:00
11450	1471	2	8	2021-10-16 01:45:00
11451	1471	2	8	2021-04-14 18:15:00
11452	1472	11	19	2020-11-21 17:30:00
11453	1472	11	19	2020-03-01 23:30:00
11454	1472	11	19	2020-12-29 13:45:00
11455	1472	11	19	2021-05-29 02:15:00
11456	1472	11	19	2021-08-09 10:15:00
11457	1472	11	19	2021-04-11 03:30:00
11458	1472	11	19	2019-12-22 21:15:00
11459	1473	10	12	2019-02-08 11:00:00
11460	1473	10	12	2019-02-14 10:30:00
11461	1473	10	12	2019-10-26 17:45:00
11462	1473	10	12	2020-05-02 15:30:00
11463	1473	10	12	2020-05-28 04:15:00
11464	1473	10	12	2019-09-24 22:00:00
11465	1474	18	8	2020-10-25 22:15:00
11466	1474	18	8	2019-12-30 23:00:00
11467	1474	18	8	2019-12-17 07:45:00
11468	1474	18	8	2020-01-28 05:00:00
11469	1474	18	8	2021-01-03 08:45:00
11470	1474	18	8	2020-03-03 19:30:00
11471	1474	18	8	2021-03-04 07:30:00
11472	1474	18	8	2020-07-27 03:45:00
11473	1474	18	8	2020-08-03 13:45:00
11474	1474	18	8	2019-10-29 22:45:00
11475	1474	18	8	2020-05-13 13:00:00
11476	1474	18	8	2020-08-03 21:45:00
11477	1475	8	18	2018-09-18 09:30:00
11478	1475	8	18	2018-10-26 13:30:00
11479	1475	8	18	2018-03-08 19:45:00
11480	1475	8	18	2018-12-07 23:00:00
11481	1475	8	18	2018-09-04 16:15:00
11482	1475	8	18	2019-04-02 14:30:00
11483	1475	8	18	2019-12-25 07:00:00
11484	1476	3	8	2018-05-29 09:45:00
11485	1476	3	8	2019-06-23 06:00:00
11486	1476	3	8	2018-08-28 16:30:00
11487	1476	3	8	2019-01-14 20:15:00
11488	1476	3	8	2018-03-03 19:30:00
11489	1476	3	8	2019-07-16 15:45:00
11490	1476	3	8	2019-12-15 10:45:00
11491	1476	3	8	2018-07-12 20:30:00
11492	1476	3	8	2018-08-24 08:45:00
11493	1477	8	8	2019-04-27 23:30:00
11494	1477	8	8	2018-10-08 16:00:00
11495	1477	8	8	2017-09-28 13:15:00
11496	1477	8	8	2017-08-11 11:00:00
11497	1477	8	8	2018-12-12 20:00:00
11498	1477	8	8	2017-07-01 03:30:00
11499	1477	8	8	2018-12-07 20:15:00
11500	1477	8	8	2018-09-10 16:15:00
11501	1478	1	15	2020-05-26 06:30:00
11502	1478	1	15	2020-10-22 08:00:00
11503	1478	1	15	2021-06-23 15:45:00
11504	1478	1	15	2020-08-02 10:00:00
11505	1478	1	15	2020-08-01 13:30:00
11506	1478	1	15	2020-12-17 12:15:00
11507	1478	1	15	2021-10-09 13:30:00
11508	1478	1	15	2020-02-22 20:00:00
11509	1478	1	15	2020-03-17 07:00:00
11510	1479	12	9	2020-10-29 06:00:00
11511	1479	12	9	2019-02-01 10:00:00
11512	1479	12	9	2020-03-04 00:15:00
11513	1479	12	9	2020-05-14 12:15:00
11514	1479	12	9	2019-07-28 19:00:00
11515	1479	12	9	2019-02-04 00:00:00
11516	1479	12	9	2019-07-09 23:30:00
11517	1479	12	9	2020-05-20 20:30:00
11518	1479	12	9	2020-01-16 16:30:00
11519	1480	9	13	2019-10-30 05:15:00
11520	1480	9	13	2019-01-04 10:15:00
11521	1480	9	13	2019-10-23 03:15:00
11522	1481	5	13	2018-03-14 12:30:00
11523	1481	5	13	2018-07-04 07:30:00
11524	1481	5	13	2018-07-26 01:00:00
11525	1481	5	13	2018-01-25 07:15:00
11526	1481	5	13	2017-04-17 03:00:00
11527	1481	5	13	2017-06-11 00:00:00
11528	1481	5	13	2017-03-27 04:30:00
11529	1481	5	13	2018-08-05 16:15:00
11530	1482	5	19	2018-11-25 14:45:00
11531	1482	5	19	2019-08-23 11:00:00
11532	1482	5	19	2019-05-20 18:30:00
11533	1482	5	19	2019-06-16 07:45:00
11534	1482	5	19	2019-02-16 09:00:00
11535	1482	5	19	2018-08-14 04:15:00
11536	1482	5	19	2018-09-13 16:45:00
11537	1482	5	19	2019-02-22 13:15:00
11538	1482	5	19	2020-02-05 14:30:00
11539	1483	9	7	2019-05-12 07:15:00
11540	1483	9	7	2018-08-11 22:45:00
11541	1483	9	7	2018-06-20 20:00:00
11542	1483	9	7	2019-09-04 02:00:00
11543	1483	9	7	2019-08-30 21:00:00
11544	1483	9	7	2018-03-06 10:15:00
11545	1484	12	1	2019-03-05 23:15:00
11546	1484	12	1	2019-09-23 17:00:00
11547	1484	12	1	2019-07-05 09:15:00
11548	1485	5	2	2018-11-20 12:45:00
11549	1485	5	2	2019-09-01 08:00:00
11550	1485	5	2	2018-12-08 01:15:00
11551	1485	5	2	2019-05-16 16:45:00
11552	1485	5	2	2019-11-01 13:00:00
11553	1485	5	2	2018-09-02 07:45:00
11554	1486	1	7	2020-12-14 01:45:00
11555	1486	1	7	2020-09-08 01:30:00
11556	1486	1	7	2020-12-09 19:45:00
11557	1486	1	7	2019-11-26 02:15:00
11558	1486	1	7	2020-04-02 17:00:00
11559	1486	1	7	2019-03-22 10:15:00
11560	1486	1	7	2021-02-08 14:15:00
11561	1486	1	7	2019-09-04 18:00:00
11562	1486	1	7	2019-10-28 17:30:00
11563	1486	1	7	2020-10-04 06:45:00
11564	1486	1	7	2019-09-20 07:00:00
11565	1486	1	7	2019-04-25 01:30:00
11566	1486	1	7	2019-04-19 15:30:00
11567	1487	10	4	2019-12-24 01:00:00
11568	1487	10	4	2020-02-19 12:15:00
11569	1487	10	4	2020-09-29 06:00:00
11570	1487	10	4	2019-09-16 03:30:00
11571	1487	10	4	2021-02-18 03:30:00
11572	1487	10	4	2020-10-27 13:30:00
11573	1487	10	4	2020-04-12 04:30:00
11574	1487	10	4	2020-08-12 20:15:00
11575	1487	10	4	2021-03-09 11:30:00
11576	1487	10	4	2021-02-24 16:30:00
11577	1487	10	4	2021-01-15 10:45:00
11578	1487	10	4	2020-09-18 03:15:00
11579	1487	10	4	2020-02-22 02:30:00
11580	1487	10	4	2019-11-18 21:30:00
11581	1487	10	4	2020-12-24 12:15:00
11582	1488	2	20	2019-01-03 20:00:00
11583	1488	2	20	2019-01-09 21:30:00
11584	1488	2	20	2019-01-06 01:45:00
11585	1488	2	20	2018-06-19 17:30:00
11586	1488	2	20	2019-02-11 21:45:00
11587	1488	2	20	2018-04-26 07:15:00
11588	1488	2	20	2019-05-09 16:15:00
11589	1488	2	20	2019-06-07 15:45:00
11590	1488	2	20	2018-08-29 19:45:00
11591	1488	2	20	2019-05-19 04:45:00
11592	1488	2	20	2018-07-04 23:00:00
11593	1488	2	20	2018-06-14 12:15:00
11594	1488	2	20	2018-11-22 03:45:00
11595	1488	2	20	2017-11-04 09:30:00
11596	1489	17	11	2021-06-15 21:00:00
11597	1489	17	11	2020-10-18 06:45:00
11598	1489	17	11	2020-10-18 09:30:00
11599	1489	17	11	2019-12-07 07:30:00
11600	1489	17	11	2021-05-30 14:00:00
11601	1489	17	11	2021-01-19 09:15:00
11602	1489	17	11	2020-02-05 06:45:00
11603	1489	17	11	2020-02-21 06:30:00
11604	1489	17	11	2021-02-03 22:45:00
11605	1489	17	11	2020-08-25 15:00:00
11606	1489	17	11	2020-02-10 18:30:00
11607	1489	17	11	2020-05-30 00:15:00
11608	1489	17	11	2020-05-12 07:00:00
11609	1489	17	11	2021-11-21 04:45:00
11610	1490	20	2	2018-07-28 13:30:00
11611	1490	20	2	2018-05-17 14:30:00
11612	1490	20	2	2018-03-22 06:00:00
11613	1490	20	2	2019-07-04 01:30:00
11614	1491	13	13	2018-12-07 22:15:00
11615	1491	13	13	2018-02-10 23:00:00
11616	1491	13	13	2019-07-09 05:15:00
11617	1491	13	13	2019-05-12 19:45:00
11618	1491	13	13	2018-08-27 19:45:00
11619	1491	13	13	2019-02-01 14:30:00
11620	1492	3	3	2019-04-10 06:30:00
11621	1493	8	11	2020-03-16 05:15:00
11622	1493	8	11	2021-07-02 23:00:00
11623	1493	8	11	2020-08-17 09:30:00
11624	1493	8	11	2020-05-15 17:15:00
11625	1494	10	17	2020-08-09 22:00:00
11626	1494	10	17	2020-01-12 12:00:00
11627	1494	10	17	2019-08-20 03:00:00
11628	1494	10	17	2020-09-01 02:45:00
11629	1494	10	17	2020-04-10 11:15:00
11630	1494	10	17	2020-11-16 18:00:00
11631	1494	10	17	2020-01-10 01:45:00
11632	1494	10	17	2019-06-30 05:00:00
11633	1494	10	17	2020-01-11 08:00:00
11634	1494	10	17	2020-11-26 02:30:00
11635	1495	20	6	2018-05-14 19:30:00
11636	1495	20	6	2019-02-04 09:00:00
11637	1495	20	6	2017-09-10 14:00:00
11638	1495	20	6	2019-05-18 00:45:00
11639	1495	20	6	2018-07-13 20:30:00
11640	1495	20	6	2018-07-11 12:30:00
11641	1495	20	6	2018-04-27 08:00:00
11642	1495	20	6	2018-05-08 08:30:00
11643	1495	20	6	2019-04-01 11:30:00
11644	1495	20	6	2019-02-24 14:00:00
11645	1496	19	10	2019-05-09 09:00:00
11646	1496	19	10	2019-06-11 20:30:00
11647	1496	19	10	2020-03-29 08:00:00
11648	1496	19	10	2020-03-30 05:00:00
11649	1496	19	10	2020-07-14 02:00:00
11650	1496	19	10	2020-02-04 04:15:00
11651	1496	19	10	2019-11-27 23:30:00
11652	1496	19	10	2020-02-25 02:15:00
11653	1496	19	10	2019-04-15 22:30:00
11654	1496	19	10	2019-07-30 08:15:00
11655	1496	19	10	2019-09-07 05:30:00
11656	1496	19	10	2019-01-26 13:30:00
11657	1496	19	10	2020-08-25 04:15:00
11658	1496	19	10	2019-09-29 16:30:00
11659	1496	19	10	2019-01-26 12:00:00
11660	1497	10	11	2019-09-20 20:15:00
11661	1498	5	2	2019-06-22 23:15:00
11662	1498	5	2	2018-03-29 01:30:00
11663	1498	5	2	2019-08-23 08:15:00
11664	1499	19	1	2019-12-20 21:15:00
11665	1499	19	1	2021-01-01 04:00:00
11666	1499	19	1	2020-11-26 22:00:00
11667	1499	19	1	2020-01-24 00:00:00
11668	1499	19	1	2020-12-14 08:30:00
11669	1499	19	1	2019-02-18 09:45:00
11670	1499	19	1	2019-08-25 20:00:00
11671	1499	19	1	2020-04-19 13:30:00
11672	1499	19	1	2019-12-10 14:00:00
11673	1499	19	1	2019-10-07 05:00:00
11674	1499	19	1	2019-07-20 13:00:00
11675	1499	19	1	2020-12-17 23:15:00
11676	1499	19	1	2019-10-09 04:15:00
11677	1499	19	1	2019-09-10 19:30:00
11678	1500	2	10	2019-12-09 10:30:00
11679	1500	2	10	2019-11-26 18:00:00
11680	1500	2	10	2020-01-18 12:45:00
11681	1500	2	10	2020-04-05 02:45:00
11682	1500	2	10	2019-11-04 10:30:00
11683	1500	2	10	2019-08-14 13:30:00
11684	1500	2	10	2019-10-11 22:15:00
11685	1500	2	10	2019-05-06 10:00:00
11686	1500	2	10	2019-06-09 03:15:00
11687	1500	2	10	2018-08-19 02:00:00
11688	1500	2	10	2018-09-13 08:15:00
11689	1500	2	10	2019-10-28 23:00:00
11690	1500	2	10	2019-09-14 07:45:00
11691	1501	5	20	2019-09-05 17:00:00
11692	1502	13	20	2021-01-06 19:15:00
11693	1502	13	20	2020-08-24 16:15:00
11694	1502	13	20	2020-12-21 16:45:00
11695	1502	13	20	2021-05-25 06:00:00
11696	1502	13	20	2020-12-18 03:45:00
11697	1502	13	20	2020-02-04 12:45:00
11698	1503	12	1	2019-04-09 07:00:00
11699	1503	12	1	2018-11-29 07:30:00
11700	1503	12	1	2018-05-12 09:30:00
11701	1504	17	2	2020-11-26 04:30:00
11702	1504	17	2	2019-08-10 23:15:00
11703	1504	17	2	2019-09-08 01:30:00
11704	1504	17	2	2021-03-30 18:30:00
11705	1504	17	2	2021-03-08 04:00:00
11706	1504	17	2	2021-05-15 14:00:00
11707	1504	17	2	2020-11-24 21:45:00
11708	1504	17	2	2020-10-30 10:45:00
11709	1504	17	2	2020-10-19 14:15:00
11710	1504	17	2	2019-07-24 04:30:00
11711	1504	17	2	2019-11-05 01:00:00
11712	1504	17	2	2020-12-29 06:30:00
11713	1505	3	9	2019-11-15 13:15:00
11714	1505	3	9	2019-04-24 23:30:00
11715	1505	3	9	2020-04-17 08:45:00
11716	1505	3	9	2020-07-12 21:30:00
11717	1505	3	9	2020-03-02 23:45:00
11718	1505	3	9	2020-12-17 16:30:00
11719	1505	3	9	2020-02-21 11:00:00
11720	1505	3	9	2019-12-08 17:00:00
11721	1505	3	9	2020-12-09 22:45:00
11722	1506	15	9	2019-09-23 23:45:00
11723	1506	15	9	2018-10-22 09:30:00
11724	1506	15	9	2019-08-20 18:30:00
11725	1506	15	9	2019-06-01 02:30:00
11726	1506	15	9	2018-10-19 10:15:00
11727	1506	15	9	2019-05-25 15:30:00
11728	1506	15	9	2019-12-02 00:30:00
11729	1506	15	9	2019-10-10 09:00:00
11730	1506	15	9	2018-06-15 09:45:00
11731	1506	15	9	2019-04-08 01:45:00
11732	1506	15	9	2020-02-23 22:30:00
11733	1506	15	9	2018-03-06 09:00:00
11734	1506	15	9	2019-12-18 08:00:00
11735	1506	15	9	2018-06-14 04:00:00
11736	1506	15	9	2018-12-01 10:15:00
11737	1507	13	2	2018-12-02 02:45:00
11738	1507	13	2	2019-06-07 19:30:00
11739	1507	13	2	2018-07-21 13:15:00
11740	1507	13	2	2018-03-18 11:00:00
11741	1507	13	2	2017-12-08 10:15:00
11742	1507	13	2	2018-02-03 11:00:00
11743	1507	13	2	2018-11-03 11:30:00
11744	1507	13	2	2019-07-03 13:30:00
11745	1507	13	2	2017-09-29 10:30:00
11746	1508	1	17	2020-01-13 10:30:00
11747	1509	19	1	2021-03-25 11:30:00
11748	1510	14	19	2021-01-19 03:00:00
11749	1510	14	19	2020-01-09 12:30:00
11750	1510	14	19	2020-07-14 08:00:00
11751	1510	14	19	2020-09-11 13:45:00
11752	1510	14	19	2020-03-29 20:45:00
11753	1510	14	19	2021-05-25 13:15:00
11754	1510	14	19	2019-08-01 20:30:00
11755	1510	14	19	2021-03-07 06:15:00
11756	1511	3	17	2021-06-05 22:45:00
11757	1511	3	17	2021-05-26 23:00:00
11758	1511	3	17	2020-12-17 18:00:00
11759	1511	3	17	2020-04-07 14:15:00
11760	1511	3	17	2021-05-03 23:45:00
11761	1511	3	17	2021-09-11 18:15:00
11762	1511	3	17	2020-03-29 20:00:00
11763	1511	3	17	2021-09-28 18:15:00
11764	1512	15	11	2019-05-06 00:30:00
11765	1512	15	11	2019-02-12 13:45:00
11766	1512	15	11	2018-02-03 20:30:00
11767	1513	3	3	2020-04-14 14:45:00
11768	1513	3	3	2019-07-03 09:30:00
11769	1513	3	3	2020-01-25 10:45:00
11770	1513	3	3	2018-11-19 20:45:00
11771	1513	3	3	2019-08-03 15:15:00
11772	1513	3	3	2019-07-23 16:15:00
11773	1514	18	20	2017-10-29 12:45:00
11774	1514	18	20	2018-07-26 22:45:00
11775	1514	18	20	2017-10-17 17:15:00
11776	1514	18	20	2018-04-29 12:15:00
11777	1514	18	20	2017-09-02 19:15:00
11778	1514	18	20	2019-01-03 21:15:00
11779	1515	3	2	2018-12-02 12:00:00
11780	1515	3	2	2019-03-11 02:00:00
11781	1515	3	2	2018-08-16 07:30:00
11782	1515	3	2	2018-11-27 07:30:00
11783	1515	3	2	2018-09-27 12:00:00
11784	1516	2	10	2018-05-26 04:30:00
11785	1516	2	10	2018-06-05 16:45:00
11786	1516	2	10	2018-01-01 08:15:00
11787	1517	18	13	2019-05-20 19:00:00
11788	1517	18	13	2017-10-14 13:45:00
11789	1517	18	13	2018-03-24 03:15:00
11790	1517	18	13	2017-08-12 06:45:00
11791	1517	18	13	2019-04-23 10:00:00
11792	1517	18	13	2017-08-28 07:30:00
11793	1517	18	13	2018-05-18 16:00:00
11794	1517	18	13	2018-03-01 12:45:00
11795	1517	18	13	2017-08-08 13:15:00
11796	1517	18	13	2018-07-24 14:00:00
11797	1517	18	13	2018-12-16 23:30:00
11798	1518	10	7	2019-11-13 01:30:00
11799	1518	10	7	2021-04-26 23:45:00
11800	1518	10	7	2020-02-03 15:30:00
11801	1518	10	7	2020-10-15 05:45:00
11802	1518	10	7	2019-05-06 17:15:00
11803	1518	10	7	2019-11-21 11:15:00
11804	1519	14	9	2018-12-25 09:00:00
11805	1520	14	11	2020-11-23 08:30:00
11806	1520	14	11	2020-03-28 05:45:00
11807	1520	14	11	2020-04-30 09:00:00
11808	1520	14	11	2020-11-28 12:00:00
11809	1520	14	11	2020-09-30 09:45:00
11810	1520	14	11	2021-02-11 16:15:00
11811	1520	14	11	2021-03-17 07:30:00
11812	1520	14	11	2020-11-07 17:15:00
11813	1520	14	11	2020-07-20 08:30:00
11814	1520	14	11	2021-05-20 17:45:00
11815	1520	14	11	2020-08-01 10:15:00
11816	1520	14	11	2021-01-10 19:15:00
11817	1521	3	20	2017-09-09 03:15:00
11818	1521	3	20	2018-07-06 13:45:00
11819	1521	3	20	2019-06-15 10:15:00
11820	1521	3	20	2017-11-01 11:00:00
11821	1521	3	20	2018-06-01 14:00:00
11822	1521	3	20	2019-02-08 02:45:00
11823	1521	3	20	2018-07-25 04:30:00
11824	1521	3	20	2018-07-16 12:45:00
11825	1522	6	19	2021-01-12 15:00:00
11826	1522	6	19	2020-08-08 14:45:00
11827	1522	6	19	2020-06-01 14:00:00
11828	1523	18	18	2017-12-01 11:45:00
11829	1523	18	18	2018-12-06 07:30:00
11830	1523	18	18	2018-03-29 11:30:00
11831	1523	18	18	2019-03-14 20:30:00
11832	1523	18	18	2018-03-13 08:00:00
11833	1523	18	18	2019-03-30 06:00:00
11834	1523	18	18	2017-12-11 17:30:00
11835	1523	18	18	2019-04-10 04:15:00
11836	1524	2	6	2021-01-13 08:45:00
11837	1524	2	6	2020-02-21 07:45:00
11838	1524	2	6	2019-05-24 05:30:00
11839	1524	2	6	2020-06-24 15:30:00
11840	1524	2	6	2020-06-30 00:30:00
11841	1525	13	9	2020-05-26 07:30:00
11842	1525	13	9	2019-05-26 17:30:00
11843	1525	13	9	2018-12-06 00:45:00
11844	1525	13	9	2020-01-23 19:00:00
11845	1525	13	9	2019-11-24 07:30:00
11846	1525	13	9	2018-12-13 00:00:00
11847	1525	13	9	2019-04-21 04:30:00
11848	1525	13	9	2020-07-04 03:15:00
11849	1525	13	9	2019-01-22 07:15:00
11850	1525	13	9	2019-10-24 23:15:00
11851	1525	13	9	2018-11-25 18:15:00
11852	1526	14	9	2018-09-20 17:00:00
11853	1526	14	9	2020-06-16 02:45:00
11854	1527	10	15	2021-05-21 11:30:00
11855	1528	14	14	2020-12-23 02:45:00
11856	1528	14	14	2020-10-18 08:45:00
11857	1528	14	14	2019-05-05 03:30:00
11858	1528	14	14	2020-03-23 17:15:00
11859	1529	20	13	2019-12-02 17:00:00
11860	1529	20	13	2020-10-27 12:45:00
11861	1529	20	13	2020-03-15 18:15:00
11862	1529	20	13	2020-07-28 03:00:00
11863	1529	20	13	2021-08-17 02:30:00
11864	1529	20	13	2021-10-22 01:30:00
11865	1529	20	13	2021-01-02 10:15:00
11866	1529	20	13	2021-11-05 08:00:00
11867	1529	20	13	2020-06-13 11:45:00
11868	1529	20	13	2020-10-10 19:15:00
11869	1529	20	13	2021-08-10 11:45:00
11870	1530	9	15	2017-09-08 02:00:00
11871	1530	9	15	2019-02-21 20:30:00
11872	1530	9	15	2019-03-05 11:15:00
11873	1530	9	15	2019-07-16 21:30:00
11874	1530	9	15	2019-06-10 09:15:00
11875	1530	9	15	2019-05-11 01:30:00
11876	1530	9	15	2018-04-27 21:00:00
11877	1530	9	15	2018-12-15 03:30:00
11878	1530	9	15	2018-03-20 19:15:00
11879	1530	9	15	2019-07-03 09:45:00
11880	1530	9	15	2018-11-08 17:00:00
11881	1530	9	15	2018-08-18 00:15:00
11882	1530	9	15	2018-09-02 10:00:00
11883	1530	9	15	2017-09-21 13:15:00
11884	1531	20	1	2021-03-03 16:45:00
11885	1531	20	1	2020-12-15 23:45:00
11886	1531	20	1	2019-07-14 00:45:00
11887	1531	20	1	2019-07-20 22:30:00
11888	1531	20	1	2020-07-02 19:15:00
11889	1531	20	1	2019-06-24 14:30:00
11890	1531	20	1	2019-05-18 03:30:00
11891	1531	20	1	2020-03-18 12:45:00
11892	1532	1	11	2018-09-07 21:30:00
11893	1532	1	11	2018-12-24 02:15:00
11894	1532	1	11	2019-12-09 12:00:00
11895	1532	1	11	2019-12-12 16:15:00
11896	1532	1	11	2018-08-16 17:00:00
11897	1532	1	11	2018-08-06 04:15:00
11898	1532	1	11	2018-10-03 04:00:00
11899	1532	1	11	2019-12-08 04:00:00
11900	1532	1	11	2019-07-08 21:00:00
11901	1532	1	11	2019-05-08 07:30:00
11902	1532	1	11	2018-05-01 20:30:00
11903	1532	1	11	2019-09-18 07:30:00
11904	1532	1	11	2019-12-16 16:45:00
11905	1532	1	11	2020-02-13 17:30:00
11906	1533	6	14	2018-02-08 23:00:00
11907	1533	6	14	2017-10-20 02:00:00
11908	1534	11	12	2019-10-30 11:00:00
11909	1534	11	12	2020-06-14 07:00:00
11910	1534	11	12	2019-06-21 22:30:00
11911	1534	11	12	2019-11-20 10:30:00
11912	1534	11	12	2020-10-19 02:00:00
11913	1534	11	12	2019-06-23 20:30:00
11914	1534	11	12	2019-09-10 00:00:00
11915	1534	11	12	2020-05-07 16:45:00
11916	1534	11	12	2019-06-15 07:00:00
11917	1534	11	12	2019-09-24 21:45:00
11918	1535	3	18	2018-03-30 16:45:00
11919	1535	3	18	2018-06-13 08:30:00
11920	1535	3	18	2017-11-14 10:30:00
11921	1535	3	18	2017-08-30 19:30:00
11922	1535	3	18	2019-02-26 00:15:00
11923	1535	3	18	2018-09-05 13:30:00
11924	1535	3	18	2017-10-23 16:00:00
11925	1535	3	18	2018-06-14 13:15:00
11926	1535	3	18	2018-10-08 18:00:00
11927	1535	3	18	2018-10-18 12:15:00
11928	1535	3	18	2017-10-09 12:00:00
11929	1535	3	18	2017-08-24 09:45:00
11930	1535	3	18	2018-10-05 19:45:00
11931	1536	6	16	2017-06-02 10:45:00
11932	1536	6	16	2017-08-21 10:30:00
11933	1536	6	16	2017-06-06 11:45:00
11934	1536	6	16	2018-09-05 10:45:00
11935	1537	14	14	2019-06-16 06:15:00
11936	1538	9	9	2020-11-26 23:30:00
11937	1538	9	9	2020-07-02 19:30:00
11938	1538	9	9	2019-01-30 08:30:00
11939	1538	9	9	2019-11-12 07:45:00
11940	1538	9	9	2020-12-17 06:00:00
11941	1538	9	9	2020-01-24 00:30:00
11942	1538	9	9	2020-10-15 01:15:00
11943	1538	9	9	2019-09-16 17:15:00
11944	1538	9	9	2020-09-02 14:30:00
11945	1538	9	9	2020-01-29 19:45:00
11946	1538	9	9	2020-06-29 14:30:00
11947	1538	9	9	2019-03-03 11:45:00
11948	1538	9	9	2020-09-10 04:15:00
11949	1538	9	9	2019-07-11 12:15:00
11950	1539	15	20	2019-11-18 00:15:00
11951	1539	15	20	2020-06-06 11:15:00
11952	1539	15	20	2021-06-16 17:45:00
11953	1539	15	20	2019-09-21 19:00:00
11954	1539	15	20	2021-04-02 00:00:00
11955	1539	15	20	2020-01-26 04:45:00
11956	1539	15	20	2019-09-18 23:00:00
11957	1539	15	20	2020-09-22 16:00:00
11958	1539	15	20	2020-02-06 09:15:00
11959	1540	15	3	2020-12-13 06:30:00
11960	1540	15	3	2019-12-14 17:30:00
11961	1540	15	3	2021-03-06 06:45:00
11962	1540	15	3	2020-07-14 08:45:00
11963	1540	15	3	2020-09-27 11:30:00
11964	1540	15	3	2021-02-02 08:30:00
11965	1540	15	3	2020-05-14 17:45:00
11966	1540	15	3	2021-01-25 06:45:00
11967	1540	15	3	2020-03-25 21:45:00
11968	1540	15	3	2019-07-06 19:15:00
11969	1541	8	4	2018-07-04 16:00:00
11970	1541	8	4	2017-11-16 05:00:00
11971	1541	8	4	2017-07-27 12:15:00
11972	1541	8	4	2018-05-04 13:30:00
11973	1542	7	19	2020-08-26 19:45:00
11974	1542	7	19	2019-06-12 14:15:00
11975	1542	7	19	2020-07-10 10:00:00
11976	1542	7	19	2020-12-13 10:15:00
11977	1542	7	19	2021-04-25 04:00:00
11978	1542	7	19	2020-03-13 18:15:00
11979	1542	7	19	2021-04-21 16:45:00
11980	1543	6	13	2019-05-29 00:30:00
11981	1543	6	13	2018-11-20 10:30:00
11982	1543	6	13	2018-10-12 03:45:00
11983	1543	6	13	2019-02-09 07:30:00
11984	1543	6	13	2019-08-30 02:00:00
11985	1543	6	13	2019-06-19 10:45:00
11986	1543	6	13	2018-01-17 22:30:00
11987	1543	6	13	2019-07-17 09:30:00
11988	1543	6	13	2018-12-01 15:30:00
11989	1543	6	13	2018-12-14 14:45:00
11990	1543	6	13	2018-05-30 10:00:00
11991	1543	6	13	2018-12-12 03:45:00
11992	1543	6	13	2019-05-29 13:00:00
11993	1544	12	17	2020-08-10 23:30:00
11994	1545	14	7	2019-08-08 00:45:00
11995	1545	14	7	2018-12-23 12:00:00
11996	1545	14	7	2019-10-03 03:30:00
11997	1545	14	7	2019-12-29 18:30:00
11998	1545	14	7	2019-05-24 02:30:00
11999	1545	14	7	2018-01-05 13:30:00
12000	1545	14	7	2019-07-29 15:15:00
12001	1545	14	7	2019-03-06 03:15:00
12002	1545	14	7	2018-09-16 07:45:00
12003	1545	14	7	2018-07-03 15:15:00
12004	1545	14	7	2018-07-08 14:00:00
12005	1546	10	15	2018-09-09 12:30:00
12006	1546	10	15	2018-07-09 10:45:00
12007	1546	10	15	2017-12-18 10:45:00
12008	1546	10	15	2017-02-16 09:15:00
12009	1546	10	15	2018-02-16 02:30:00
12010	1546	10	15	2018-07-15 06:00:00
12011	1546	10	15	2018-12-22 15:15:00
12012	1547	11	10	2019-09-23 09:30:00
12013	1548	4	4	2019-06-04 01:30:00
12014	1548	4	4	2018-07-05 06:45:00
12015	1548	4	4	2019-05-10 03:30:00
12016	1548	4	4	2018-09-16 01:00:00
12017	1548	4	4	2018-04-28 05:45:00
12018	1548	4	4	2019-06-15 09:30:00
12019	1548	4	4	2018-07-08 13:00:00
12020	1549	16	11	2019-08-26 23:45:00
12021	1549	16	11	2019-01-04 09:30:00
12022	1549	16	11	2019-04-15 01:45:00
12023	1549	16	11	2019-11-11 15:30:00
12024	1549	16	11	2019-11-05 04:00:00
12025	1549	16	11	2019-07-19 19:30:00
12026	1549	16	11	2018-08-05 14:15:00
12027	1549	16	11	2018-12-14 03:00:00
12028	1549	16	11	2018-04-25 11:00:00
12029	1549	16	11	2017-12-15 21:15:00
12030	1550	17	10	2020-05-02 17:45:00
12031	1550	17	10	2020-01-15 22:30:00
12032	1550	17	10	2020-06-20 13:30:00
12033	1550	17	10	2021-03-24 22:45:00
12034	1550	17	10	2020-06-01 17:00:00
12035	1550	17	10	2021-05-06 01:15:00
12036	1550	17	10	2021-02-13 09:45:00
12037	1550	17	10	2021-01-11 05:00:00
12038	1550	17	10	2020-02-18 18:00:00
12039	1550	17	10	2020-01-20 05:15:00
12040	1551	19	15	2018-01-19 21:30:00
12041	1551	19	15	2018-12-08 19:45:00
12042	1551	19	15	2019-02-26 03:00:00
12043	1552	13	18	2020-04-18 07:15:00
12044	1553	11	16	2021-02-01 04:00:00
12045	1554	8	18	2019-03-04 15:30:00
12046	1554	8	18	2020-02-27 09:45:00
12047	1554	8	18	2018-10-15 00:15:00
12048	1554	8	18	2019-10-05 21:15:00
12049	1554	8	18	2019-07-04 14:30:00
12050	1555	20	16	2018-10-18 06:15:00
12051	1555	20	16	2019-06-18 06:45:00
12052	1555	20	16	2019-03-21 06:15:00
12053	1555	20	16	2017-12-12 09:00:00
12054	1555	20	16	2018-05-13 20:45:00
12055	1555	20	16	2019-02-24 15:15:00
12056	1555	20	16	2018-10-15 17:15:00
12057	1555	20	16	2019-09-09 05:00:00
12058	1555	20	16	2019-01-29 08:15:00
12059	1555	20	16	2018-03-20 07:30:00
12060	1556	9	6	2019-07-11 05:00:00
12061	1556	9	6	2018-10-24 16:00:00
12062	1556	9	6	2019-01-23 18:00:00
12063	1556	9	6	2018-12-15 05:45:00
12064	1556	9	6	2019-08-01 15:15:00
12065	1556	9	6	2020-03-08 17:15:00
12066	1556	9	6	2020-07-18 21:30:00
12067	1556	9	6	2020-06-16 16:30:00
12068	1556	9	6	2019-11-08 15:45:00
12069	1556	9	6	2020-05-19 02:00:00
12070	1556	9	6	2020-04-10 01:45:00
12071	1557	17	8	2018-07-08 20:00:00
12072	1557	17	8	2019-03-21 23:45:00
12073	1557	17	8	2018-12-04 04:15:00
12074	1557	17	8	2019-08-08 13:00:00
12075	1557	17	8	2018-01-20 20:00:00
12076	1557	17	8	2019-01-26 23:15:00
12077	1557	17	8	2018-06-14 12:15:00
12078	1557	17	8	2019-01-18 19:00:00
12079	1557	17	8	2018-04-07 09:30:00
12080	1557	17	8	2018-07-09 18:45:00
12081	1558	10	10	2019-03-13 09:30:00
12082	1558	10	10	2020-11-13 16:45:00
12083	1558	10	10	2019-05-01 23:30:00
12084	1558	10	10	2020-07-16 21:15:00
12085	1558	10	10	2020-11-21 11:15:00
12086	1559	13	13	2019-04-19 00:00:00
12087	1559	13	13	2018-09-06 09:45:00
12088	1559	13	13	2018-10-20 08:30:00
12089	1559	13	13	2019-02-19 12:00:00
12090	1559	13	13	2018-10-29 21:45:00
12091	1559	13	13	2018-08-08 17:30:00
12092	1559	13	13	2018-08-14 17:15:00
12093	1559	13	13	2019-01-16 12:45:00
12094	1559	13	13	2018-12-05 11:15:00
12095	1559	13	13	2019-06-22 18:00:00
12096	1559	13	13	2018-03-02 14:30:00
12097	1559	13	13	2019-03-26 22:45:00
12098	1559	13	13	2018-11-30 10:15:00
12099	1559	13	13	2019-07-28 06:30:00
12100	1560	14	7	2019-04-29 22:45:00
12101	1560	14	7	2019-09-25 12:00:00
12102	1560	14	7	2019-12-04 03:15:00
12103	1560	14	7	2020-04-07 19:45:00
12104	1560	14	7	2019-10-28 08:15:00
12105	1560	14	7	2019-07-30 10:15:00
12106	1560	14	7	2020-01-02 07:30:00
12107	1560	14	7	2020-03-24 19:00:00
12108	1560	14	7	2018-11-01 02:00:00
12109	1560	14	7	2019-12-03 07:15:00
12110	1560	14	7	2019-09-03 01:00:00
12111	1561	17	2	2021-01-02 04:00:00
12112	1561	17	2	2020-03-22 16:45:00
12113	1561	17	2	2019-11-21 18:15:00
12114	1561	17	2	2021-04-11 14:30:00
12115	1561	17	2	2019-12-23 07:45:00
12116	1561	17	2	2020-05-26 02:15:00
12117	1561	17	2	2020-01-20 13:00:00
12118	1561	17	2	2021-06-23 09:30:00
12119	1561	17	2	2020-01-21 12:30:00
12120	1561	17	2	2019-09-13 00:15:00
12121	1561	17	2	2020-07-02 00:15:00
12122	1561	17	2	2019-07-09 20:15:00
12123	1561	17	2	2021-04-11 05:00:00
12124	1561	17	2	2020-01-14 00:30:00
12125	1561	17	2	2020-08-22 06:30:00
12126	1562	16	15	2019-05-16 19:15:00
12127	1562	16	15	2019-06-21 00:15:00
12128	1562	16	15	2019-06-12 11:15:00
12129	1562	16	15	2017-10-18 04:30:00
12130	1562	16	15	2019-03-04 13:30:00
12131	1562	16	15	2017-12-23 14:15:00
12132	1562	16	15	2019-07-23 23:30:00
12133	1563	18	11	2017-09-19 06:00:00
12134	1563	18	11	2017-05-16 10:30:00
12135	1563	18	11	2017-10-27 13:45:00
12136	1564	11	15	2019-04-26 00:30:00
12137	1564	11	15	2020-11-12 04:15:00
12138	1564	11	15	2020-02-03 13:30:00
12139	1565	16	18	2019-06-25 01:15:00
12140	1565	16	18	2018-09-13 15:45:00
12141	1565	16	18	2018-04-24 00:00:00
12142	1566	17	20	2019-03-15 17:00:00
12143	1566	17	20	2018-03-07 17:30:00
12144	1566	17	20	2017-07-04 14:15:00
12145	1566	17	20	2018-07-30 15:45:00
12146	1566	17	20	2019-02-04 22:45:00
12147	1566	17	20	2017-08-11 07:45:00
12148	1566	17	20	2019-02-04 12:45:00
12149	1566	17	20	2019-03-22 18:00:00
12150	1566	17	20	2017-09-04 22:45:00
12151	1566	17	20	2018-12-11 09:30:00
12152	1567	8	17	2021-03-02 00:45:00
12153	1568	11	8	2021-07-14 22:45:00
12154	1568	11	8	2021-07-01 00:30:00
12155	1568	11	8	2020-12-09 14:45:00
12156	1568	11	8	2020-01-05 19:00:00
12157	1568	11	8	2021-02-26 06:45:00
12158	1568	11	8	2019-08-01 20:30:00
12159	1568	11	8	2021-07-12 07:00:00
12160	1568	11	8	2020-06-14 22:30:00
12161	1568	11	8	2021-02-19 14:30:00
12162	1569	15	1	2021-07-03 23:30:00
12163	1569	15	1	2020-04-15 11:00:00
12164	1569	15	1	2020-11-15 22:45:00
12165	1570	1	8	2018-10-14 10:00:00
12166	1570	1	8	2018-04-23 00:15:00
12167	1570	1	8	2018-08-17 07:30:00
12168	1570	1	8	2018-06-19 13:15:00
12169	1570	1	8	2019-01-21 00:00:00
12170	1570	1	8	2017-06-25 02:00:00
12171	1570	1	8	2017-07-25 07:15:00
12172	1570	1	8	2019-01-01 02:00:00
12173	1570	1	8	2017-12-05 00:15:00
12174	1570	1	8	2018-04-15 12:45:00
12175	1570	1	8	2017-07-22 07:15:00
12176	1570	1	8	2018-05-27 01:00:00
12177	1571	15	3	2018-05-04 07:15:00
12178	1571	15	3	2018-05-24 09:00:00
12179	1571	15	3	2018-09-06 13:00:00
12180	1571	15	3	2019-07-23 05:45:00
12181	1571	15	3	2019-03-08 05:30:00
12182	1571	15	3	2019-08-26 15:45:00
12183	1571	15	3	2018-06-13 16:00:00
12184	1572	18	5	2019-06-23 06:00:00
12185	1573	7	3	2017-11-11 19:00:00
12186	1573	7	3	2017-07-01 19:00:00
12187	1573	7	3	2018-01-18 14:30:00
12188	1573	7	3	2017-08-04 06:30:00
12189	1573	7	3	2017-12-08 10:15:00
12190	1573	7	3	2018-02-11 21:30:00
12191	1573	7	3	2017-12-04 19:15:00
12192	1573	7	3	2017-08-05 12:30:00
12193	1573	7	3	2019-02-10 18:15:00
12194	1573	7	3	2017-11-12 06:45:00
12195	1573	7	3	2019-03-09 02:00:00
12196	1573	7	3	2018-02-04 16:30:00
12197	1573	7	3	2018-07-22 09:45:00
12198	1573	7	3	2018-04-09 07:45:00
12199	1574	10	4	2019-05-12 09:30:00
12200	1574	10	4	2017-12-08 09:45:00
12201	1574	10	4	2019-08-24 10:45:00
12202	1574	10	4	2019-02-12 09:00:00
12203	1574	10	4	2019-08-30 18:15:00
12204	1574	10	4	2018-06-18 19:45:00
12205	1574	10	4	2018-06-19 16:45:00
12206	1574	10	4	2018-02-10 00:15:00
12207	1574	10	4	2018-02-09 02:30:00
12208	1574	10	4	2018-11-24 07:15:00
12209	1574	10	4	2019-05-26 00:00:00
12210	1574	10	4	2017-12-09 00:15:00
12211	1574	10	4	2018-04-13 04:15:00
12212	1574	10	4	2019-03-05 19:30:00
12213	1574	10	4	2018-02-13 17:30:00
12214	1575	14	13	2020-04-10 08:30:00
12215	1575	14	13	2020-01-01 21:00:00
12216	1575	14	13	2019-06-18 20:15:00
12217	1575	14	13	2019-09-18 11:30:00
12218	1575	14	13	2018-09-03 05:15:00
12219	1575	14	13	2020-03-15 07:45:00
12220	1575	14	13	2018-11-18 04:30:00
12221	1575	14	13	2019-01-10 12:45:00
12222	1575	14	13	2019-05-28 16:45:00
12223	1575	14	13	2018-09-11 20:45:00
12224	1576	6	4	2019-08-14 21:15:00
12225	1576	6	4	2020-12-16 21:45:00
12226	1576	6	4	2020-05-22 04:00:00
12227	1576	6	4	2019-10-04 11:00:00
12228	1576	6	4	2019-05-15 01:45:00
12229	1576	6	4	2020-02-18 01:00:00
12230	1576	6	4	2020-04-21 23:00:00
12231	1576	6	4	2020-01-23 05:00:00
12232	1576	6	4	2019-02-17 10:00:00
12233	1577	17	11	2018-04-22 23:15:00
12234	1577	17	11	2018-10-29 17:45:00
12235	1577	17	11	2018-05-12 10:30:00
12236	1577	17	11	2018-07-13 08:30:00
12237	1577	17	11	2018-05-04 18:30:00
12238	1577	17	11	2019-01-17 09:00:00
12239	1577	17	11	2018-10-27 22:45:00
12240	1577	17	11	2018-07-02 23:00:00
12241	1577	17	11	2018-02-16 09:30:00
12242	1577	17	11	2017-12-18 02:15:00
12243	1578	10	19	2019-03-16 03:00:00
12244	1578	10	19	2020-07-19 23:00:00
12245	1578	10	19	2020-01-20 16:45:00
12246	1578	10	19	2020-02-25 04:30:00
12247	1578	10	19	2019-05-28 13:45:00
12248	1578	10	19	2020-05-04 17:30:00
12249	1579	15	11	2019-04-25 23:30:00
12250	1579	15	11	2018-04-07 03:45:00
12251	1579	15	11	2019-02-14 06:45:00
12252	1579	15	11	2018-11-29 01:30:00
12253	1580	7	20	2019-05-18 18:00:00
12254	1580	7	20	2019-07-04 06:45:00
12255	1580	7	20	2018-08-03 16:00:00
12256	1581	8	1	2019-10-04 07:15:00
12257	1581	8	1	2020-02-02 13:45:00
12258	1581	8	1	2020-06-19 08:45:00
12259	1581	8	1	2019-09-01 02:30:00
12260	1581	8	1	2019-08-08 21:30:00
12261	1581	8	1	2019-07-06 03:00:00
12262	1581	8	1	2020-05-10 16:45:00
12263	1581	8	1	2019-01-06 16:15:00
12264	1581	8	1	2020-05-24 08:15:00
12265	1581	8	1	2020-08-02 23:15:00
12266	1581	8	1	2020-05-19 14:45:00
12267	1581	8	1	2020-08-16 01:15:00
12268	1582	6	13	2020-08-20 21:30:00
12269	1582	6	13	2019-10-19 05:15:00
12270	1582	6	13	2019-10-09 11:00:00
12271	1582	6	13	2020-09-29 12:30:00
12272	1582	6	13	2021-02-11 08:15:00
12273	1582	6	13	2019-09-11 21:30:00
12274	1582	6	13	2020-05-14 09:30:00
12275	1582	6	13	2020-01-28 17:45:00
12276	1583	17	10	2020-08-23 09:15:00
12277	1583	17	10	2019-10-16 03:15:00
12278	1583	17	10	2020-12-09 06:30:00
12279	1583	17	10	2020-03-04 11:30:00
12280	1583	17	10	2020-06-17 06:30:00
12281	1583	17	10	2020-09-23 11:15:00
12282	1583	17	10	2021-03-05 14:00:00
12283	1583	17	10	2019-10-17 16:15:00
12284	1583	17	10	2020-09-09 12:30:00
12285	1583	17	10	2020-02-12 02:30:00
12286	1583	17	10	2019-11-02 05:45:00
12287	1583	17	10	2020-02-18 06:00:00
12288	1583	17	10	2019-12-19 14:30:00
12289	1583	17	10	2020-06-21 19:30:00
12290	1583	17	10	2020-05-13 10:00:00
12291	1584	11	20	2020-08-30 08:00:00
12292	1584	11	20	2018-12-02 10:45:00
12293	1584	11	20	2020-02-03 22:45:00
12294	1584	11	20	2018-10-28 13:45:00
12295	1584	11	20	2020-09-05 01:45:00
12296	1584	11	20	2020-06-13 22:45:00
12297	1584	11	20	2019-11-16 05:30:00
12298	1584	11	20	2019-08-09 04:30:00
12299	1584	11	20	2020-08-20 04:30:00
12300	1584	11	20	2019-01-09 05:15:00
12301	1584	11	20	2020-09-06 22:00:00
12302	1584	11	20	2019-12-12 20:30:00
12303	1584	11	20	2020-05-30 19:30:00
12304	1584	11	20	2020-06-10 21:45:00
12305	1585	13	15	2019-12-16 22:00:00
12306	1585	13	15	2019-10-16 07:15:00
12307	1585	13	15	2019-08-27 21:00:00
12308	1585	13	15	2019-02-05 05:15:00
12309	1585	13	15	2019-12-17 03:00:00
12310	1585	13	15	2020-05-09 23:30:00
12311	1585	13	15	2019-02-10 02:15:00
12312	1585	13	15	2019-09-14 03:15:00
12313	1585	13	15	2019-06-13 17:30:00
12314	1586	14	12	2017-11-12 11:45:00
12315	1586	14	12	2019-02-18 21:30:00
12316	1586	14	12	2018-10-03 03:00:00
12317	1587	11	8	2020-01-30 14:15:00
12318	1587	11	8	2019-05-09 18:45:00
12319	1587	11	8	2019-10-10 18:00:00
12320	1587	11	8	2019-12-05 21:30:00
12321	1587	11	8	2019-09-09 23:30:00
12322	1587	11	8	2020-04-14 00:30:00
12323	1587	11	8	2019-03-26 00:15:00
12324	1587	11	8	2019-11-27 02:15:00
12325	1587	11	8	2020-07-27 15:15:00
12326	1587	11	8	2019-05-23 06:00:00
12327	1587	11	8	2019-08-18 09:15:00
12328	1588	4	3	2018-12-02 07:30:00
12329	1588	4	3	2018-06-03 05:00:00
12330	1588	4	3	2019-01-07 20:30:00
12331	1588	4	3	2017-08-30 09:15:00
12332	1588	4	3	2019-05-22 14:45:00
12333	1588	4	3	2019-02-22 10:15:00
12334	1588	4	3	2018-04-05 01:30:00
12335	1588	4	3	2017-11-04 12:30:00
12336	1588	4	3	2018-06-01 14:15:00
12337	1588	4	3	2018-11-12 19:30:00
12338	1588	4	3	2018-03-01 12:45:00
12339	1588	4	3	2019-04-25 15:15:00
12340	1588	4	3	2018-08-29 04:30:00
12341	1588	4	3	2017-09-09 16:15:00
12342	1589	16	6	2021-01-22 15:30:00
12343	1589	16	6	2020-09-22 08:15:00
12344	1589	16	6	2020-01-09 01:00:00
12345	1589	16	6	2020-10-10 11:30:00
12346	1589	16	6	2020-07-24 18:45:00
12347	1589	16	6	2020-09-05 15:30:00
12348	1589	16	6	2021-06-21 04:00:00
12349	1589	16	6	2020-11-01 04:00:00
12350	1589	16	6	2020-08-16 21:30:00
12351	1589	16	6	2019-10-28 00:45:00
12352	1589	16	6	2020-12-14 10:00:00
12353	1590	20	2	2019-01-27 04:15:00
12354	1590	20	2	2019-12-13 08:00:00
12355	1590	20	2	2018-10-27 09:15:00
12356	1590	20	2	2020-01-02 18:00:00
12357	1590	20	2	2020-03-19 19:30:00
12358	1590	20	2	2019-07-29 03:30:00
12359	1590	20	2	2019-11-18 04:45:00
12360	1590	20	2	2020-05-05 03:45:00
12361	1590	20	2	2018-12-15 02:00:00
12362	1590	20	2	2018-11-05 07:00:00
12363	1590	20	2	2018-09-22 23:30:00
12364	1590	20	2	2020-03-23 00:30:00
12365	1590	20	2	2019-11-08 19:30:00
12366	1591	12	15	2020-05-26 01:15:00
12367	1591	12	15	2020-04-05 23:30:00
12368	1591	12	15	2020-09-27 17:30:00
12369	1591	12	15	2019-04-28 03:30:00
12370	1591	12	15	2020-05-14 16:30:00
12371	1591	12	15	2020-09-01 00:45:00
12372	1592	20	9	2020-03-01 04:30:00
12373	1593	10	3	2017-11-06 03:30:00
12374	1593	10	3	2018-09-08 07:00:00
12375	1593	10	3	2018-01-03 00:30:00
12376	1593	10	3	2018-07-09 01:15:00
12377	1593	10	3	2019-05-22 10:30:00
12378	1593	10	3	2018-02-06 06:45:00
12379	1593	10	3	2018-08-06 16:45:00
12380	1594	14	16	2018-07-28 11:30:00
12381	1594	14	16	2018-07-24 12:30:00
12382	1594	14	16	2017-12-11 06:00:00
12383	1594	14	16	2019-07-23 02:15:00
12384	1594	14	16	2017-11-21 16:00:00
12385	1594	14	16	2017-09-28 04:00:00
12386	1594	14	16	2019-02-21 20:45:00
12387	1594	14	16	2017-09-29 07:00:00
12388	1594	14	16	2019-01-24 18:30:00
12389	1594	14	16	2018-12-29 12:45:00
12390	1594	14	16	2017-11-29 13:15:00
12391	1595	4	2	2018-05-20 18:00:00
12392	1595	4	2	2017-10-25 04:00:00
12393	1595	4	2	2018-11-26 11:45:00
12394	1595	4	2	2018-06-24 22:45:00
12395	1595	4	2	2018-12-18 08:00:00
12396	1595	4	2	2017-08-26 09:30:00
12397	1595	4	2	2018-11-10 13:15:00
12398	1596	10	15	2020-03-16 10:00:00
12399	1596	10	15	2019-11-13 13:15:00
12400	1596	10	15	2021-01-16 15:00:00
12401	1596	10	15	2019-11-26 07:30:00
12402	1596	10	15	2020-06-18 20:45:00
12403	1596	10	15	2021-10-08 08:30:00
12404	1596	10	15	2020-02-12 04:45:00
12405	1596	10	15	2020-09-09 09:30:00
12406	1597	3	8	2018-03-16 14:15:00
12407	1597	3	8	2018-05-26 08:30:00
12408	1597	3	8	2018-08-02 17:30:00
12409	1597	3	8	2017-10-11 05:00:00
12410	1597	3	8	2018-02-17 01:45:00
12411	1597	3	8	2017-05-02 03:45:00
12412	1597	3	8	2019-03-16 18:15:00
12413	1597	3	8	2018-04-13 16:45:00
12414	1598	9	15	2020-09-19 19:30:00
12415	1598	9	15	2021-02-12 14:15:00
12416	1598	9	15	2021-02-13 18:00:00
12417	1598	9	15	2020-05-14 21:15:00
12418	1599	5	13	2021-11-26 06:00:00
12419	1599	5	13	2021-09-27 11:15:00
12420	1599	5	13	2021-05-10 00:15:00
12421	1599	5	13	2020-09-23 20:30:00
12422	1599	5	13	2019-12-25 02:15:00
12423	1599	5	13	2020-04-03 23:30:00
12424	1599	5	13	2021-09-25 23:30:00
12425	1599	5	13	2020-05-02 04:30:00
12426	1599	5	13	2020-11-20 07:30:00
12427	1599	5	13	2020-12-13 17:45:00
12428	1600	3	12	2018-11-20 12:30:00
12429	1600	3	12	2017-11-06 16:15:00
12430	1600	3	12	2017-10-05 21:45:00
12431	1601	20	8	2020-11-25 14:00:00
12432	1601	20	8	2020-07-02 01:15:00
12433	1601	20	8	2021-09-05 05:45:00
12434	1601	20	8	2021-06-14 18:45:00
12435	1601	20	8	2021-06-27 19:00:00
12436	1601	20	8	2020-12-22 17:30:00
12437	1601	20	8	2019-12-21 05:30:00
12438	1601	20	8	2020-11-01 19:30:00
12439	1601	20	8	2020-03-04 08:00:00
12440	1602	6	18	2020-04-12 17:45:00
12441	1602	6	18	2020-12-04 20:15:00
12442	1602	6	18	2021-04-22 21:30:00
12443	1602	6	18	2020-12-06 06:30:00
12444	1602	6	18	2020-07-21 12:00:00
12445	1602	6	18	2020-04-24 07:45:00
12446	1602	6	18	2020-04-05 21:00:00
12447	1602	6	18	2020-09-07 22:45:00
12448	1602	6	18	2020-09-24 01:15:00
12449	1602	6	18	2021-01-05 08:45:00
12450	1602	6	18	2020-12-08 08:15:00
12451	1603	13	18	2020-07-12 19:45:00
12452	1603	13	18	2020-03-18 20:45:00
12453	1603	13	18	2020-04-01 07:30:00
12454	1603	13	18	2019-07-11 07:15:00
12455	1603	13	18	2019-05-03 23:30:00
12456	1603	13	18	2020-10-18 05:00:00
12457	1603	13	18	2019-10-10 00:45:00
12458	1603	13	18	2019-05-15 10:00:00
12459	1603	13	18	2019-11-08 05:30:00
12460	1604	15	10	2020-11-20 13:45:00
12461	1604	15	10	2020-02-10 10:15:00
12462	1604	15	10	2019-07-02 02:00:00
12463	1604	15	10	2019-11-05 14:00:00
12464	1604	15	10	2020-02-10 16:45:00
12465	1604	15	10	2019-08-20 22:45:00
12466	1604	15	10	2020-06-24 16:30:00
12467	1604	15	10	2020-01-03 08:30:00
12468	1604	15	10	2020-12-19 20:00:00
12469	1604	15	10	2020-08-16 08:45:00
12470	1605	19	3	2019-02-02 15:00:00
12471	1605	19	3	2020-01-04 19:30:00
12472	1605	19	3	2019-03-23 19:15:00
12473	1605	19	3	2020-04-01 17:45:00
12474	1605	19	3	2019-07-09 20:00:00
12475	1605	19	3	2020-07-28 13:15:00
12476	1605	19	3	2020-04-25 15:15:00
12477	1605	19	3	2019-06-05 11:00:00
12478	1606	6	7	2019-09-07 11:15:00
12479	1606	6	7	2021-03-28 13:45:00
12480	1606	6	7	2020-09-21 10:30:00
12481	1606	6	7	2021-01-10 03:15:00
12482	1606	6	7	2020-07-11 22:30:00
12483	1606	6	7	2020-11-22 19:00:00
12484	1606	6	7	2020-12-12 20:45:00
12485	1606	6	7	2021-03-05 10:00:00
12486	1606	6	7	2021-01-01 05:00:00
12487	1606	6	7	2019-07-17 14:30:00
12488	1607	5	6	2019-10-11 12:30:00
12489	1607	5	6	2020-09-09 12:30:00
12490	1607	5	6	2019-06-17 01:45:00
12491	1607	5	6	2019-06-10 14:00:00
12492	1607	5	6	2019-12-25 05:30:00
12493	1607	5	6	2019-09-12 14:30:00
12494	1607	5	6	2020-09-05 10:15:00
12495	1607	5	6	2019-02-13 08:30:00
12496	1607	5	6	2020-05-19 12:30:00
12497	1607	5	6	2019-10-15 06:30:00
12498	1607	5	6	2020-05-30 07:15:00
12499	1607	5	6	2020-05-28 20:15:00
12500	1607	5	6	2019-06-02 19:45:00
12501	1607	5	6	2019-06-30 13:30:00
12502	1608	4	3	2018-12-08 16:00:00
12503	1608	4	3	2019-06-04 17:15:00
12504	1608	4	3	2020-03-01 21:30:00
12505	1608	4	3	2019-11-26 01:15:00
12506	1608	4	3	2018-10-17 21:00:00
12507	1608	4	3	2020-02-24 17:00:00
12508	1608	4	3	2019-12-01 20:30:00
12509	1608	4	3	2019-09-27 20:30:00
12510	1608	4	3	2019-10-10 14:15:00
12511	1608	4	3	2018-09-04 06:15:00
12512	1608	4	3	2020-06-27 07:30:00
12513	1608	4	3	2019-02-12 06:45:00
12514	1609	6	1	2020-10-01 17:00:00
12515	1609	6	1	2021-05-10 04:30:00
12516	1609	6	1	2019-07-12 12:00:00
12517	1609	6	1	2021-03-04 14:00:00
12518	1609	6	1	2020-11-29 21:30:00
12519	1609	6	1	2019-09-09 04:45:00
12520	1609	6	1	2020-09-17 08:15:00
12521	1609	6	1	2021-06-20 23:45:00
12522	1609	6	1	2021-06-12 21:30:00
12523	1609	6	1	2020-09-07 02:15:00
12524	1609	6	1	2020-11-28 08:45:00
12525	1609	6	1	2020-01-29 03:30:00
12526	1609	6	1	2020-02-06 04:00:00
12527	1609	6	1	2021-02-11 08:15:00
12528	1610	16	1	2018-11-01 13:15:00
12529	1610	16	1	2020-06-23 07:45:00
12530	1610	16	1	2019-12-30 15:00:00
12531	1610	16	1	2019-09-10 21:45:00
12532	1610	16	1	2019-06-11 12:15:00
12533	1611	18	4	2020-01-21 15:15:00
12534	1611	18	4	2018-07-03 08:00:00
12535	1611	18	4	2018-05-28 03:15:00
12536	1611	18	4	2019-02-04 21:45:00
12537	1611	18	4	2019-05-06 22:45:00
12538	1611	18	4	2019-09-13 23:00:00
12539	1611	18	4	2019-03-05 13:30:00
12540	1611	18	4	2018-10-14 07:30:00
12541	1611	18	4	2019-08-28 01:00:00
12542	1611	18	4	2019-01-01 02:30:00
12543	1611	18	4	2020-03-21 01:45:00
12544	1611	18	4	2019-04-04 17:15:00
12545	1611	18	4	2019-06-23 13:45:00
12546	1611	18	4	2020-01-18 06:00:00
12547	1612	3	8	2018-08-28 20:30:00
12548	1612	3	8	2018-04-05 18:15:00
12549	1612	3	8	2018-12-24 19:45:00
12550	1612	3	8	2017-07-21 08:30:00
12551	1612	3	8	2018-03-10 07:30:00
12552	1612	3	8	2017-11-02 06:15:00
12553	1612	3	8	2017-06-01 10:00:00
12554	1612	3	8	2019-01-25 20:45:00
12555	1612	3	8	2018-09-08 22:15:00
12556	1612	3	8	2018-04-09 22:15:00
12557	1612	3	8	2017-06-25 09:15:00
12558	1612	3	8	2018-09-18 13:30:00
12559	1612	3	8	2017-04-27 14:15:00
12560	1613	12	4	2019-03-16 16:30:00
12561	1614	13	9	2021-02-18 03:15:00
12562	1614	13	9	2020-11-08 02:00:00
12563	1614	13	9	2020-05-28 01:45:00
12564	1615	15	20	2019-12-25 13:30:00
12565	1615	15	20	2019-02-02 12:15:00
12566	1615	15	20	2019-04-15 05:15:00
12567	1615	15	20	2020-03-11 07:15:00
12568	1615	15	20	2019-06-24 02:00:00
12569	1615	15	20	2020-05-30 14:00:00
12570	1615	15	20	2018-11-23 19:00:00
12571	1616	20	13	2019-07-27 17:30:00
12572	1616	20	13	2020-10-12 18:45:00
12573	1616	20	13	2019-08-21 12:15:00
12574	1616	20	13	2020-02-12 12:00:00
12575	1616	20	13	2021-01-22 04:15:00
12576	1616	20	13	2020-07-06 19:30:00
12577	1616	20	13	2020-11-19 14:00:00
12578	1616	20	13	2019-11-17 18:45:00
12579	1616	20	13	2021-05-05 03:45:00
12580	1616	20	13	2020-07-22 02:45:00
12581	1616	20	13	2021-02-09 04:00:00
12582	1616	20	13	2019-12-23 21:45:00
12583	1616	20	13	2019-10-23 15:45:00
12584	1616	20	13	2021-02-02 15:30:00
12585	1617	2	17	2019-12-11 20:30:00
12586	1617	2	17	2019-08-09 16:00:00
12587	1617	2	17	2020-02-27 00:15:00
12588	1617	2	17	2019-09-10 18:15:00
12589	1617	2	17	2020-06-25 09:30:00
12590	1617	2	17	2019-02-02 10:15:00
12591	1617	2	17	2020-03-01 13:15:00
12592	1617	2	17	2020-06-25 12:15:00
12593	1617	2	17	2020-05-17 15:15:00
12594	1617	2	17	2019-11-11 09:00:00
12595	1617	2	17	2018-11-11 05:15:00
12596	1617	2	17	2019-10-28 07:00:00
12597	1617	2	17	2019-06-03 03:15:00
12598	1617	2	17	2019-06-03 11:00:00
12599	1618	10	19	2021-04-21 20:45:00
12600	1618	10	19	2021-02-02 18:30:00
12601	1618	10	19	2021-05-06 20:30:00
12602	1618	10	19	2020-04-05 23:45:00
12603	1618	10	19	2021-04-04 16:30:00
12604	1618	10	19	2019-08-07 04:30:00
12605	1618	10	19	2021-07-01 13:15:00
12606	1618	10	19	2021-02-01 07:00:00
12607	1618	10	19	2019-11-20 00:00:00
12608	1619	11	16	2019-04-04 23:30:00
12609	1619	11	16	2019-01-05 03:30:00
12610	1619	11	16	2018-12-17 13:45:00
12611	1619	11	16	2019-06-29 01:45:00
12612	1619	11	16	2019-12-17 22:30:00
12613	1619	11	16	2019-06-25 02:15:00
12614	1620	13	1	2019-10-14 07:00:00
12615	1620	13	1	2018-12-29 22:00:00
12616	1620	13	1	2020-02-08 13:15:00
12617	1620	13	1	2019-02-12 07:45:00
12618	1620	13	1	2019-03-14 19:15:00
12619	1620	13	1	2019-08-07 15:45:00
12620	1620	13	1	2020-06-11 16:45:00
12621	1620	13	1	2019-05-14 12:45:00
12622	1620	13	1	2020-10-05 16:00:00
12623	1620	13	1	2020-05-19 04:00:00
12624	1621	14	14	2017-06-14 19:45:00
12625	1621	14	14	2018-09-23 05:00:00
12626	1621	14	14	2018-09-02 10:30:00
12627	1621	14	14	2018-07-27 12:30:00
12628	1621	14	14	2017-08-07 03:00:00
12629	1621	14	14	2018-11-05 10:00:00
12630	1621	14	14	2018-08-09 05:30:00
12631	1621	14	14	2017-08-24 04:30:00
12632	1621	14	14	2018-11-21 11:00:00
12633	1621	14	14	2018-07-12 02:30:00
12634	1621	14	14	2019-04-06 05:15:00
12635	1622	11	1	2019-07-17 17:15:00
12636	1623	7	8	2020-10-16 07:15:00
12637	1624	12	15	2021-01-05 19:30:00
12638	1624	12	15	2020-08-02 07:15:00
12639	1624	12	15	2020-04-01 15:00:00
12640	1624	12	15	2020-10-08 03:00:00
12641	1624	12	15	2020-09-08 02:30:00
12642	1624	12	15	2021-05-25 19:30:00
12643	1624	12	15	2021-05-13 12:45:00
12644	1624	12	15	2019-10-26 01:15:00
12645	1624	12	15	2020-03-20 17:00:00
12646	1624	12	15	2020-05-19 08:00:00
12647	1624	12	15	2020-08-08 16:15:00
12648	1624	12	15	2020-02-24 07:45:00
12649	1624	12	15	2020-09-18 04:00:00
12650	1624	12	15	2021-03-21 09:45:00
12651	1625	20	2	2019-10-23 19:15:00
12652	1625	20	2	2021-06-01 16:15:00
12653	1625	20	2	2021-09-19 01:15:00
12654	1625	20	2	2021-03-20 18:30:00
12655	1625	20	2	2021-01-01 08:30:00
12656	1625	20	2	2021-08-07 18:30:00
12657	1626	6	10	2019-09-16 14:15:00
12658	1626	6	10	2020-12-08 04:15:00
12659	1626	6	10	2019-05-24 10:15:00
12660	1626	6	10	2020-02-23 20:15:00
12661	1626	6	10	2020-11-21 02:00:00
12662	1626	6	10	2020-05-12 00:00:00
12663	1626	6	10	2019-03-18 13:30:00
12664	1626	6	10	2020-01-03 18:15:00
12665	1626	6	10	2020-06-21 06:30:00
12666	1626	6	10	2020-12-08 03:15:00
12667	1626	6	10	2020-01-11 19:45:00
12668	1626	6	10	2020-11-21 13:45:00
12669	1626	6	10	2019-08-12 23:30:00
12670	1626	6	10	2020-04-18 04:30:00
12671	1627	11	14	2020-03-04 22:30:00
12672	1627	11	14	2019-10-29 23:00:00
12673	1627	11	14	2019-09-21 07:45:00
12674	1627	11	14	2019-06-12 20:45:00
12675	1627	11	14	2019-06-05 17:15:00
12676	1627	11	14	2018-10-10 15:00:00
12677	1627	11	14	2020-03-08 04:30:00
12678	1628	9	9	2019-02-19 03:30:00
12679	1628	9	9	2018-11-06 09:00:00
12680	1628	9	9	2020-01-23 23:45:00
12681	1628	9	9	2020-01-26 12:15:00
12682	1628	9	9	2019-10-08 03:00:00
12683	1628	9	9	2020-05-24 23:15:00
12684	1628	9	9	2020-01-26 02:00:00
12685	1628	9	9	2020-03-12 02:45:00
12686	1628	9	9	2019-07-19 16:00:00
12687	1628	9	9	2019-08-23 11:00:00
12688	1628	9	9	2020-04-01 19:15:00
12689	1628	9	9	2019-08-03 12:00:00
12690	1628	9	9	2020-06-30 20:45:00
12691	1629	9	1	2019-06-05 01:00:00
12692	1629	9	1	2018-12-19 21:30:00
12693	1629	9	1	2019-05-09 21:45:00
12694	1629	9	1	2019-05-24 11:30:00
12695	1629	9	1	2018-01-26 09:15:00
12696	1629	9	1	2018-11-17 16:15:00
12697	1629	9	1	2019-12-21 15:00:00
12698	1629	9	1	2018-12-29 21:15:00
12699	1630	4	20	2019-02-26 01:45:00
12700	1630	4	20	2017-12-29 06:00:00
12701	1630	4	20	2019-05-30 11:30:00
12702	1630	4	20	2017-12-21 11:00:00
12703	1630	4	20	2017-07-24 22:30:00
12704	1630	4	20	2017-07-01 02:30:00
12705	1630	4	20	2017-09-03 07:00:00
12706	1630	4	20	2018-03-30 09:45:00
12707	1630	4	20	2018-06-21 16:30:00
12708	1630	4	20	2018-10-08 12:00:00
12709	1630	4	20	2017-11-01 04:00:00
12710	1630	4	20	2017-12-24 12:45:00
12711	1631	3	2	2019-05-11 20:00:00
12712	1631	3	2	2019-08-02 19:15:00
12713	1631	3	2	2019-10-27 03:00:00
12714	1631	3	2	2020-11-06 05:00:00
12715	1631	3	2	2020-08-21 05:00:00
12716	1632	4	17	2019-11-01 16:30:00
12717	1632	4	17	2018-12-02 07:30:00
12718	1632	4	17	2018-03-11 03:00:00
12719	1633	1	10	2018-12-18 10:15:00
12720	1633	1	10	2017-04-27 10:15:00
12721	1633	1	10	2018-12-17 00:30:00
12722	1633	1	10	2017-04-28 01:30:00
12723	1633	1	10	2018-07-16 21:30:00
12724	1634	1	7	2020-04-13 09:00:00
12725	1634	1	7	2020-01-23 14:15:00
12726	1634	1	7	2020-05-26 01:00:00
12727	1634	1	7	2020-08-06 03:00:00
12728	1634	1	7	2019-11-10 16:30:00
12729	1635	7	4	2020-07-25 13:30:00
12730	1635	7	4	2020-10-13 12:15:00
12731	1635	7	4	2020-08-03 05:30:00
12732	1635	7	4	2020-04-19 03:30:00
12733	1635	7	4	2020-03-22 15:00:00
12734	1635	7	4	2020-07-22 21:45:00
12735	1635	7	4	2021-03-28 07:30:00
12736	1635	7	4	2021-10-25 15:15:00
12737	1635	7	4	2020-02-26 16:30:00
12738	1635	7	4	2021-09-26 13:30:00
12739	1635	7	4	2021-10-19 02:45:00
12740	1635	7	4	2021-01-22 12:45:00
12741	1635	7	4	2020-05-20 15:30:00
12742	1636	19	12	2018-09-25 17:00:00
12743	1636	19	12	2018-01-06 13:15:00
12744	1636	19	12	2017-12-17 19:30:00
12745	1636	19	12	2019-03-12 15:45:00
12746	1636	19	12	2017-12-12 02:45:00
12747	1636	19	12	2018-05-17 22:30:00
12748	1636	19	12	2018-04-08 10:30:00
12749	1636	19	12	2018-10-24 20:30:00
12750	1636	19	12	2019-09-25 06:15:00
12751	1636	19	12	2018-09-02 08:15:00
12752	1636	19	12	2018-01-10 00:00:00
12753	1636	19	12	2019-07-30 18:00:00
12754	1637	2	1	2019-04-02 12:15:00
12755	1637	2	1	2020-11-02 18:15:00
12756	1637	2	1	2019-09-28 03:15:00
12757	1637	2	1	2019-01-23 17:15:00
12758	1637	2	1	2019-12-07 18:00:00
12759	1637	2	1	2020-06-30 12:15:00
12760	1637	2	1	2020-05-30 10:15:00
12761	1637	2	1	2019-11-12 16:15:00
12762	1637	2	1	2020-07-26 21:30:00
12763	1637	2	1	2020-07-24 11:30:00
12764	1637	2	1	2019-12-14 04:00:00
12765	1637	2	1	2020-07-21 22:30:00
12766	1637	2	1	2020-09-02 16:45:00
12767	1637	2	1	2020-10-10 17:15:00
12768	1637	2	1	2020-05-07 21:15:00
12769	1638	17	1	2017-11-19 12:15:00
12770	1638	17	1	2017-09-23 02:00:00
12771	1638	17	1	2017-08-10 00:00:00
12772	1638	17	1	2017-09-11 22:15:00
12773	1638	17	1	2019-02-09 02:15:00
12774	1638	17	1	2017-11-17 01:00:00
12775	1638	17	1	2019-02-12 05:15:00
12776	1638	17	1	2017-10-25 11:00:00
12777	1638	17	1	2018-06-02 06:45:00
12778	1638	17	1	2017-06-26 00:45:00
12779	1638	17	1	2017-07-15 01:15:00
12780	1639	18	7	2017-03-06 12:45:00
12781	1639	18	7	2017-06-22 02:45:00
12782	1639	18	7	2017-12-04 02:30:00
12783	1639	18	7	2017-08-14 13:30:00
12784	1639	18	7	2018-05-30 19:00:00
12785	1639	18	7	2017-12-28 07:00:00
12786	1639	18	7	2017-02-16 14:30:00
12787	1639	18	7	2017-06-28 00:30:00
12788	1639	18	7	2018-01-30 15:30:00
12789	1639	18	7	2017-03-17 06:30:00
12790	1639	18	7	2017-05-10 20:15:00
12791	1639	18	7	2018-07-20 09:45:00
12792	1640	2	11	2019-02-20 02:30:00
12793	1640	2	11	2018-06-05 18:30:00
12794	1640	2	11	2017-12-22 17:00:00
12795	1640	2	11	2019-02-07 15:00:00
12796	1640	2	11	2018-02-03 01:00:00
12797	1640	2	11	2019-05-01 21:30:00
12798	1640	2	11	2017-10-29 09:00:00
12799	1640	2	11	2018-09-25 20:45:00
12800	1641	19	19	2020-03-29 18:45:00
12801	1641	19	19	2019-01-24 09:45:00
12802	1641	19	19	2019-08-20 20:45:00
12803	1641	19	19	2018-09-17 13:00:00
12804	1641	19	19	2019-06-14 01:15:00
12805	1642	5	14	2021-01-24 03:30:00
12806	1642	5	14	2019-10-19 17:00:00
12807	1642	5	14	2020-12-13 10:00:00
12808	1643	13	6	2018-12-14 20:45:00
12809	1643	13	6	2018-03-30 05:30:00
12810	1643	13	6	2017-10-03 02:15:00
12811	1644	3	2	2018-02-18 04:00:00
12812	1644	3	2	2019-12-17 13:30:00
12813	1644	3	2	2018-06-25 00:15:00
12814	1644	3	2	2019-05-22 10:15:00
12815	1644	3	2	2019-09-06 14:30:00
12816	1644	3	2	2019-06-08 04:45:00
12817	1644	3	2	2019-08-19 17:15:00
12818	1644	3	2	2019-05-04 12:45:00
12819	1644	3	2	2019-08-14 20:45:00
12820	1644	3	2	2018-08-19 15:15:00
12821	1644	3	2	2018-05-30 18:45:00
12822	1644	3	2	2019-09-09 20:30:00
12823	1644	3	2	2018-12-27 12:00:00
12824	1644	3	2	2018-03-25 00:00:00
12825	1645	11	12	2020-11-13 06:30:00
12826	1645	11	12	2021-07-04 06:30:00
12827	1645	11	12	2020-05-11 07:15:00
12828	1645	11	12	2021-05-09 21:30:00
12829	1645	11	12	2020-02-11 13:45:00
12830	1645	11	12	2021-01-29 08:15:00
12831	1645	11	12	2021-07-17 22:15:00
12832	1645	11	12	2020-05-23 05:30:00
12833	1645	11	12	2020-07-24 17:30:00
12834	1646	15	12	2019-05-13 11:00:00
12835	1646	15	12	2019-03-04 18:45:00
12836	1646	15	12	2018-10-25 01:00:00
12837	1646	15	12	2019-10-01 13:15:00
12838	1646	15	12	2019-02-04 11:45:00
12839	1646	15	12	2018-06-26 10:45:00
12840	1646	15	12	2019-12-05 21:00:00
12841	1646	15	12	2018-11-16 10:00:00
12842	1646	15	12	2018-04-11 11:45:00
12843	1646	15	12	2018-11-29 16:45:00
12844	1646	15	12	2018-02-24 16:30:00
12845	1646	15	12	2018-05-03 20:30:00
12846	1646	15	12	2018-12-17 04:00:00
12847	1646	15	12	2018-06-04 09:00:00
12848	1647	10	9	2020-09-06 16:00:00
12849	1647	10	9	2020-05-07 16:45:00
12850	1648	16	15	2019-10-16 02:15:00
12851	1648	16	15	2019-04-09 08:45:00
12852	1648	16	15	2019-05-09 12:45:00
12853	1648	16	15	2019-10-17 13:45:00
12854	1648	16	15	2020-03-05 06:45:00
12855	1648	16	15	2019-06-18 08:30:00
12856	1648	16	15	2019-12-23 03:15:00
12857	1648	16	15	2021-01-05 19:00:00
12858	1648	16	15	2020-07-02 04:00:00
12859	1649	6	8	2020-08-23 10:30:00
12860	1649	6	8	2020-05-23 02:15:00
12861	1649	6	8	2020-09-14 02:45:00
12862	1649	6	8	2020-06-03 09:45:00
12863	1649	6	8	2019-12-02 09:30:00
12864	1649	6	8	2020-12-28 11:45:00
12865	1649	6	8	2020-06-24 00:00:00
12866	1649	6	8	2020-08-02 05:00:00
12867	1649	6	8	2021-04-15 13:45:00
12868	1649	6	8	2020-05-27 18:30:00
12869	1649	6	8	2020-01-04 02:30:00
12870	1649	6	8	2019-11-05 08:30:00
12871	1649	6	8	2021-03-20 07:00:00
12872	1649	6	8	2020-04-22 19:30:00
12873	1649	6	8	2021-01-05 12:45:00
12874	1650	8	20	2021-03-19 22:45:00
12875	1650	8	20	2020-08-18 08:15:00
12876	1650	8	20	2020-05-03 08:15:00
12877	1650	8	20	2019-11-26 08:45:00
12878	1650	8	20	2021-02-18 18:30:00
12879	1650	8	20	2019-12-11 06:00:00
12880	1650	8	20	2021-01-13 07:15:00
12881	1650	8	20	2021-05-21 23:15:00
12882	1650	8	20	2021-01-09 05:30:00
12883	1651	13	2	2020-09-16 21:30:00
12884	1651	13	2	2019-04-13 04:45:00
12885	1651	13	2	2019-08-21 04:30:00
12886	1651	13	2	2020-04-13 11:00:00
12887	1651	13	2	2019-06-18 15:15:00
12888	1651	13	2	2020-09-08 10:30:00
12889	1651	13	2	2021-03-18 00:00:00
12890	1651	13	2	2020-02-03 20:00:00
12891	1651	13	2	2020-08-05 03:30:00
12892	1651	13	2	2020-01-09 10:00:00
12893	1651	13	2	2019-08-14 04:00:00
12894	1651	13	2	2020-06-16 09:45:00
12895	1651	13	2	2019-04-01 15:45:00
12896	1652	17	10	2020-09-22 16:45:00
12897	1652	17	10	2020-06-09 14:30:00
12898	1652	17	10	2019-03-20 13:30:00
12899	1652	17	10	2019-05-23 01:45:00
12900	1652	17	10	2019-02-12 16:30:00
12901	1652	17	10	2019-04-20 01:30:00
12902	1652	17	10	2019-05-24 00:45:00
12903	1652	17	10	2019-05-29 09:00:00
12904	1652	17	10	2020-04-24 20:00:00
12905	1652	17	10	2020-10-15 08:45:00
12906	1652	17	10	2020-07-16 03:30:00
12907	1652	17	10	2019-01-24 06:30:00
12908	1652	17	10	2020-02-06 19:15:00
12909	1652	17	10	2019-07-29 18:15:00
12910	1653	15	2	2017-12-09 23:15:00
12911	1653	15	2	2019-06-25 23:45:00
12912	1653	15	2	2017-12-27 05:30:00
12913	1653	15	2	2018-01-07 18:30:00
12914	1653	15	2	2017-12-08 01:30:00
12915	1653	15	2	2019-03-15 22:15:00
12916	1653	15	2	2017-12-03 12:45:00
12917	1653	15	2	2019-07-01 00:45:00
12918	1653	15	2	2019-07-26 02:30:00
12919	1653	15	2	2019-04-04 07:00:00
12920	1653	15	2	2018-12-01 01:30:00
12921	1654	3	8	2020-02-17 21:30:00
12922	1654	3	8	2019-08-26 13:30:00
12923	1654	3	8	2018-06-21 07:30:00
12924	1654	3	8	2019-12-10 19:00:00
12925	1654	3	8	2019-12-20 12:45:00
12926	1654	3	8	2018-04-13 07:45:00
12927	1655	10	14	2019-05-04 11:45:00
12928	1655	10	14	2018-01-24 11:15:00
12929	1655	10	14	2017-11-01 06:30:00
12930	1655	10	14	2018-09-13 02:45:00
12931	1655	10	14	2019-07-09 22:30:00
12932	1655	10	14	2018-03-14 21:30:00
12933	1655	10	14	2019-04-26 08:45:00
12934	1655	10	14	2018-05-08 10:00:00
12935	1656	5	7	2018-12-14 17:30:00
12936	1656	5	7	2018-11-09 00:15:00
12937	1656	5	7	2018-09-28 07:30:00
12938	1656	5	7	2018-11-05 20:00:00
12939	1657	13	11	2020-08-25 21:15:00
12940	1657	13	11	2021-03-24 17:15:00
12941	1657	13	11	2021-05-19 05:15:00
12942	1657	13	11	2021-08-14 06:15:00
12943	1658	17	13	2019-02-11 09:30:00
12944	1658	17	13	2018-11-11 07:15:00
12945	1658	17	13	2018-01-11 15:00:00
12946	1658	17	13	2017-10-02 01:15:00
12947	1658	17	13	2019-08-04 23:45:00
12948	1658	17	13	2018-11-10 20:15:00
12949	1658	17	13	2018-07-22 03:30:00
12950	1658	17	13	2019-02-03 21:15:00
12951	1658	17	13	2019-02-03 07:45:00
12952	1658	17	13	2017-11-24 23:30:00
12953	1658	17	13	2018-06-10 12:30:00
12954	1659	5	16	2018-11-28 20:45:00
12955	1659	5	16	2020-05-10 18:45:00
12956	1659	5	16	2019-08-01 02:45:00
12957	1659	5	16	2019-06-02 10:15:00
12958	1659	5	16	2018-07-21 13:00:00
12959	1659	5	16	2020-03-04 20:30:00
12960	1659	5	16	2019-02-04 15:15:00
12961	1659	5	16	2019-11-25 07:15:00
12962	1659	5	16	2019-10-30 13:15:00
12963	1659	5	16	2020-02-03 03:15:00
12964	1659	5	16	2018-08-03 18:45:00
12965	1659	5	16	2019-12-17 17:00:00
12966	1659	5	16	2020-02-04 13:15:00
12967	1660	19	2	2019-08-28 07:30:00
12968	1660	19	2	2019-05-04 03:00:00
12969	1660	19	2	2019-12-01 03:30:00
12970	1660	19	2	2019-09-14 10:30:00
12971	1660	19	2	2019-09-26 10:00:00
12972	1660	19	2	2020-11-10 22:30:00
12973	1660	19	2	2019-12-15 12:30:00
12974	1660	19	2	2020-08-21 11:15:00
12975	1660	19	2	2020-03-01 04:15:00
12976	1660	19	2	2019-02-10 02:00:00
12977	1660	19	2	2020-01-27 13:15:00
12978	1661	9	20	2021-03-12 04:30:00
12979	1661	9	20	2020-04-06 10:00:00
12980	1661	9	20	2019-12-04 22:15:00
12981	1661	9	20	2019-12-25 10:15:00
12982	1661	9	20	2020-04-23 13:00:00
12983	1661	9	20	2020-12-22 09:30:00
12984	1661	9	20	2020-03-27 21:30:00
12985	1661	9	20	2019-05-19 21:00:00
12986	1661	9	20	2020-12-02 18:45:00
12987	1662	7	14	2019-07-28 01:15:00
12988	1662	7	14	2019-03-26 07:00:00
12989	1662	7	14	2018-12-29 15:45:00
12990	1662	7	14	2019-06-29 05:45:00
12991	1662	7	14	2017-12-15 15:15:00
12992	1662	7	14	2019-06-05 05:15:00
12993	1662	7	14	2018-07-21 20:15:00
12994	1662	7	14	2018-01-15 04:30:00
12995	1662	7	14	2019-06-30 21:30:00
12996	1662	7	14	2019-01-03 02:45:00
12997	1662	7	14	2019-01-23 08:15:00
12998	1662	7	14	2018-11-11 05:00:00
12999	1663	2	2	2018-11-01 06:30:00
13000	1663	2	2	2018-09-20 03:30:00
13001	1663	2	2	2019-04-17 16:45:00
13002	1663	2	2	2019-04-05 00:15:00
13003	1663	2	2	2018-08-04 05:00:00
13004	1663	2	2	2017-09-29 13:30:00
13005	1663	2	2	2018-02-17 03:15:00
13006	1663	2	2	2017-08-12 06:30:00
13007	1663	2	2	2019-05-06 05:00:00
13008	1663	2	2	2019-04-17 20:15:00
13009	1663	2	2	2018-06-14 05:00:00
13010	1663	2	2	2019-06-10 07:45:00
13011	1663	2	2	2018-05-13 00:00:00
13012	1664	19	2	2021-06-24 11:00:00
13013	1664	19	2	2019-12-03 18:00:00
13014	1664	19	2	2020-06-07 04:15:00
13015	1664	19	2	2021-04-19 09:30:00
13016	1664	19	2	2019-08-11 13:15:00
13017	1664	19	2	2020-08-10 14:15:00
13018	1664	19	2	2021-06-23 01:30:00
13019	1664	19	2	2020-07-07 20:15:00
13020	1664	19	2	2020-11-07 07:15:00
13021	1664	19	2	2019-07-13 11:15:00
13022	1664	19	2	2019-12-28 12:30:00
13023	1664	19	2	2020-09-05 09:15:00
13024	1664	19	2	2020-10-21 12:00:00
13025	1664	19	2	2019-11-28 01:45:00
13026	1664	19	2	2019-08-12 16:00:00
13027	1665	19	2	2018-11-24 02:00:00
13028	1665	19	2	2019-11-14 07:00:00
13029	1665	19	2	2019-12-06 13:00:00
13030	1665	19	2	2018-11-13 16:30:00
13031	1665	19	2	2019-03-02 01:15:00
13032	1666	4	10	2019-06-16 04:00:00
13033	1666	4	10	2018-05-07 11:00:00
13034	1666	4	10	2019-01-05 23:00:00
13035	1666	4	10	2019-04-14 05:45:00
13036	1666	4	10	2019-12-22 05:00:00
13037	1666	4	10	2019-02-16 03:45:00
13038	1667	10	11	2018-07-04 09:45:00
13039	1667	10	11	2020-01-09 09:15:00
13040	1667	10	11	2019-07-19 15:30:00
13041	1667	10	11	2020-01-12 01:15:00
13042	1667	10	11	2018-06-18 03:45:00
13043	1668	15	15	2019-11-09 12:45:00
13044	1668	15	15	2021-01-29 23:15:00
13045	1668	15	15	2020-05-22 18:00:00
13046	1668	15	15	2019-05-02 01:15:00
13047	1668	15	15	2020-06-05 22:00:00
13048	1668	15	15	2020-01-17 08:00:00
13049	1668	15	15	2019-03-03 23:45:00
13050	1668	15	15	2020-04-15 16:30:00
13051	1668	15	15	2020-11-23 19:15:00
13052	1668	15	15	2021-02-01 22:15:00
13053	1669	20	11	2020-10-18 22:00:00
13054	1669	20	11	2021-04-13 04:00:00
13055	1669	20	11	2020-09-14 05:15:00
13056	1669	20	11	2020-02-25 22:00:00
13057	1669	20	11	2019-11-25 16:45:00
13058	1669	20	11	2019-08-29 11:15:00
13059	1669	20	11	2020-08-03 22:15:00
13060	1669	20	11	2021-02-19 05:00:00
13061	1669	20	11	2021-02-21 10:30:00
13062	1669	20	11	2020-09-02 05:45:00
13063	1670	15	18	2019-06-29 11:15:00
13064	1670	15	18	2019-04-11 11:30:00
13065	1670	15	18	2020-06-15 00:30:00
13066	1670	15	18	2020-03-27 05:15:00
13067	1671	15	15	2021-04-19 19:30:00
13068	1671	15	15	2020-08-19 15:30:00
13069	1671	15	15	2021-10-07 19:15:00
13070	1671	15	15	2021-07-05 21:15:00
13071	1672	14	2	2019-03-16 06:00:00
13072	1672	14	2	2019-03-09 15:45:00
13073	1672	14	2	2017-08-14 23:30:00
13074	1672	14	2	2017-09-08 04:00:00
13075	1672	14	2	2018-11-06 06:30:00
13076	1672	14	2	2017-09-15 09:00:00
13077	1672	14	2	2017-09-09 03:00:00
13078	1672	14	2	2018-04-28 23:45:00
13079	1673	8	13	2019-09-26 21:45:00
13080	1673	8	13	2019-11-12 05:45:00
13081	1674	19	17	2020-01-08 05:45:00
13082	1674	19	17	2019-06-21 20:00:00
13083	1674	19	17	2020-07-10 18:00:00
13084	1674	19	17	2020-03-03 17:15:00
13085	1674	19	17	2020-02-27 08:15:00
13086	1674	19	17	2020-01-28 22:00:00
13087	1674	19	17	2019-09-30 00:00:00
13088	1674	19	17	2020-10-04 01:45:00
13089	1675	20	17	2018-07-12 05:00:00
13090	1675	20	17	2019-11-22 17:00:00
13091	1675	20	17	2018-05-25 23:00:00
13092	1675	20	17	2018-11-13 17:15:00
13093	1675	20	17	2019-02-02 08:15:00
13094	1675	20	17	2020-01-14 04:15:00
13095	1675	20	17	2019-11-10 10:15:00
13096	1675	20	17	2018-10-23 17:15:00
13097	1675	20	17	2018-09-17 17:45:00
13098	1675	20	17	2018-08-18 09:00:00
13099	1675	20	17	2019-05-14 14:45:00
13100	1676	5	20	2021-05-03 14:45:00
13101	1676	5	20	2020-01-09 07:30:00
13102	1676	5	20	2020-05-20 13:45:00
13103	1676	5	20	2020-05-02 05:00:00
13104	1676	5	20	2019-12-16 15:00:00
13105	1676	5	20	2021-09-29 02:00:00
13106	1676	5	20	2020-03-01 07:45:00
13107	1676	5	20	2020-11-16 21:45:00
13108	1676	5	20	2020-03-20 07:30:00
13109	1676	5	20	2020-04-27 15:00:00
13110	1676	5	20	2021-05-11 16:15:00
13111	1676	5	20	2021-08-11 11:45:00
13112	1676	5	20	2021-05-14 21:00:00
13113	1677	6	14	2020-06-13 00:30:00
13114	1677	6	14	2020-04-13 17:00:00
13115	1677	6	14	2019-08-10 07:30:00
13116	1678	12	1	2021-03-27 05:00:00
13117	1678	12	1	2021-04-19 18:45:00
13118	1678	12	1	2021-03-22 11:30:00
13119	1678	12	1	2020-12-03 00:30:00
13120	1678	12	1	2019-12-17 11:15:00
13121	1678	12	1	2020-10-12 06:00:00
13122	1678	12	1	2020-11-22 01:45:00
13123	1678	12	1	2020-01-07 21:00:00
13124	1678	12	1	2021-02-26 07:00:00
13125	1678	12	1	2020-06-17 00:00:00
13126	1678	12	1	2020-05-04 10:30:00
13127	1678	12	1	2021-08-01 01:15:00
13128	1678	12	1	2019-10-15 12:15:00
13129	1679	7	18	2019-05-18 01:15:00
13130	1679	7	18	2019-09-12 06:00:00
13131	1679	7	18	2020-02-04 07:15:00
13132	1679	7	18	2019-07-18 22:45:00
13133	1679	7	18	2018-09-02 02:00:00
13134	1679	7	18	2018-03-07 15:15:00
13135	1679	7	18	2018-06-08 06:30:00
13136	1679	7	18	2020-02-07 01:45:00
13137	1679	7	18	2019-02-12 09:30:00
13138	1679	7	18	2019-10-09 06:15:00
13139	1680	3	9	2020-02-18 03:15:00
13140	1680	3	9	2019-11-04 04:30:00
13141	1680	3	9	2018-05-30 06:15:00
13142	1680	3	9	2018-04-27 20:45:00
13143	1680	3	9	2018-11-01 03:30:00
13144	1680	3	9	2019-12-07 17:00:00
13145	1680	3	9	2019-10-25 15:00:00
13146	1680	3	9	2018-04-05 07:00:00
13147	1680	3	9	2018-05-20 17:15:00
13148	1680	3	9	2019-03-18 18:00:00
13149	1680	3	9	2019-11-30 10:00:00
13150	1681	15	12	2019-05-03 02:00:00
13151	1681	15	12	2020-05-15 08:00:00
13152	1681	15	12	2020-04-16 07:45:00
13153	1681	15	12	2018-12-17 07:00:00
13154	1682	20	16	2019-04-09 09:45:00
13155	1682	20	16	2019-05-10 12:45:00
13156	1682	20	16	2020-01-12 06:45:00
13157	1682	20	16	2018-03-14 20:45:00
13158	1682	20	16	2019-01-23 23:30:00
13159	1682	20	16	2019-05-09 01:30:00
13160	1682	20	16	2018-11-16 10:45:00
13161	1682	20	16	2018-07-25 09:45:00
13162	1682	20	16	2018-12-30 11:30:00
13163	1682	20	16	2019-12-20 16:45:00
13164	1682	20	16	2019-05-29 18:45:00
13165	1682	20	16	2019-07-24 11:30:00
13166	1682	20	16	2018-02-03 00:45:00
13167	1683	7	9	2018-10-07 16:45:00
13168	1683	7	9	2018-11-01 09:30:00
13169	1683	7	9	2017-08-10 10:30:00
13170	1683	7	9	2017-10-28 10:15:00
13171	1683	7	9	2018-09-10 04:00:00
13172	1683	7	9	2017-07-20 18:30:00
13173	1683	7	9	2018-08-17 23:30:00
13174	1683	7	9	2019-01-08 05:00:00
13175	1683	7	9	2019-01-14 21:45:00
13176	1683	7	9	2018-12-01 11:30:00
13177	1683	7	9	2018-06-23 19:30:00
13178	1683	7	9	2018-10-12 02:45:00
13179	1683	7	9	2018-02-07 06:00:00
13180	1683	7	9	2018-11-30 14:15:00
13181	1683	7	9	2018-01-15 15:00:00
13182	1684	3	15	2020-12-02 13:30:00
13183	1684	3	15	2020-08-22 12:30:00
13184	1684	3	15	2020-07-03 18:00:00
13185	1684	3	15	2020-09-17 04:15:00
13186	1685	1	5	2018-12-24 14:15:00
13187	1685	1	5	2017-06-14 22:00:00
13188	1685	1	5	2019-05-01 01:15:00
13189	1685	1	5	2018-02-05 09:45:00
13190	1685	1	5	2017-11-29 12:45:00
13191	1685	1	5	2018-07-16 01:30:00
13192	1685	1	5	2018-04-23 03:45:00
13193	1685	1	5	2018-10-18 18:15:00
13194	1685	1	5	2018-01-22 20:30:00
13195	1685	1	5	2017-08-25 03:30:00
13196	1685	1	5	2017-09-15 23:15:00
13197	1685	1	5	2017-08-06 12:15:00
13198	1685	1	5	2018-01-01 06:15:00
13199	1685	1	5	2017-12-11 13:45:00
13200	1686	2	8	2018-05-16 09:45:00
13201	1686	2	8	2017-05-22 21:00:00
13202	1686	2	8	2018-06-04 21:00:00
13203	1687	5	16	2021-03-18 10:00:00
13204	1687	5	16	2020-05-28 01:30:00
13205	1687	5	16	2020-03-06 22:15:00
13206	1687	5	16	2020-07-04 07:30:00
13207	1687	5	16	2020-06-22 16:15:00
13208	1687	5	16	2021-08-27 17:00:00
13209	1687	5	16	2020-02-13 01:30:00
13210	1687	5	16	2020-01-02 05:45:00
13211	1687	5	16	2021-02-25 22:45:00
13212	1687	5	16	2021-02-14 18:15:00
13213	1687	5	16	2021-11-14 18:00:00
13214	1687	5	16	2021-06-05 03:45:00
13215	1688	10	14	2019-11-12 10:15:00
13216	1688	10	14	2020-10-06 09:30:00
13217	1688	10	14	2019-10-30 08:00:00
13218	1688	10	14	2020-07-20 07:15:00
13219	1688	10	14	2020-11-24 06:15:00
13220	1688	10	14	2020-02-25 23:00:00
13221	1688	10	14	2019-06-22 09:45:00
13222	1688	10	14	2019-02-27 12:15:00
13223	1688	10	14	2020-09-14 19:15:00
13224	1688	10	14	2019-11-30 12:15:00
13225	1689	7	4	2019-12-06 15:15:00
13226	1689	7	4	2019-03-18 11:15:00
13227	1689	7	4	2019-02-05 17:00:00
13228	1689	7	4	2020-04-05 13:45:00
13229	1689	7	4	2019-09-09 01:30:00
13230	1689	7	4	2019-10-03 18:30:00
13231	1689	7	4	2018-12-29 15:00:00
13232	1689	7	4	2019-02-21 03:00:00
13233	1690	7	3	2019-12-03 07:15:00
13234	1690	7	3	2020-11-26 19:30:00
13235	1690	7	3	2021-04-25 04:00:00
13236	1690	7	3	2021-05-29 19:00:00
13237	1690	7	3	2021-04-05 06:45:00
13238	1690	7	3	2021-02-22 15:30:00
13239	1690	7	3	2021-07-23 03:45:00
13240	1690	7	3	2021-07-26 13:15:00
13241	1690	7	3	2019-11-28 02:00:00
13242	1691	12	8	2021-04-22 14:45:00
13243	1691	12	8	2020-02-13 07:45:00
13244	1691	12	8	2021-09-24 16:30:00
13245	1691	12	8	2020-09-09 12:30:00
13246	1691	12	8	2021-08-19 01:00:00
13247	1691	12	8	2019-11-05 15:15:00
13248	1691	12	8	2020-03-12 07:45:00
13249	1691	12	8	2021-02-20 22:45:00
13250	1691	12	8	2021-08-02 19:00:00
13251	1691	12	8	2019-12-27 20:45:00
13252	1691	12	8	2021-03-09 14:45:00
13253	1692	16	10	2020-04-30 07:30:00
13254	1692	16	10	2020-06-25 05:30:00
13255	1692	16	10	2019-10-07 16:15:00
13256	1693	10	12	2019-06-03 15:00:00
13257	1693	10	12	2018-06-02 23:15:00
13258	1693	10	12	2018-12-26 19:45:00
13259	1693	10	12	2019-11-11 15:30:00
13260	1693	10	12	2018-10-30 04:30:00
13261	1693	10	12	2018-04-24 03:30:00
13262	1693	10	12	2018-05-03 19:00:00
13263	1693	10	12	2018-08-29 01:45:00
13264	1693	10	12	2019-10-03 20:15:00
13265	1693	10	12	2020-01-17 14:00:00
13266	1693	10	12	2020-01-02 09:15:00
13267	1693	10	12	2019-06-19 10:00:00
13268	1693	10	12	2018-07-30 06:15:00
13269	1694	4	13	2020-02-01 16:30:00
13270	1694	4	13	2018-11-21 08:45:00
13271	1694	4	13	2018-08-14 12:15:00
13272	1694	4	13	2020-01-22 02:15:00
13273	1694	4	13	2019-12-15 17:30:00
13274	1694	4	13	2019-06-10 23:45:00
13275	1694	4	13	2018-06-07 02:30:00
13276	1694	4	13	2018-04-10 03:15:00
13277	1695	20	4	2018-11-14 11:15:00
13278	1695	20	4	2019-12-26 15:45:00
13279	1695	20	4	2018-12-01 21:30:00
13280	1695	20	4	2020-01-18 08:30:00
13281	1695	20	4	2019-06-28 14:00:00
13282	1695	20	4	2019-03-12 17:30:00
13283	1695	20	4	2019-08-13 21:15:00
13284	1696	19	19	2019-08-11 18:00:00
13285	1696	19	19	2020-03-09 10:15:00
13286	1696	19	19	2020-10-11 14:15:00
13287	1696	19	19	2019-09-23 07:00:00
13288	1696	19	19	2019-10-30 02:15:00
13289	1696	19	19	2020-02-23 08:45:00
13290	1696	19	19	2019-11-13 11:00:00
13291	1696	19	19	2020-09-17 11:45:00
13292	1696	19	19	2020-11-21 09:45:00
13293	1696	19	19	2019-04-03 22:00:00
13294	1696	19	19	2020-06-17 02:30:00
13295	1696	19	19	2019-10-18 15:30:00
13296	1697	2	13	2018-10-15 11:15:00
13297	1697	2	13	2019-03-03 23:15:00
13298	1697	2	13	2019-03-27 10:15:00
13299	1697	2	13	2019-04-04 05:30:00
13300	1697	2	13	2019-12-27 07:00:00
13301	1697	2	13	2018-08-16 21:00:00
13302	1697	2	13	2019-05-23 22:30:00
13303	1697	2	13	2019-10-23 22:45:00
13304	1697	2	13	2019-06-06 07:30:00
13305	1697	2	13	2019-07-30 08:45:00
13306	1697	2	13	2019-01-08 23:45:00
13307	1697	2	13	2019-11-01 15:00:00
13308	1697	2	13	2019-10-26 17:45:00
13309	1697	2	13	2018-11-02 21:30:00
13310	1698	8	11	2017-11-13 10:30:00
13311	1698	8	11	2017-08-24 11:15:00
13312	1698	8	11	2019-01-16 01:00:00
13313	1698	8	11	2018-11-12 12:00:00
13314	1698	8	11	2018-12-15 05:00:00
13315	1698	8	11	2019-04-15 08:15:00
13316	1698	8	11	2019-06-25 02:30:00
13317	1698	8	11	2018-10-11 02:45:00
13318	1698	8	11	2018-02-13 00:30:00
13319	1698	8	11	2019-01-15 03:00:00
13320	1698	8	11	2019-01-28 11:45:00
13321	1698	8	11	2018-10-04 19:15:00
13322	1698	8	11	2018-11-28 01:30:00
13323	1698	8	11	2018-02-04 11:45:00
13324	1698	8	11	2017-08-26 17:00:00
13325	1699	11	4	2018-10-06 13:45:00
13326	1699	11	4	2020-05-30 20:15:00
13327	1699	11	4	2019-02-01 15:45:00
13328	1699	11	4	2020-05-21 23:45:00
13329	1699	11	4	2019-01-27 15:30:00
13330	1699	11	4	2019-07-25 08:15:00
13331	1699	11	4	2019-02-05 21:15:00
13332	1700	20	8	2020-01-24 16:45:00
13333	1701	12	4	2018-12-14 22:15:00
13334	1701	12	4	2018-07-16 02:00:00
13335	1701	12	4	2019-03-05 11:00:00
13336	1701	12	4	2019-02-04 02:30:00
13337	1701	12	4	2020-01-08 02:15:00
13338	1701	12	4	2019-07-17 17:15:00
13339	1701	12	4	2018-10-13 06:30:00
13340	1701	12	4	2018-04-24 05:30:00
13341	1701	12	4	2019-11-21 14:45:00
13342	1701	12	4	2019-12-19 17:15:00
13343	1701	12	4	2019-06-14 07:30:00
13344	1701	12	4	2019-07-16 22:00:00
13345	1701	12	4	2018-03-30 10:00:00
13346	1701	12	4	2019-04-04 21:00:00
13347	1702	6	4	2019-05-13 21:45:00
13348	1702	6	4	2019-02-11 09:30:00
13349	1702	6	4	2019-10-29 12:00:00
13350	1702	6	4	2019-05-20 21:45:00
13351	1702	6	4	2018-04-14 03:15:00
13352	1702	6	4	2018-12-19 19:45:00
13353	1702	6	4	2018-07-25 14:00:00
13354	1702	6	4	2019-11-07 17:45:00
13355	1702	6	4	2019-12-30 08:30:00
13356	1703	1	11	2018-02-26 16:15:00
13357	1703	1	11	2018-11-27 05:00:00
13358	1703	1	11	2017-06-19 22:15:00
13359	1703	1	11	2018-04-26 00:45:00
13360	1703	1	11	2018-07-24 23:15:00
13361	1703	1	11	2017-03-13 13:45:00
13362	1703	1	11	2019-01-01 01:00:00
13363	1703	1	11	2018-03-05 01:45:00
13364	1703	1	11	2017-05-19 22:15:00
13365	1703	1	11	2018-03-28 14:30:00
13366	1703	1	11	2017-08-03 20:45:00
13367	1704	9	16	2020-09-26 07:15:00
13368	1705	5	14	2018-11-27 16:00:00
13369	1705	5	14	2018-06-14 15:45:00
13370	1705	5	14	2018-07-22 00:00:00
13371	1705	5	14	2018-01-01 03:45:00
13372	1705	5	14	2018-08-10 10:45:00
13373	1705	5	14	2018-02-23 06:45:00
13374	1705	5	14	2018-07-04 05:15:00
13375	1705	5	14	2017-10-26 07:00:00
13376	1706	17	8	2018-11-19 09:00:00
13377	1706	17	8	2019-09-14 22:45:00
13378	1706	17	8	2019-02-08 18:30:00
13379	1706	17	8	2019-10-29 09:30:00
13380	1706	17	8	2019-03-20 08:30:00
13381	1706	17	8	2019-10-23 18:45:00
13382	1707	13	17	2020-04-11 20:15:00
13383	1707	13	17	2020-09-11 20:15:00
13384	1707	13	17	2018-12-19 06:30:00
13385	1707	13	17	2020-01-17 18:00:00
13386	1707	13	17	2019-12-13 13:15:00
13387	1707	13	17	2019-11-05 22:45:00
13388	1707	13	17	2020-08-15 08:00:00
13389	1707	13	17	2019-08-05 09:45:00
13390	1707	13	17	2020-01-17 11:30:00
13391	1707	13	17	2019-02-02 13:00:00
13392	1707	13	17	2020-04-14 07:00:00
13393	1707	13	17	2019-12-23 21:45:00
13394	1707	13	17	2020-06-12 21:45:00
13395	1707	13	17	2020-09-19 18:45:00
13396	1708	19	5	2018-05-15 10:30:00
13397	1708	19	5	2018-08-26 05:00:00
13398	1709	17	5	2021-03-06 06:45:00
13399	1709	17	5	2021-01-04 13:15:00
13400	1709	17	5	2021-05-12 00:30:00
13401	1709	17	5	2021-07-05 09:00:00
13402	1709	17	5	2021-05-14 20:45:00
13403	1709	17	5	2021-01-13 10:45:00
13404	1709	17	5	2020-10-20 05:30:00
13405	1709	17	5	2020-12-09 07:45:00
13406	1709	17	5	2020-03-02 10:45:00
13407	1710	5	15	2020-08-30 17:45:00
13408	1710	5	15	2020-08-28 10:45:00
13409	1710	5	15	2019-09-27 12:00:00
13410	1710	5	15	2019-09-04 17:00:00
13411	1710	5	15	2020-05-10 12:45:00
13412	1710	5	15	2020-01-30 23:45:00
13413	1710	5	15	2019-02-07 06:15:00
13414	1711	12	6	2020-12-26 23:00:00
13415	1711	12	6	2020-05-25 23:45:00
13416	1711	12	6	2020-02-04 21:15:00
13417	1711	12	6	2020-03-22 04:30:00
13418	1711	12	6	2021-04-29 06:45:00
13419	1711	12	6	2020-07-22 01:30:00
13420	1711	12	6	2020-07-19 15:15:00
13421	1711	12	6	2019-08-20 06:45:00
13422	1711	12	6	2020-10-15 05:00:00
13423	1711	12	6	2019-12-06 03:45:00
13424	1711	12	6	2020-12-17 17:30:00
13425	1711	12	6	2020-06-24 10:45:00
13426	1711	12	6	2020-12-30 03:15:00
13427	1711	12	6	2020-12-12 20:30:00
13428	1712	5	1	2021-06-13 06:45:00
13429	1712	5	1	2020-11-15 02:45:00
13430	1712	5	1	2021-06-04 09:30:00
13431	1712	5	1	2020-03-06 11:00:00
13432	1712	5	1	2019-10-25 05:45:00
13433	1712	5	1	2020-10-14 07:15:00
13434	1712	5	1	2020-12-22 16:15:00
13435	1712	5	1	2020-04-16 14:15:00
13436	1712	5	1	2020-03-20 06:15:00
13437	1712	5	1	2021-05-14 21:15:00
13438	1712	5	1	2020-06-05 03:15:00
13439	1712	5	1	2021-08-16 22:15:00
13440	1712	5	1	2019-09-14 08:15:00
13441	1712	5	1	2020-05-21 08:45:00
13442	1712	5	1	2021-03-09 05:15:00
13443	1713	5	11	2019-01-19 13:15:00
13444	1713	5	11	2018-04-26 17:00:00
13445	1713	5	11	2019-01-24 11:45:00
13446	1713	5	11	2019-05-04 18:15:00
13447	1713	5	11	2019-04-12 01:45:00
13448	1713	5	11	2018-11-02 04:30:00
13449	1713	5	11	2018-10-26 12:30:00
13450	1713	5	11	2019-01-03 15:45:00
13451	1713	5	11	2018-10-25 04:30:00
13452	1713	5	11	2018-04-01 07:45:00
13453	1713	5	11	2019-08-12 22:45:00
13454	1713	5	11	2018-06-14 15:30:00
13455	1714	1	2	2021-04-08 22:30:00
13456	1714	1	2	2019-09-12 19:45:00
13457	1714	1	2	2021-01-18 12:30:00
13458	1714	1	2	2021-04-25 00:15:00
13459	1714	1	2	2020-05-03 06:45:00
13460	1714	1	2	2020-06-01 06:15:00
13461	1714	1	2	2021-05-08 15:00:00
13462	1714	1	2	2021-02-12 06:00:00
13463	1715	6	7	2019-09-28 17:45:00
13464	1715	6	7	2019-10-30 20:00:00
13465	1715	6	7	2020-06-29 08:00:00
13466	1715	6	7	2020-08-07 06:00:00
13467	1715	6	7	2019-08-12 21:45:00
13468	1715	6	7	2020-08-17 13:30:00
13469	1715	6	7	2020-04-04 06:45:00
13470	1716	15	20	2019-09-30 00:30:00
13471	1716	15	20	2019-08-05 14:45:00
13472	1716	15	20	2019-11-26 00:30:00
13473	1716	15	20	2019-06-07 05:00:00
13474	1716	15	20	2020-09-02 09:00:00
13475	1716	15	20	2019-07-25 13:45:00
13476	1716	15	20	2020-05-12 23:00:00
13477	1716	15	20	2020-10-15 22:30:00
13478	1716	15	20	2019-08-06 16:15:00
13479	1716	15	20	2019-06-09 04:15:00
13480	1717	6	12	2017-04-18 09:15:00
13481	1717	6	12	2017-03-05 01:00:00
13482	1717	6	12	2017-07-03 21:00:00
13483	1717	6	12	2018-03-18 09:30:00
13484	1718	19	3	2020-05-26 00:15:00
13485	1718	19	3	2020-10-05 20:15:00
13486	1718	19	3	2020-01-21 07:30:00
13487	1718	19	3	2019-09-21 12:30:00
13488	1718	19	3	2020-07-02 03:00:00
13489	1718	19	3	2021-05-16 18:30:00
13490	1718	19	3	2020-07-01 05:00:00
13491	1718	19	3	2020-09-08 05:15:00
13492	1719	18	13	2017-10-15 08:15:00
13493	1719	18	13	2018-01-13 23:00:00
13494	1719	18	13	2018-02-24 04:45:00
13495	1719	18	13	2019-03-23 01:30:00
13496	1719	18	13	2018-06-25 22:45:00
13497	1719	18	13	2018-10-09 03:45:00
13498	1719	18	13	2019-01-09 15:15:00
13499	1719	18	13	2019-04-07 18:30:00
13500	1719	18	13	2018-10-29 19:00:00
13501	1720	1	4	2019-12-13 06:00:00
13502	1720	1	4	2019-04-07 17:45:00
13503	1720	1	4	2019-12-04 04:00:00
13504	1720	1	4	2018-03-24 15:45:00
13505	1721	9	13	2018-01-01 19:30:00
13506	1721	9	13	2017-06-10 23:45:00
13507	1721	9	13	2017-05-14 03:30:00
13508	1721	9	13	2019-01-24 09:30:00
13509	1721	9	13	2019-04-05 02:00:00
13510	1721	9	13	2018-11-16 08:45:00
13511	1721	9	13	2018-12-02 06:15:00
13512	1721	9	13	2018-01-05 11:45:00
13513	1721	9	13	2017-05-27 13:15:00
13514	1721	9	13	2017-10-10 01:15:00
13515	1721	9	13	2019-03-02 21:00:00
13516	1721	9	13	2018-11-29 00:30:00
13517	1721	9	13	2018-08-14 08:15:00
13518	1722	12	17	2019-11-21 14:45:00
13519	1722	12	17	2018-06-10 23:45:00
13520	1723	13	2	2018-11-05 18:30:00
13521	1723	13	2	2019-12-29 03:30:00
13522	1723	13	2	2019-06-15 07:00:00
13523	1723	13	2	2020-06-26 06:00:00
13524	1723	13	2	2019-07-22 20:15:00
13525	1723	13	2	2019-02-10 00:00:00
13526	1723	13	2	2019-04-26 19:45:00
13527	1723	13	2	2020-08-13 21:30:00
13528	1723	13	2	2020-07-25 06:00:00
13529	1724	1	10	2019-04-06 20:15:00
13530	1724	1	10	2018-11-17 01:00:00
13531	1724	1	10	2019-02-02 23:00:00
13532	1724	1	10	2018-09-23 19:00:00
13533	1724	1	10	2019-10-08 15:30:00
13534	1724	1	10	2019-08-25 22:00:00
13535	1724	1	10	2019-08-11 18:00:00
13536	1724	1	10	2019-09-20 02:45:00
13537	1724	1	10	2020-05-23 00:45:00
13538	1724	1	10	2020-02-22 18:30:00
13539	1724	1	10	2020-01-16 09:00:00
13540	1725	4	16	2017-05-15 07:45:00
13541	1725	4	16	2017-06-11 02:00:00
13542	1725	4	16	2018-04-20 05:15:00
13543	1725	4	16	2018-02-02 00:00:00
13544	1725	4	16	2017-09-04 01:30:00
13545	1725	4	16	2017-07-16 02:30:00
13546	1725	4	16	2017-06-11 16:15:00
13547	1725	4	16	2018-08-16 06:15:00
13548	1725	4	16	2018-05-17 20:15:00
13549	1725	4	16	2018-10-18 05:15:00
13550	1725	4	16	2017-03-15 21:00:00
13551	1725	4	16	2019-02-03 04:15:00
13552	1725	4	16	2018-11-16 21:00:00
13553	1725	4	16	2018-05-23 04:30:00
13554	1726	1	4	2018-01-03 14:45:00
13555	1726	1	4	2018-11-04 12:15:00
13556	1726	1	4	2018-09-13 19:45:00
13557	1726	1	4	2019-01-04 21:45:00
13558	1726	1	4	2018-08-26 18:45:00
13559	1726	1	4	2018-05-10 06:00:00
13560	1726	1	4	2018-11-30 00:45:00
13561	1726	1	4	2018-08-18 04:15:00
13562	1726	1	4	2017-12-08 23:00:00
13563	1726	1	4	2018-01-12 20:15:00
13564	1726	1	4	2018-07-01 02:45:00
13565	1726	1	4	2019-02-03 01:00:00
13566	1726	1	4	2017-12-30 23:00:00
13567	1726	1	4	2019-01-04 03:45:00
13568	1726	1	4	2017-08-02 11:30:00
13569	1727	3	14	2020-05-13 12:45:00
13570	1727	3	14	2021-02-07 16:15:00
13571	1727	3	14	2020-08-08 05:00:00
13572	1727	3	14	2020-09-23 00:30:00
13573	1727	3	14	2019-08-04 07:30:00
13574	1727	3	14	2020-01-06 15:30:00
13575	1727	3	14	2020-03-25 10:45:00
13576	1727	3	14	2019-10-29 20:45:00
13577	1728	9	18	2020-09-23 16:15:00
13578	1728	9	18	2020-11-23 09:15:00
13579	1728	9	18	2021-06-09 06:30:00
13580	1728	9	18	2021-12-22 19:45:00
13581	1728	9	18	2020-02-05 19:00:00
13582	1728	9	18	2021-07-08 00:00:00
13583	1728	9	18	2021-12-24 04:45:00
13584	1729	14	3	2019-05-03 06:15:00
13585	1729	14	3	2020-09-04 02:00:00
13586	1729	14	3	2020-06-19 17:00:00
13587	1729	14	3	2020-10-05 00:30:00
13588	1729	14	3	2020-10-28 01:30:00
13589	1729	14	3	2018-12-13 23:00:00
13590	1729	14	3	2019-06-21 23:30:00
13591	1729	14	3	2020-11-28 03:15:00
13592	1729	14	3	2019-09-10 12:45:00
13593	1730	5	17	2017-09-05 07:15:00
13594	1730	5	17	2017-04-25 03:00:00
13595	1730	5	17	2018-07-21 03:15:00
13596	1730	5	17	2019-03-10 18:15:00
13597	1730	5	17	2018-02-19 20:45:00
13598	1731	15	3	2018-07-24 03:45:00
13599	1731	15	3	2019-07-26 21:15:00
13600	1731	15	3	2018-07-23 03:45:00
13601	1731	15	3	2018-09-12 07:45:00
13602	1731	15	3	2019-01-24 23:15:00
13603	1731	15	3	2019-08-02 19:30:00
13604	1731	15	3	2018-12-11 07:00:00
13605	1731	15	3	2019-04-08 04:30:00
13606	1731	15	3	2019-07-18 04:45:00
13607	1731	15	3	2018-06-03 20:30:00
13608	1731	15	3	2019-03-13 12:45:00
13609	1731	15	3	2019-05-05 21:00:00
13610	1731	15	3	2019-01-09 13:15:00
13611	1731	15	3	2019-02-03 09:15:00
13612	1732	1	4	2019-02-04 13:30:00
13613	1733	5	16	2020-05-12 00:30:00
13614	1733	5	16	2019-06-16 06:00:00
13615	1733	5	16	2019-09-12 06:00:00
13616	1733	5	16	2018-11-15 17:45:00
13617	1733	5	16	2020-02-03 10:00:00
13618	1733	5	16	2020-08-30 03:30:00
13619	1733	5	16	2019-07-10 23:45:00
13620	1733	5	16	2019-04-30 15:15:00
13621	1733	5	16	2020-02-03 20:45:00
13622	1733	5	16	2018-11-17 20:30:00
13623	1733	5	16	2019-04-10 16:30:00
13624	1733	5	16	2020-02-10 07:15:00
13625	1734	13	9	2020-02-16 16:45:00
13626	1734	13	9	2018-11-28 07:45:00
13627	1734	13	9	2019-01-18 19:15:00
13628	1734	13	9	2020-01-18 18:45:00
13629	1734	13	9	2020-03-30 19:45:00
13630	1734	13	9	2019-10-23 22:30:00
13631	1734	13	9	2019-08-23 21:00:00
13632	1734	13	9	2019-08-01 23:00:00
13633	1734	13	9	2019-02-15 05:00:00
13634	1734	13	9	2019-02-13 09:30:00
13635	1734	13	9	2020-01-14 01:00:00
13636	1734	13	9	2019-10-05 11:30:00
13637	1734	13	9	2020-02-15 18:45:00
13638	1734	13	9	2020-09-05 16:30:00
13639	1735	17	15	2018-06-15 08:15:00
13640	1735	17	15	2019-07-08 11:45:00
13641	1735	17	15	2018-06-17 21:30:00
13642	1735	17	15	2018-12-17 03:15:00
13643	1735	17	15	2020-03-28 08:00:00
13644	1735	17	15	2018-06-23 18:45:00
13645	1735	17	15	2020-02-19 08:00:00
13646	1735	17	15	2019-07-14 17:45:00
13647	1735	17	15	2018-08-27 02:15:00
13648	1736	1	9	2019-08-24 18:00:00
13649	1736	1	9	2019-06-04 06:45:00
13650	1736	1	9	2019-07-01 16:45:00
13651	1736	1	9	2018-08-13 08:30:00
13652	1736	1	9	2018-09-15 13:00:00
13653	1736	1	9	2018-02-23 16:30:00
13654	1736	1	9	2017-11-16 09:00:00
13655	1736	1	9	2018-08-15 19:00:00
13656	1736	1	9	2019-02-07 16:45:00
13657	1736	1	9	2018-01-21 23:00:00
13658	1736	1	9	2018-08-17 09:15:00
13659	1736	1	9	2019-09-06 01:45:00
13660	1737	6	3	2021-08-24 10:45:00
13661	1737	6	3	2020-06-08 23:45:00
13662	1737	6	3	2020-09-16 23:15:00
13663	1737	6	3	2020-03-04 19:30:00
13664	1737	6	3	2021-08-16 18:45:00
13665	1737	6	3	2020-01-04 09:30:00
13666	1737	6	3	2020-02-07 10:00:00
13667	1737	6	3	2020-05-05 16:15:00
13668	1737	6	3	2020-09-11 01:45:00
13669	1737	6	3	2020-07-13 07:15:00
13670	1737	6	3	2021-01-27 21:30:00
13671	1737	6	3	2021-12-06 07:15:00
13672	1737	6	3	2020-11-30 17:00:00
13673	1738	5	17	2019-11-06 06:30:00
13674	1738	5	17	2020-10-10 14:15:00
13675	1738	5	17	2020-01-04 12:30:00
13676	1738	5	17	2020-05-29 11:30:00
13677	1738	5	17	2020-03-29 02:15:00
13678	1738	5	17	2019-12-11 05:30:00
13679	1738	5	17	2021-05-27 15:45:00
13680	1738	5	17	2021-03-11 05:30:00
13681	1738	5	17	2019-11-02 05:30:00
13682	1739	13	19	2020-06-18 08:30:00
13683	1739	13	19	2021-08-28 12:30:00
13684	1739	13	19	2020-05-14 13:00:00
13685	1739	13	19	2020-06-28 18:45:00
13686	1739	13	19	2021-02-02 07:45:00
13687	1739	13	19	2019-12-22 21:45:00
13688	1739	13	19	2019-11-22 08:30:00
13689	1739	13	19	2020-08-11 02:45:00
13690	1739	13	19	2020-05-11 03:45:00
13691	1740	13	3	2019-11-08 13:30:00
13692	1740	13	3	2019-10-05 10:00:00
13693	1740	13	3	2018-10-07 12:00:00
13694	1740	13	3	2019-01-03 09:30:00
13695	1740	13	3	2018-09-10 12:30:00
13696	1740	13	3	2018-10-27 05:15:00
13697	1740	13	3	2020-01-30 17:30:00
13698	1740	13	3	2019-07-27 04:45:00
13699	1740	13	3	2019-11-10 03:45:00
13700	1740	13	3	2020-02-02 23:00:00
13701	1740	13	3	2018-07-10 01:00:00
13702	1740	13	3	2018-06-25 12:00:00
13703	1740	13	3	2019-10-04 09:15:00
13704	1740	13	3	2019-05-16 11:30:00
13705	1741	8	17	2019-09-24 20:30:00
13706	1741	8	17	2018-04-13 04:45:00
13707	1741	8	17	2018-10-06 10:45:00
13708	1741	8	17	2019-01-23 07:30:00
13709	1741	8	17	2019-12-15 09:15:00
13710	1741	8	17	2019-07-06 13:00:00
13711	1741	8	17	2019-08-25 05:15:00
13712	1742	19	3	2018-06-24 09:00:00
13713	1742	19	3	2018-02-24 05:45:00
13714	1743	4	19	2018-08-23 04:45:00
13715	1744	11	17	2019-11-04 13:15:00
13716	1744	11	17	2020-11-10 06:45:00
13717	1744	11	17	2020-12-07 01:30:00
13718	1744	11	17	2020-12-28 20:45:00
13719	1744	11	17	2020-07-18 19:30:00
13720	1744	11	17	2019-10-28 06:45:00
13721	1744	11	17	2021-07-23 08:00:00
13722	1744	11	17	2020-08-14 19:00:00
13723	1744	11	17	2019-09-20 08:15:00
13724	1744	11	17	2020-10-19 06:00:00
13725	1745	4	6	2020-12-18 02:00:00
13726	1745	4	6	2019-03-09 04:00:00
13727	1745	4	6	2019-03-26 22:45:00
13728	1745	4	6	2019-11-20 00:00:00
13729	1745	4	6	2020-11-19 04:15:00
13730	1745	4	6	2019-11-18 09:15:00
13731	1746	18	14	2017-05-21 15:00:00
13732	1746	18	14	2018-02-20 04:30:00
13733	1746	18	14	2017-07-15 09:15:00
13734	1747	7	12	2018-08-05 13:30:00
13735	1748	11	6	2019-04-06 16:00:00
13736	1748	11	6	2019-10-20 03:45:00
13737	1748	11	6	2019-08-21 22:00:00
13738	1748	11	6	2018-08-21 06:15:00
13739	1748	11	6	2018-10-24 09:00:00
13740	1748	11	6	2019-05-01 20:45:00
13741	1748	11	6	2018-04-16 03:30:00
13742	1748	11	6	2019-06-22 20:15:00
13743	1748	11	6	2019-07-16 19:30:00
13744	1748	11	6	2018-01-13 10:30:00
13745	1748	11	6	2019-01-08 03:15:00
13746	1748	11	6	2018-12-01 04:00:00
13747	1748	11	6	2019-03-28 11:00:00
13748	1748	11	6	2019-11-29 12:00:00
13749	1749	18	12	2019-05-25 20:00:00
13750	1749	18	12	2020-05-12 21:15:00
13751	1749	18	12	2019-05-26 21:30:00
13752	1749	18	12	2019-06-12 02:15:00
13753	1750	7	11	2019-11-06 04:15:00
13754	1750	7	11	2018-12-11 03:00:00
13755	1750	7	11	2018-06-04 17:15:00
13756	1750	7	11	2019-02-07 00:00:00
13757	1750	7	11	2018-07-14 02:00:00
13758	1750	7	11	2018-11-13 03:00:00
13759	1750	7	11	2019-03-05 22:00:00
13760	1750	7	11	2018-09-22 18:30:00
13761	1750	7	11	2019-09-19 18:30:00
13762	1751	7	11	2018-01-06 17:00:00
13763	1751	7	11	2018-11-21 14:00:00
13764	1751	7	11	2019-07-08 15:15:00
13765	1751	7	11	2018-02-17 20:00:00
13766	1751	7	11	2019-04-06 20:15:00
13767	1751	7	11	2018-05-20 18:15:00
13768	1751	7	11	2019-02-01 14:30:00
13769	1751	7	11	2019-01-09 14:30:00
13770	1751	7	11	2018-08-11 00:30:00
13771	1751	7	11	2019-04-06 19:45:00
13772	1751	7	11	2018-01-01 19:30:00
13773	1751	7	11	2018-09-27 03:45:00
13774	1752	9	17	2017-10-17 15:00:00
13775	1752	9	17	2019-01-01 15:45:00
13776	1752	9	17	2018-10-23 01:45:00
13777	1752	9	17	2018-10-09 16:00:00
13778	1752	9	17	2018-06-03 09:15:00
13779	1752	9	17	2018-05-30 12:30:00
13780	1752	9	17	2018-10-09 16:30:00
13781	1752	9	17	2017-11-30 13:30:00
13782	1752	9	17	2017-04-23 09:15:00
13783	1753	20	5	2018-12-10 05:00:00
13784	1753	20	5	2018-06-24 03:45:00
13785	1753	20	5	2017-09-11 18:45:00
13786	1753	20	5	2019-01-06 21:15:00
13787	1753	20	5	2017-05-15 18:45:00
13788	1753	20	5	2018-12-02 00:30:00
13789	1753	20	5	2018-04-03 17:00:00
13790	1753	20	5	2018-07-09 18:30:00
13791	1753	20	5	2018-02-07 09:45:00
13792	1753	20	5	2017-04-30 13:30:00
13793	1753	20	5	2018-11-04 04:45:00
13794	1754	13	11	2019-11-20 11:00:00
13795	1754	13	11	2018-11-29 19:00:00
13796	1754	13	11	2019-01-18 05:30:00
13797	1754	13	11	2019-11-30 23:15:00
13798	1754	13	11	2018-07-13 15:30:00
13799	1754	13	11	2018-06-09 16:00:00
13800	1754	13	11	2018-11-19 13:45:00
13801	1754	13	11	2020-01-05 17:45:00
13802	1754	13	11	2019-08-12 11:30:00
13803	1754	13	11	2018-11-06 22:45:00
13804	1754	13	11	2018-04-06 15:30:00
13805	1754	13	11	2019-06-30 10:15:00
13806	1754	13	11	2018-02-04 11:00:00
13807	1754	13	11	2019-03-14 04:45:00
13808	1755	4	5	2017-07-29 00:45:00
13809	1755	4	5	2017-06-21 05:45:00
13810	1755	4	5	2018-09-29 19:30:00
13811	1755	4	5	2018-09-08 00:00:00
13812	1755	4	5	2018-12-21 23:45:00
13813	1755	4	5	2018-12-14 01:30:00
13814	1755	4	5	2017-11-30 06:30:00
13815	1755	4	5	2017-05-25 19:15:00
13816	1755	4	5	2017-02-02 09:45:00
13817	1755	4	5	2017-03-13 15:45:00
13818	1755	4	5	2018-09-12 14:00:00
13819	1755	4	5	2018-08-30 05:00:00
13820	1755	4	5	2018-03-05 21:00:00
13821	1756	14	4	2019-07-20 00:15:00
13822	1757	14	20	2019-06-06 08:45:00
13823	1757	14	20	2019-03-19 20:15:00
13824	1757	14	20	2020-09-04 09:45:00
13825	1757	14	20	2020-05-26 00:15:00
13826	1757	14	20	2020-06-11 04:30:00
13827	1757	14	20	2020-07-01 16:30:00
13828	1757	14	20	2020-09-23 04:45:00
13829	1757	14	20	2018-11-09 10:15:00
13830	1757	14	20	2019-03-16 15:15:00
13831	1757	14	20	2020-04-09 18:15:00
13832	1758	5	9	2020-08-02 14:15:00
13833	1758	5	9	2019-02-01 09:00:00
13834	1758	5	9	2018-09-07 05:00:00
13835	1758	5	9	2020-03-22 18:30:00
13836	1758	5	9	2018-12-02 13:15:00
13837	1758	5	9	2020-02-14 13:15:00
13838	1758	5	9	2018-09-23 21:45:00
13839	1758	5	9	2018-09-06 14:45:00
13840	1758	5	9	2019-12-13 11:30:00
13841	1758	5	9	2019-03-12 17:15:00
13842	1758	5	9	2019-10-14 13:15:00
13843	1758	5	9	2020-01-03 01:30:00
13844	1758	5	9	2019-11-04 12:45:00
13845	1758	5	9	2019-02-06 09:30:00
13846	1759	6	18	2019-01-18 21:45:00
13847	1760	18	8	2019-12-17 15:15:00
13848	1760	18	8	2021-03-04 19:30:00
13849	1760	18	8	2020-07-03 16:15:00
13850	1760	18	8	2019-06-05 23:00:00
13851	1760	18	8	2020-11-27 03:00:00
13852	1760	18	8	2020-01-25 01:15:00
13853	1760	18	8	2020-01-25 22:15:00
13854	1760	18	8	2019-12-25 07:45:00
13855	1760	18	8	2021-01-19 14:30:00
13856	1760	18	8	2021-03-21 17:30:00
13857	1761	2	5	2020-03-03 05:30:00
13858	1761	2	5	2020-01-19 02:45:00
13859	1761	2	5	2020-09-22 02:45:00
13860	1762	17	14	2020-02-01 13:15:00
13861	1762	17	14	2021-06-13 12:45:00
13862	1762	17	14	2019-08-29 11:30:00
13863	1763	7	16	2018-09-18 02:45:00
13864	1763	7	16	2018-05-02 04:15:00
13865	1763	7	16	2018-12-21 09:15:00
13866	1763	7	16	2017-11-10 03:45:00
13867	1763	7	16	2018-01-29 21:30:00
13868	1763	7	16	2018-12-20 03:45:00
13869	1763	7	16	2017-02-27 02:30:00
13870	1763	7	16	2017-06-15 08:15:00
13871	1763	7	16	2017-06-10 04:45:00
13872	1763	7	16	2017-03-14 13:30:00
13873	1763	7	16	2017-07-09 15:15:00
13874	1764	20	11	2020-02-10 18:15:00
13875	1764	20	11	2020-09-23 16:15:00
13876	1764	20	11	2019-12-08 04:30:00
13877	1764	20	11	2019-02-01 13:30:00
13878	1765	4	1	2019-02-02 19:45:00
13879	1765	4	1	2020-02-09 19:00:00
13880	1765	4	1	2020-01-27 12:30:00
13881	1765	4	1	2019-07-08 22:30:00
13882	1765	4	1	2019-08-29 00:00:00
13883	1765	4	1	2020-04-24 15:30:00
13884	1765	4	1	2020-05-01 10:30:00
13885	1765	4	1	2019-04-17 03:00:00
13886	1765	4	1	2019-10-29 02:45:00
13887	1765	4	1	2019-02-17 02:15:00
13888	1765	4	1	2020-05-21 16:30:00
13889	1765	4	1	2018-08-29 03:15:00
13890	1766	19	4	2021-06-18 01:30:00
13891	1766	19	4	2021-07-12 03:30:00
13892	1766	19	4	2020-07-10 03:30:00
13893	1766	19	4	2020-12-15 15:15:00
13894	1766	19	4	2020-08-28 07:30:00
13895	1766	19	4	2020-12-17 05:00:00
13896	1766	19	4	2021-01-06 04:15:00
13897	1766	19	4	2021-04-16 11:30:00
13898	1767	11	18	2019-07-20 09:00:00
13899	1767	11	18	2018-12-20 15:00:00
13900	1767	11	18	2019-05-07 02:45:00
13901	1767	11	18	2018-12-27 13:30:00
13902	1767	11	18	2018-05-18 05:00:00
13903	1767	11	18	2018-09-10 23:15:00
13904	1767	11	18	2017-10-30 14:00:00
13905	1767	11	18	2018-02-12 05:45:00
13906	1767	11	18	2018-07-13 22:45:00
13907	1767	11	18	2017-10-26 06:15:00
13908	1767	11	18	2018-05-27 20:15:00
13909	1767	11	18	2019-03-11 22:45:00
13910	1767	11	18	2018-03-06 16:30:00
13911	1767	11	18	2018-07-23 23:15:00
13912	1767	11	18	2019-06-08 07:00:00
13913	1768	1	14	2021-04-12 05:45:00
13914	1768	1	14	2020-06-25 03:30:00
13915	1768	1	14	2021-07-11 07:45:00
13916	1768	1	14	2021-04-17 04:45:00
13917	1768	1	14	2020-08-13 03:30:00
13918	1768	1	14	2021-04-30 03:30:00
13919	1768	1	14	2020-10-08 15:00:00
13920	1768	1	14	2020-07-07 18:30:00
13921	1769	20	18	2019-10-24 23:00:00
13922	1770	10	12	2019-05-09 10:45:00
13923	1770	10	12	2018-10-19 05:15:00
13924	1770	10	12	2018-06-16 15:15:00
13925	1770	10	12	2019-06-02 15:00:00
13926	1770	10	12	2019-01-03 22:30:00
13927	1770	10	12	2019-03-06 12:30:00
13928	1770	10	12	2020-01-26 12:15:00
13929	1770	10	12	2019-10-08 17:45:00
13930	1770	10	12	2018-09-09 08:15:00
13931	1770	10	12	2018-10-24 10:45:00
13932	1771	3	9	2021-04-25 01:45:00
13933	1771	3	9	2020-01-28 22:45:00
13934	1771	3	9	2020-08-11 04:45:00
13935	1771	3	9	2020-03-07 17:30:00
13936	1771	3	9	2021-04-12 12:30:00
13937	1771	3	9	2020-04-19 18:00:00
13938	1771	3	9	2021-04-19 16:00:00
13939	1771	3	9	2020-04-08 14:15:00
13940	1771	3	9	2020-05-04 20:00:00
13941	1771	3	9	2021-11-12 06:30:00
13942	1772	18	10	2020-01-11 13:30:00
13943	1772	18	10	2021-02-26 22:00:00
13944	1772	18	10	2020-04-03 19:00:00
13945	1772	18	10	2021-12-09 13:15:00
13946	1772	18	10	2020-03-24 11:15:00
13947	1772	18	10	2021-05-20 11:30:00
13948	1772	18	10	2020-05-07 13:15:00
13949	1773	6	1	2019-07-11 19:00:00
13950	1773	6	1	2020-06-18 10:15:00
13951	1773	6	1	2020-03-08 02:45:00
13952	1773	6	1	2020-05-23 18:15:00
13953	1773	6	1	2021-01-08 09:45:00
13954	1773	6	1	2020-01-08 13:30:00
13955	1773	6	1	2020-11-07 12:30:00
13956	1773	6	1	2020-01-30 09:00:00
13957	1773	6	1	2021-03-30 00:30:00
13958	1773	6	1	2021-05-13 03:15:00
13959	1773	6	1	2021-04-13 18:15:00
13960	1773	6	1	2021-01-14 20:15:00
13961	1774	4	6	2018-01-23 12:45:00
13962	1774	4	6	2017-06-05 23:00:00
13963	1774	4	6	2018-10-03 13:15:00
13964	1774	4	6	2019-01-18 18:30:00
13965	1774	4	6	2018-10-20 11:00:00
13966	1774	4	6	2017-07-01 02:00:00
13967	1774	4	6	2017-12-13 08:00:00
13968	1774	4	6	2018-08-19 13:30:00
13969	1774	4	6	2017-07-17 20:00:00
13970	1774	4	6	2017-12-21 23:00:00
13971	1774	4	6	2017-09-11 12:30:00
13972	1775	14	10	2019-05-24 09:15:00
13973	1776	3	9	2020-01-04 01:00:00
13974	1776	3	9	2019-08-29 00:30:00
13975	1776	3	9	2019-05-01 08:00:00
13976	1776	3	9	2020-03-23 14:15:00
13977	1777	13	10	2018-07-25 19:45:00
13978	1777	13	10	2019-02-20 01:00:00
13979	1777	13	10	2017-08-01 23:45:00
13980	1777	13	10	2019-04-20 20:45:00
13981	1777	13	10	2018-11-02 14:30:00
13982	1777	13	10	2018-05-26 23:00:00
13983	1777	13	10	2017-06-29 09:30:00
13984	1777	13	10	2018-07-08 09:45:00
13985	1777	13	10	2018-12-12 16:30:00
13986	1777	13	10	2018-05-26 09:45:00
13987	1777	13	10	2018-02-23 01:15:00
13988	1778	19	14	2020-08-24 04:45:00
13989	1778	19	14	2019-05-12 11:30:00
13990	1779	11	14	2018-10-10 14:45:00
13991	1779	11	14	2019-08-14 01:30:00
13992	1779	11	14	2018-07-18 10:15:00
13993	1779	11	14	2020-02-12 05:30:00
13994	1779	11	14	2019-10-14 23:15:00
13995	1779	11	14	2019-10-04 18:15:00
13996	1779	11	14	2019-12-18 06:45:00
13997	1779	11	14	2019-08-26 23:15:00
13998	1779	11	14	2019-03-15 16:15:00
13999	1779	11	14	2019-01-09 07:00:00
14000	1779	11	14	2019-02-02 04:45:00
14001	1779	11	14	2019-02-08 20:45:00
14002	1779	11	14	2019-10-18 00:00:00
14003	1779	11	14	2018-09-28 21:45:00
14004	1779	11	14	2019-01-15 02:45:00
14005	1780	2	12	2018-03-23 11:15:00
14006	1780	2	12	2018-02-19 05:45:00
14007	1780	2	12	2018-03-21 14:30:00
14008	1781	1	7	2019-03-02 12:00:00
14009	1781	1	7	2018-12-10 14:00:00
14010	1781	1	7	2019-03-08 06:00:00
14011	1781	1	7	2019-03-25 10:15:00
14012	1781	1	7	2019-01-30 05:00:00
14013	1781	1	7	2019-03-22 03:30:00
14014	1781	1	7	2019-07-07 15:45:00
14015	1781	1	7	2018-09-29 15:15:00
14016	1781	1	7	2019-09-12 02:00:00
14017	1781	1	7	2019-09-24 17:30:00
14018	1781	1	7	2019-05-07 20:00:00
14019	1781	1	7	2019-02-01 04:00:00
14020	1781	1	7	2019-11-29 09:30:00
14021	1782	19	6	2018-02-11 09:15:00
14022	1782	19	6	2017-07-11 01:15:00
14023	1782	19	6	2018-02-27 10:00:00
14024	1782	19	6	2018-10-13 03:30:00
14025	1783	19	17	2021-07-01 21:15:00
14026	1783	19	17	2021-07-16 13:00:00
14027	1783	19	17	2020-08-06 23:00:00
14028	1783	19	17	2021-09-25 02:15:00
14029	1784	9	5	2019-04-08 03:45:00
14030	1784	9	5	2019-11-22 03:00:00
14031	1784	9	5	2018-02-04 16:45:00
14032	1784	9	5	2018-02-04 04:30:00
14033	1784	9	5	2018-11-15 17:15:00
14034	1784	9	5	2018-01-03 15:45:00
14035	1784	9	5	2019-01-29 22:15:00
14036	1784	9	5	2018-02-04 02:00:00
14037	1784	9	5	2018-09-14 13:15:00
14038	1784	9	5	2019-01-27 12:00:00
14039	1784	9	5	2018-06-03 15:15:00
14040	1784	9	5	2018-03-08 09:00:00
14041	1784	9	5	2019-02-26 00:00:00
14042	1784	9	5	2019-05-27 09:45:00
14043	1784	9	5	2018-12-19 22:30:00
14044	1785	13	11	2017-05-06 18:15:00
14045	1786	8	10	2019-11-22 19:15:00
14046	1786	8	10	2021-05-08 20:15:00
14047	1786	8	10	2019-11-04 02:15:00
14048	1786	8	10	2020-05-23 04:45:00
14049	1786	8	10	2021-06-27 05:30:00
14050	1786	8	10	2021-08-07 04:00:00
14051	1786	8	10	2020-06-30 07:45:00
14052	1786	8	10	2020-01-22 14:30:00
14053	1786	8	10	2020-07-01 23:30:00
14054	1786	8	10	2021-06-05 07:00:00
14055	1786	8	10	2019-11-09 02:15:00
14056	1786	8	10	2020-06-20 04:45:00
14057	1786	8	10	2021-01-15 12:30:00
14058	1786	8	10	2020-06-20 02:30:00
14059	1786	8	10	2021-02-16 14:15:00
14060	1787	1	13	2020-02-14 00:15:00
14061	1787	1	13	2020-01-13 03:15:00
14062	1787	1	13	2020-06-12 17:30:00
14063	1787	1	13	2020-03-23 05:00:00
14064	1787	1	13	2020-12-30 20:45:00
14065	1787	1	13	2019-09-20 22:15:00
14066	1787	1	13	2019-08-09 08:45:00
14067	1787	1	13	2020-02-12 05:30:00
14068	1787	1	13	2020-07-19 03:15:00
14069	1788	1	1	2021-03-29 09:00:00
14070	1788	1	1	2021-01-05 10:00:00
14071	1788	1	1	2021-04-09 09:30:00
14072	1788	1	1	2020-11-11 19:15:00
14073	1788	1	1	2021-04-30 10:00:00
14074	1788	1	1	2019-12-23 11:15:00
14075	1788	1	1	2020-12-26 07:30:00
14076	1788	1	1	2020-09-10 13:00:00
14077	1788	1	1	2021-08-17 10:15:00
14078	1788	1	1	2021-04-11 02:00:00
14079	1788	1	1	2020-05-29 07:30:00
14080	1788	1	1	2021-02-21 12:00:00
14081	1788	1	1	2020-10-26 04:15:00
14082	1788	1	1	2021-10-26 06:45:00
14083	1789	13	9	2020-03-14 23:00:00
14084	1789	13	9	2021-11-19 19:00:00
14085	1789	13	9	2020-10-18 06:30:00
14086	1789	13	9	2020-06-16 17:45:00
14087	1789	13	9	2019-12-13 17:15:00
14088	1789	13	9	2021-11-15 03:15:00
14089	1789	13	9	2021-09-29 10:45:00
14090	1789	13	9	2021-04-14 16:00:00
14091	1789	13	9	2020-07-22 21:30:00
14092	1789	13	9	2021-01-26 00:45:00
14093	1790	11	7	2019-05-22 06:30:00
14094	1790	11	7	2018-09-22 10:30:00
14095	1790	11	7	2018-09-02 20:00:00
14096	1790	11	7	2019-03-13 03:15:00
14097	1790	11	7	2018-08-02 00:00:00
14098	1790	11	7	2019-12-23 00:30:00
14099	1790	11	7	2019-11-01 01:00:00
14100	1791	19	16	2020-11-27 21:30:00
14101	1791	19	16	2020-06-09 06:15:00
14102	1791	19	16	2020-11-02 17:45:00
14103	1792	4	4	2019-03-17 16:45:00
14104	1792	4	4	2020-01-11 13:45:00
14105	1792	4	4	2019-01-17 10:00:00
14106	1792	4	4	2018-03-05 17:30:00
14107	1792	4	4	2018-10-28 12:00:00
14108	1792	4	4	2019-10-17 01:15:00
14109	1792	4	4	2018-11-30 09:00:00
14110	1792	4	4	2018-03-07 20:30:00
14111	1792	4	4	2019-06-30 16:45:00
14112	1792	4	4	2019-11-30 04:15:00
14113	1792	4	4	2018-07-07 23:30:00
14114	1792	4	4	2019-09-14 09:30:00
14115	1792	4	4	2018-06-22 07:30:00
14116	1792	4	4	2019-03-22 22:30:00
14117	1792	4	4	2019-10-15 10:15:00
14118	1793	6	15	2018-07-18 12:30:00
14119	1793	6	15	2017-12-21 22:15:00
14120	1793	6	15	2017-07-09 23:15:00
14121	1793	6	15	2018-02-24 22:45:00
14122	1793	6	15	2017-07-11 02:45:00
14123	1793	6	15	2018-05-02 07:15:00
14124	1793	6	15	2017-09-05 01:15:00
14125	1794	6	17	2019-01-19 19:45:00
14126	1794	6	17	2018-04-19 23:00:00
14127	1794	6	17	2018-11-04 22:15:00
14128	1794	6	17	2017-12-07 02:00:00
14129	1794	6	17	2018-10-11 07:00:00
14130	1794	6	17	2019-08-10 11:45:00
14131	1794	6	17	2018-12-25 04:45:00
14132	1795	15	4	2018-10-12 15:00:00
14133	1795	15	4	2019-02-05 05:00:00
14134	1795	15	4	2018-08-28 06:30:00
14135	1795	15	4	2018-09-27 19:00:00
14136	1795	15	4	2019-04-04 21:00:00
14137	1795	15	4	2019-07-26 02:00:00
14138	1796	13	3	2018-07-06 14:30:00
14139	1796	13	3	2018-03-11 01:15:00
14140	1796	13	3	2018-12-24 22:00:00
14141	1796	13	3	2018-01-07 01:15:00
14142	1796	13	3	2019-08-09 02:00:00
14143	1796	13	3	2018-11-11 01:45:00
14144	1796	13	3	2018-12-10 12:15:00
14145	1796	13	3	2019-12-11 07:45:00
14146	1796	13	3	2018-07-03 12:45:00
14147	1796	13	3	2019-09-20 11:00:00
14148	1797	19	7	2018-11-19 15:30:00
14149	1797	19	7	2019-04-10 02:45:00
14150	1797	19	7	2019-11-22 06:45:00
14151	1797	19	7	2019-08-20 01:00:00
14152	1797	19	7	2018-07-18 22:30:00
14153	1797	19	7	2019-11-02 12:15:00
14154	1797	19	7	2018-04-14 16:15:00
14155	1797	19	7	2018-06-16 18:30:00
14156	1797	19	7	2018-03-19 00:45:00
14157	1797	19	7	2019-01-28 20:30:00
14158	1797	19	7	2018-11-23 09:15:00
14159	1797	19	7	2018-07-30 00:45:00
14160	1797	19	7	2019-07-16 23:45:00
14161	1797	19	7	2019-06-09 13:30:00
14162	1798	2	16	2020-03-11 00:45:00
14163	1798	2	16	2018-09-28 03:15:00
14164	1798	2	16	2020-01-19 19:00:00
14165	1798	2	16	2019-10-08 19:00:00
14166	1798	2	16	2019-06-03 18:15:00
14167	1798	2	16	2018-04-28 09:30:00
14168	1798	2	16	2018-06-06 20:45:00
14169	1798	2	16	2018-07-16 03:15:00
14170	1798	2	16	2019-12-17 20:45:00
14171	1798	2	16	2020-02-11 12:30:00
14172	1798	2	16	2020-02-09 16:30:00
14173	1798	2	16	2019-12-21 16:30:00
14174	1798	2	16	2018-08-15 10:00:00
14175	1799	4	12	2018-08-30 00:00:00
14176	1799	4	12	2020-04-17 00:45:00
14177	1799	4	12	2018-09-05 23:00:00
14178	1799	4	12	2019-12-02 07:15:00
14179	1799	4	12	2019-01-11 01:45:00
14180	1799	4	12	2018-11-22 18:15:00
14181	1799	4	12	2019-07-26 01:15:00
14182	1799	4	12	2019-05-23 22:00:00
14183	1799	4	12	2020-05-22 19:15:00
14184	1799	4	12	2020-06-13 13:30:00
14185	1799	4	12	2020-07-28 07:00:00
14186	1799	4	12	2020-03-23 23:00:00
14187	1799	4	12	2020-07-10 14:45:00
14188	1800	8	19	2018-10-18 03:00:00
14189	1800	8	19	2018-10-18 09:30:00
14190	1800	8	19	2018-08-11 09:15:00
14191	1800	8	19	2018-06-16 19:00:00
14192	1800	8	19	2019-06-30 21:00:00
14193	1800	8	19	2019-05-12 20:45:00
14194	1800	8	19	2019-01-15 02:00:00
14195	1800	8	19	2018-05-21 21:00:00
14196	1800	8	19	2019-05-14 19:15:00
14197	1800	8	19	2019-05-12 02:30:00
14198	1800	8	19	2020-01-01 01:00:00
14199	1800	8	19	2020-01-23 09:45:00
14200	1801	14	9	2017-02-02 22:45:00
14201	1801	14	9	2017-11-02 06:45:00
14202	1801	14	9	2018-05-17 08:15:00
14203	1801	14	9	2018-10-12 20:15:00
14204	1801	14	9	2018-08-18 07:30:00
14205	1801	14	9	2017-03-04 10:45:00
14206	1801	14	9	2018-08-07 01:15:00
14207	1801	14	9	2017-03-10 00:15:00
14208	1801	14	9	2018-02-03 23:15:00
14209	1802	16	15	2020-03-14 12:00:00
14210	1802	16	15	2019-08-13 04:15:00
14211	1802	16	15	2019-01-26 05:00:00
14212	1802	16	15	2019-05-26 18:45:00
14213	1802	16	15	2020-03-21 05:30:00
14214	1802	16	15	2019-12-15 22:30:00
14215	1802	16	15	2019-11-09 01:30:00
14216	1803	7	7	2018-02-06 03:30:00
14217	1804	18	2	2019-05-10 04:45:00
14218	1804	18	2	2018-01-14 22:00:00
14219	1804	18	2	2018-07-25 06:15:00
14220	1804	18	2	2017-07-28 20:30:00
14221	1804	18	2	2017-08-09 21:15:00
14222	1804	18	2	2018-01-12 09:00:00
14223	1804	18	2	2018-01-10 00:30:00
14224	1804	18	2	2018-11-30 03:30:00
14225	1804	18	2	2017-08-02 19:45:00
14226	1805	6	3	2021-04-12 06:30:00
14227	1805	6	3	2021-09-27 23:30:00
14228	1805	6	3	2020-08-13 13:15:00
14229	1805	6	3	2020-11-01 15:15:00
14230	1805	6	3	2020-06-26 05:00:00
14231	1805	6	3	2020-08-24 07:45:00
14232	1805	6	3	2020-02-17 18:45:00
14233	1805	6	3	2021-08-29 22:30:00
14234	1806	20	11	2019-08-12 16:30:00
14235	1806	20	11	2020-03-06 03:15:00
14236	1806	20	11	2019-12-27 22:00:00
14237	1806	20	11	2020-10-22 13:45:00
14238	1806	20	11	2021-01-12 14:45:00
14239	1806	20	11	2020-05-17 13:00:00
14240	1806	20	11	2019-04-22 00:30:00
14241	1806	20	11	2020-04-01 15:45:00
14242	1806	20	11	2020-07-25 13:00:00
14243	1806	20	11	2021-02-04 19:30:00
14244	1806	20	11	2019-12-05 05:15:00
14245	1806	20	11	2020-07-29 22:15:00
14246	1806	20	11	2020-03-22 04:15:00
14247	1806	20	11	2019-08-21 05:30:00
14248	1806	20	11	2019-08-13 20:45:00
14249	1807	3	18	2020-04-22 22:15:00
14250	1807	3	18	2019-05-17 08:45:00
14251	1808	17	17	2019-07-02 22:15:00
14252	1808	17	17	2018-03-27 03:00:00
14253	1809	10	11	2019-08-16 08:30:00
14254	1809	10	11	2019-03-26 15:00:00
14255	1809	10	11	2018-11-03 14:30:00
14256	1809	10	11	2020-09-15 08:45:00
14257	1809	10	11	2020-05-14 13:30:00
14258	1809	10	11	2019-06-12 09:15:00
14259	1809	10	11	2018-11-24 02:00:00
14260	1810	11	15	2018-10-19 21:45:00
14261	1810	11	15	2019-02-10 16:30:00
14262	1810	11	15	2017-11-28 01:15:00
14263	1810	11	15	2018-02-22 01:15:00
14264	1810	11	15	2018-06-30 19:15:00
14265	1810	11	15	2017-06-28 18:45:00
14266	1810	11	15	2018-09-10 05:15:00
14267	1810	11	15	2018-06-08 11:15:00
14268	1810	11	15	2017-08-23 12:30:00
14269	1810	11	15	2017-08-06 09:15:00
14270	1810	11	15	2018-12-16 09:30:00
14271	1811	16	10	2019-06-11 18:45:00
14272	1811	16	10	2020-12-17 13:15:00
14273	1811	16	10	2019-12-25 00:30:00
14274	1811	16	10	2019-09-19 00:15:00
14275	1811	16	10	2019-09-18 10:15:00
14276	1811	16	10	2020-02-02 17:15:00
14277	1811	16	10	2019-05-16 12:00:00
14278	1811	16	10	2020-07-22 10:00:00
14279	1811	16	10	2020-05-16 02:15:00
14280	1811	16	10	2019-10-27 01:45:00
14281	1811	16	10	2020-05-13 12:30:00
14282	1811	16	10	2020-08-10 12:15:00
14283	1812	20	5	2020-11-28 05:45:00
14284	1812	20	5	2021-03-26 18:00:00
14285	1812	20	5	2019-11-01 21:30:00
14286	1812	20	5	2021-08-28 10:15:00
14287	1812	20	5	2021-03-18 01:00:00
14288	1813	14	2	2020-08-03 03:45:00
14289	1813	14	2	2020-05-24 06:30:00
14290	1813	14	2	2021-09-15 23:30:00
14291	1813	14	2	2021-08-28 14:00:00
14292	1813	14	2	2021-06-01 12:45:00
14293	1814	14	19	2019-07-09 14:15:00
14294	1815	12	15	2020-06-24 00:00:00
14295	1815	12	15	2019-04-25 10:00:00
14296	1815	12	15	2020-04-25 16:30:00
14297	1815	12	15	2018-08-06 23:30:00
14298	1816	18	15	2019-01-28 07:15:00
14299	1816	18	15	2019-01-08 10:30:00
14300	1817	12	16	2018-11-12 07:15:00
14301	1817	12	16	2018-08-20 08:30:00
14302	1818	8	2	2020-10-09 03:45:00
14303	1818	8	2	2020-06-27 04:00:00
14304	1818	8	2	2020-08-21 10:30:00
14305	1818	8	2	2020-02-09 13:30:00
14306	1818	8	2	2020-02-23 06:45:00
14307	1818	8	2	2020-08-06 08:45:00
14308	1818	8	2	2019-09-26 15:30:00
14309	1818	8	2	2019-04-14 09:00:00
14310	1818	8	2	2020-07-04 04:30:00
14311	1819	8	1	2021-02-05 02:45:00
14312	1819	8	1	2019-12-14 04:30:00
14313	1819	8	1	2019-05-13 15:45:00
14314	1820	11	2	2018-02-18 19:15:00
14315	1820	11	2	2018-02-05 18:00:00
14316	1820	11	2	2019-03-03 11:15:00
14317	1820	11	2	2018-12-17 16:45:00
14318	1820	11	2	2017-09-29 18:45:00
14319	1820	11	2	2019-02-21 21:45:00
14320	1821	7	10	2018-09-21 06:15:00
14321	1821	7	10	2019-08-23 23:00:00
14322	1821	7	10	2019-04-12 14:00:00
14323	1821	7	10	2019-04-23 05:15:00
14324	1821	7	10	2018-02-25 20:00:00
14325	1821	7	10	2018-11-09 19:00:00
14326	1821	7	10	2019-08-01 06:30:00
14327	1821	7	10	2018-02-22 19:45:00
14328	1821	7	10	2019-06-01 03:15:00
14329	1821	7	10	2019-03-06 09:15:00
14330	1821	7	10	2018-08-11 17:00:00
14331	1822	11	9	2020-02-03 02:45:00
14332	1822	11	9	2020-01-14 09:30:00
14333	1822	11	9	2020-08-14 22:45:00
14334	1822	11	9	2021-09-21 11:45:00
14335	1822	11	9	2021-07-06 14:30:00
14336	1822	11	9	2020-02-03 15:15:00
14337	1822	11	9	2020-12-24 15:30:00
14338	1822	11	9	2021-11-27 23:30:00
14339	1822	11	9	2020-01-15 05:00:00
14340	1823	7	12	2019-03-02 04:30:00
14341	1823	7	12	2018-03-29 02:00:00
14342	1823	7	12	2018-02-22 07:30:00
14343	1823	7	12	2018-09-02 07:15:00
14344	1823	7	12	2019-08-18 06:45:00
14345	1823	7	12	2019-06-24 06:00:00
14346	1823	7	12	2019-04-29 05:45:00
14347	1823	7	12	2018-02-27 18:30:00
14348	1823	7	12	2018-01-23 22:00:00
14349	1823	7	12	2018-09-14 05:00:00
14350	1823	7	12	2018-02-14 10:15:00
14351	1823	7	12	2018-01-02 20:15:00
14352	1823	7	12	2018-03-11 14:30:00
14353	1823	7	12	2018-10-13 18:00:00
14354	1823	7	12	2019-05-27 06:00:00
14355	1824	1	1	2019-06-14 00:00:00
14356	1824	1	1	2018-09-26 17:00:00
14357	1824	1	1	2018-12-23 01:00:00
14358	1824	1	1	2018-09-03 16:30:00
14359	1824	1	1	2019-06-22 04:15:00
14360	1824	1	1	2018-04-25 06:15:00
14361	1824	1	1	2018-10-08 00:30:00
14362	1824	1	1	2018-06-21 09:45:00
14363	1824	1	1	2018-05-01 09:15:00
14364	1824	1	1	2018-10-16 17:45:00
14365	1824	1	1	2019-06-15 01:45:00
14366	1824	1	1	2018-02-22 18:30:00
14367	1825	16	2	2020-03-13 04:30:00
14368	1825	16	2	2019-09-29 11:15:00
14369	1825	16	2	2019-05-01 13:15:00
14370	1825	16	2	2019-07-26 10:45:00
14371	1826	17	19	2018-09-06 15:15:00
14372	1826	17	19	2019-07-04 13:00:00
14373	1826	17	19	2019-10-15 11:15:00
14374	1826	17	19	2020-03-07 18:30:00
14375	1826	17	19	2018-11-02 05:15:00
14376	1826	17	19	2018-11-26 11:00:00
14377	1826	17	19	2018-12-07 21:00:00
14378	1826	17	19	2018-09-13 23:15:00
14379	1826	17	19	2018-07-18 00:30:00
14380	1826	17	19	2019-06-23 14:00:00
14381	1826	17	19	2019-09-21 04:30:00
14382	1826	17	19	2019-06-27 14:15:00
14383	1827	14	18	2021-03-29 06:30:00
14384	1827	14	18	2020-09-25 17:30:00
14385	1827	14	18	2019-10-27 02:45:00
14386	1827	14	18	2020-11-16 21:30:00
14387	1827	14	18	2019-07-24 04:30:00
14388	1827	14	18	2020-11-02 12:15:00
14389	1827	14	18	2019-07-05 06:15:00
14390	1827	14	18	2020-11-09 05:30:00
14391	1827	14	18	2020-09-19 13:45:00
14392	1827	14	18	2021-04-17 01:15:00
14393	1827	14	18	2021-04-19 11:00:00
14394	1827	14	18	2020-05-26 17:00:00
14395	1828	2	2	2019-06-08 01:45:00
14396	1828	2	2	2018-01-28 04:30:00
14397	1828	2	2	2018-11-14 21:30:00
14398	1828	2	2	2019-03-19 12:45:00
14399	1828	2	2	2018-04-14 22:45:00
14400	1828	2	2	2018-08-20 15:30:00
14401	1828	2	2	2019-02-03 05:00:00
14402	1828	2	2	2018-06-16 20:15:00
14403	1828	2	2	2018-12-26 21:15:00
14404	1828	2	2	2018-12-12 05:00:00
14405	1828	2	2	2018-03-09 07:45:00
14406	1828	2	2	2019-06-03 02:45:00
14407	1829	9	4	2018-09-18 08:00:00
14408	1829	9	4	2019-05-15 11:00:00
14409	1830	8	11	2021-01-30 14:00:00
14410	1830	8	11	2020-08-10 06:15:00
14411	1830	8	11	2019-07-14 04:45:00
14412	1830	8	11	2021-02-03 13:45:00
14413	1830	8	11	2019-10-11 19:45:00
14414	1830	8	11	2019-08-04 23:30:00
14415	1830	8	11	2021-02-02 17:15:00
14416	1830	8	11	2020-05-20 16:30:00
14417	1830	8	11	2021-01-11 15:30:00
14418	1831	6	17	2020-10-14 16:15:00
14419	1831	6	17	2021-04-16 21:15:00
14420	1831	6	17	2021-09-28 10:30:00
14421	1831	6	17	2020-05-02 00:15:00
14422	1831	6	17	2020-06-14 22:45:00
14423	1831	6	17	2020-08-21 06:45:00
14424	1831	6	17	2021-04-08 12:00:00
14425	1831	6	17	2020-09-20 22:00:00
14426	1831	6	17	2021-03-17 07:30:00
14427	1831	6	17	2021-07-12 17:45:00
14428	1832	2	3	2021-01-23 23:00:00
14429	1832	2	3	2019-12-13 22:45:00
14430	1832	2	3	2020-11-04 19:15:00
14431	1832	2	3	2019-09-28 08:00:00
14432	1832	2	3	2021-04-05 08:15:00
14433	1833	5	14	2019-03-26 15:15:00
14434	1833	5	14	2017-12-17 20:45:00
14435	1834	14	20	2019-12-01 13:45:00
14436	1834	14	20	2018-12-24 11:00:00
14437	1835	3	10	2018-08-07 18:15:00
14438	1835	3	10	2019-03-25 09:30:00
14439	1835	3	10	2018-05-27 10:45:00
14440	1835	3	10	2018-07-15 03:45:00
14441	1835	3	10	2019-07-17 18:00:00
14442	1835	3	10	2018-09-24 15:00:00
14443	1835	3	10	2018-05-06 08:45:00
14444	1835	3	10	2018-03-13 08:15:00
14445	1835	3	10	2018-07-02 20:30:00
14446	1835	3	10	2019-11-19 06:30:00
14447	1835	3	10	2019-02-08 20:45:00
14448	1835	3	10	2019-02-01 16:30:00
14449	1835	3	10	2019-11-19 18:00:00
14450	1836	14	8	2018-03-26 05:15:00
14451	1836	14	8	2019-02-06 22:15:00
14452	1836	14	8	2019-04-19 12:45:00
14453	1836	14	8	2018-09-25 06:30:00
14454	1837	19	1	2018-11-26 17:30:00
14455	1837	19	1	2019-03-05 17:30:00
14456	1837	19	1	2019-02-10 17:15:00
14457	1838	19	1	2018-12-11 15:00:00
14458	1838	19	1	2018-07-15 18:45:00
14459	1838	19	1	2019-01-16 11:15:00
14460	1838	19	1	2019-03-27 20:15:00
14461	1838	19	1	2018-06-05 23:30:00
14462	1838	19	1	2018-12-21 00:00:00
14463	1839	18	16	2020-06-25 05:00:00
14464	1839	18	16	2019-10-10 00:45:00
14465	1839	18	16	2021-05-21 05:15:00
14466	1839	18	16	2020-07-20 01:00:00
14467	1839	18	16	2019-08-13 18:15:00
14468	1839	18	16	2019-10-13 23:15:00
14469	1839	18	16	2020-01-12 14:45:00
14470	1839	18	16	2020-09-30 08:00:00
14471	1839	18	16	2019-10-14 07:30:00
14472	1840	3	7	2017-07-09 12:00:00
14473	1840	3	7	2018-06-06 03:30:00
14474	1840	3	7	2018-05-25 09:30:00
14475	1840	3	7	2017-08-28 08:30:00
14476	1840	3	7	2018-11-17 07:00:00
14477	1840	3	7	2018-06-29 22:30:00
14478	1840	3	7	2018-06-30 07:00:00
14479	1840	3	7	2017-10-09 12:00:00
14480	1840	3	7	2019-02-26 19:45:00
14481	1840	3	7	2018-12-13 17:15:00
14482	1841	15	10	2019-06-16 08:30:00
14483	1841	15	10	2018-09-10 01:45:00
14484	1841	15	10	2019-06-16 15:45:00
14485	1841	15	10	2019-09-02 02:30:00
14486	1841	15	10	2019-02-13 04:00:00
14487	1841	15	10	2019-03-05 01:30:00
14488	1841	15	10	2019-09-22 15:45:00
14489	1841	15	10	2019-01-08 23:45:00
14490	1841	15	10	2018-12-29 04:45:00
14491	1841	15	10	2018-05-07 20:00:00
14492	1841	15	10	2018-09-30 02:15:00
14493	1841	15	10	2019-02-15 16:15:00
14494	1841	15	10	2020-01-25 17:00:00
14495	1841	15	10	2019-10-17 02:30:00
14496	1841	15	10	2020-02-10 00:30:00
14497	1842	1	18	2020-12-14 17:45:00
14498	1842	1	18	2020-11-26 23:45:00
14499	1842	1	18	2020-02-02 18:30:00
14500	1842	1	18	2020-03-08 18:30:00
14501	1842	1	18	2021-06-19 09:45:00
14502	1842	1	18	2021-10-27 09:45:00
14503	1842	1	18	2021-01-13 01:30:00
14504	1842	1	18	2020-04-29 07:00:00
14505	1842	1	18	2020-03-07 04:45:00
14506	1842	1	18	2020-09-06 07:15:00
14507	1842	1	18	2020-08-22 09:30:00
14508	1842	1	18	2021-07-14 02:30:00
14509	1842	1	18	2020-12-13 09:00:00
14510	1843	2	19	2018-11-15 18:15:00
14511	1843	2	19	2018-09-20 03:00:00
14512	1843	2	19	2018-05-03 11:45:00
14513	1843	2	19	2018-02-02 02:00:00
14514	1844	17	13	2019-04-17 00:30:00
14515	1844	17	13	2020-07-11 07:30:00
14516	1844	17	13	2020-09-14 10:45:00
14517	1844	17	13	2020-08-13 21:00:00
14518	1844	17	13	2020-12-05 17:45:00
14519	1844	17	13	2020-12-01 18:15:00
14520	1844	17	13	2019-05-14 20:30:00
14521	1844	17	13	2020-10-08 17:00:00
14522	1844	17	13	2019-08-15 15:15:00
14523	1844	17	13	2020-10-28 18:15:00
14524	1844	17	13	2019-11-23 13:45:00
14525	1844	17	13	2020-05-23 18:45:00
14526	1845	6	20	2020-02-09 00:00:00
14527	1845	6	20	2020-06-01 19:15:00
14528	1845	6	20	2020-04-11 18:00:00
14529	1845	6	20	2019-12-14 02:30:00
14530	1845	6	20	2020-01-05 01:15:00
14531	1845	6	20	2019-07-24 18:45:00
14532	1845	6	20	2020-11-05 03:30:00
14533	1845	6	20	2019-04-08 06:15:00
14534	1845	6	20	2020-07-06 09:00:00
14535	1845	6	20	2021-03-03 19:00:00
14536	1845	6	20	2020-04-09 18:30:00
14537	1845	6	20	2020-08-22 09:30:00
14538	1846	5	7	2017-11-07 15:30:00
14539	1846	5	7	2018-05-01 04:00:00
14540	1846	5	7	2017-10-07 15:15:00
14541	1846	5	7	2018-07-21 12:45:00
14542	1846	5	7	2018-05-17 13:45:00
14543	1846	5	7	2017-12-02 16:45:00
14544	1847	3	12	2020-02-04 17:00:00
14545	1847	3	12	2019-03-09 05:15:00
14546	1847	3	12	2018-12-13 21:45:00
14547	1847	3	12	2018-09-23 07:30:00
14548	1847	3	12	2019-09-14 22:30:00
14549	1847	3	12	2018-05-19 20:00:00
14550	1847	3	12	2020-03-17 01:30:00
14551	1847	3	12	2019-07-05 09:30:00
14552	1847	3	12	2018-07-27 21:00:00
14553	1847	3	12	2019-04-20 08:15:00
14554	1847	3	12	2019-09-10 14:15:00
14555	1848	9	14	2019-03-19 16:00:00
14556	1848	9	14	2017-07-15 02:00:00
14557	1848	9	14	2019-02-02 07:15:00
14558	1848	9	14	2017-12-18 17:15:00
14559	1848	9	14	2017-07-28 20:30:00
14560	1848	9	14	2018-06-30 12:45:00
14561	1848	9	14	2018-04-25 15:15:00
14562	1848	9	14	2018-05-16 17:15:00
14563	1848	9	14	2018-09-23 05:45:00
14564	1848	9	14	2017-08-20 12:45:00
14565	1848	9	14	2017-06-18 00:15:00
14566	1848	9	14	2018-03-03 19:30:00
14567	1848	9	14	2017-12-01 06:00:00
14568	1848	9	14	2018-04-08 17:45:00
14569	1849	8	14	2019-02-25 19:00:00
14570	1849	8	14	2018-10-11 20:45:00
14571	1849	8	14	2018-01-27 09:00:00
14572	1849	8	14	2018-05-14 00:45:00
14573	1849	8	14	2019-05-18 06:30:00
14574	1849	8	14	2018-06-29 16:00:00
14575	1849	8	14	2018-01-06 04:15:00
14576	1849	8	14	2019-06-02 07:45:00
14577	1849	8	14	2019-05-15 19:00:00
14578	1850	4	15	2018-06-23 18:45:00
14579	1850	4	15	2018-11-09 21:30:00
14580	1850	4	15	2017-07-07 13:00:00
14581	1850	4	15	2018-06-09 04:00:00
14582	1850	4	15	2017-10-11 12:45:00
14583	1850	4	15	2018-11-07 14:15:00
14584	1851	13	20	2019-04-06 13:30:00
14585	1851	13	20	2019-07-05 20:00:00
14586	1851	13	20	2018-07-26 20:15:00
14587	1851	13	20	2018-04-14 06:30:00
14588	1851	13	20	2017-11-08 00:45:00
14589	1851	13	20	2018-10-21 13:15:00
14590	1851	13	20	2019-06-09 04:30:00
14591	1851	13	20	2018-08-04 23:00:00
14592	1851	13	20	2019-09-16 03:00:00
14593	1851	13	20	2018-07-25 12:45:00
14594	1851	13	20	2019-03-26 15:30:00
14595	1851	13	20	2018-01-24 10:15:00
14596	1852	8	3	2018-10-02 20:30:00
14597	1852	8	3	2020-02-16 07:00:00
14598	1852	8	3	2020-01-23 04:00:00
14599	1852	8	3	2019-06-09 06:00:00
14600	1852	8	3	2020-07-19 13:00:00
14601	1852	8	3	2019-01-24 13:45:00
14602	1852	8	3	2020-03-04 23:00:00
14603	1852	8	3	2020-02-24 10:15:00
14604	1852	8	3	2019-01-18 14:30:00
14605	1852	8	3	2019-02-02 01:00:00
14606	1852	8	3	2019-11-02 15:15:00
14607	1853	5	14	2019-01-21 16:15:00
14608	1853	5	14	2019-01-15 22:30:00
14609	1853	5	14	2019-12-13 09:45:00
14610	1854	6	19	2019-10-30 07:30:00
14611	1854	6	19	2019-11-05 04:00:00
14612	1854	6	19	2020-01-28 04:00:00
14613	1854	6	19	2021-05-07 09:15:00
14614	1854	6	19	2021-09-22 13:15:00
14615	1854	6	19	2020-03-07 11:00:00
14616	1854	6	19	2020-08-17 05:00:00
14617	1854	6	19	2021-09-03 17:30:00
14618	1854	6	19	2020-10-06 00:15:00
14619	1854	6	19	2020-12-28 21:15:00
14620	1854	6	19	2021-05-01 08:45:00
14621	1854	6	19	2021-08-06 18:45:00
14622	1855	20	15	2019-04-05 02:15:00
14623	1855	20	15	2020-07-11 04:00:00
14624	1855	20	15	2019-06-05 05:00:00
14625	1855	20	15	2019-06-12 09:45:00
14626	1855	20	15	2019-05-30 23:45:00
14627	1855	20	15	2020-03-11 13:15:00
14628	1855	20	15	2019-05-01 14:00:00
14629	1855	20	15	2019-01-02 03:15:00
14630	1855	20	15	2020-03-17 03:30:00
14631	1855	20	15	2020-01-28 01:15:00
14632	1856	20	7	2018-08-05 13:15:00
14633	1856	20	7	2017-08-20 06:30:00
14634	1856	20	7	2019-01-05 04:00:00
14635	1856	20	7	2017-06-12 10:45:00
14636	1856	20	7	2017-08-04 05:30:00
14637	1856	20	7	2017-06-23 04:45:00
14638	1856	20	7	2017-09-18 23:45:00
14639	1857	8	10	2018-07-20 05:00:00
14640	1857	8	10	2019-05-22 18:30:00
14641	1857	8	10	2018-03-06 10:00:00
14642	1857	8	10	2018-02-12 05:45:00
14643	1857	8	10	2018-07-16 01:15:00
14644	1857	8	10	2018-07-20 01:00:00
14645	1857	8	10	2018-08-11 06:45:00
14646	1857	8	10	2018-10-05 01:30:00
14647	1857	8	10	2018-05-20 06:30:00
14648	1857	8	10	2018-01-25 10:30:00
14649	1857	8	10	2018-06-27 19:45:00
14650	1857	8	10	2019-06-17 23:30:00
14651	1858	12	9	2021-04-07 04:00:00
14652	1858	12	9	2020-06-26 09:15:00
14653	1859	5	20	2019-06-15 22:15:00
14654	1859	5	20	2020-05-12 18:30:00
14655	1859	5	20	2021-03-20 07:15:00
14656	1859	5	20	2020-07-22 06:15:00
14657	1859	5	20	2020-07-29 11:00:00
14658	1859	5	20	2019-06-22 17:45:00
14659	1859	5	20	2019-07-27 00:00:00
14660	1859	5	20	2019-09-19 16:15:00
14661	1860	20	17	2018-03-14 01:15:00
14662	1860	20	17	2018-08-13 06:45:00
14663	1860	20	17	2019-08-29 18:15:00
14664	1860	20	17	2018-01-17 18:00:00
14665	1860	20	17	2018-04-01 03:15:00
14666	1860	20	17	2017-12-15 16:45:00
14667	1861	20	19	2018-04-29 17:30:00
14668	1861	20	19	2018-07-15 16:15:00
14669	1861	20	19	2017-08-14 07:30:00
14670	1861	20	19	2018-06-01 18:15:00
14671	1861	20	19	2019-01-17 22:00:00
14672	1861	20	19	2018-06-06 04:00:00
14673	1861	20	19	2018-02-24 07:15:00
14674	1861	20	19	2019-02-01 09:45:00
14675	1861	20	19	2018-04-19 13:45:00
14676	1861	20	19	2018-03-20 18:30:00
14677	1861	20	19	2019-03-17 19:15:00
14678	1862	8	8	2017-03-09 02:45:00
14679	1862	8	8	2018-02-04 12:45:00
14680	1862	8	8	2018-02-07 03:30:00
14681	1862	8	8	2018-11-24 19:00:00
14682	1863	12	7	2018-06-01 13:00:00
14683	1863	12	7	2019-01-09 07:00:00
14684	1863	12	7	2018-02-08 14:15:00
14685	1863	12	7	2019-05-27 11:30:00
14686	1863	12	7	2018-05-17 01:45:00
14687	1863	12	7	2019-04-12 05:00:00
14688	1863	12	7	2018-12-25 21:00:00
14689	1863	12	7	2019-10-05 06:45:00
14690	1864	9	6	2021-06-16 22:00:00
14691	1864	9	6	2019-08-29 19:00:00
14692	1865	16	19	2019-10-15 01:15:00
14693	1865	16	19	2020-09-05 22:30:00
14694	1865	16	19	2020-09-06 17:15:00
14695	1865	16	19	2020-10-07 15:15:00
14696	1865	16	19	2021-03-06 22:30:00
14697	1865	16	19	2020-12-08 17:00:00
14698	1865	16	19	2019-12-18 18:45:00
14699	1865	16	19	2021-02-14 17:15:00
14700	1865	16	19	2020-10-11 17:45:00
14701	1865	16	19	2020-01-13 01:15:00
14702	1866	1	19	2018-11-25 08:45:00
14703	1866	1	19	2020-07-24 16:45:00
14704	1866	1	19	2020-01-26 12:15:00
14705	1866	1	19	2019-08-10 02:15:00
14706	1866	1	19	2018-11-18 00:30:00
14707	1866	1	19	2019-11-03 02:30:00
14708	1866	1	19	2019-12-29 21:15:00
14709	1866	1	19	2020-07-11 21:00:00
14710	1866	1	19	2019-04-30 03:45:00
14711	1867	1	12	2021-01-12 12:00:00
14712	1867	1	12	2020-12-23 19:45:00
14713	1867	1	12	2020-02-05 18:30:00
14714	1867	1	12	2019-11-02 18:45:00
14715	1867	1	12	2020-03-22 04:30:00
14716	1867	1	12	2020-10-23 05:30:00
14717	1867	1	12	2020-02-19 10:00:00
14718	1868	13	19	2017-11-23 19:45:00
14719	1868	13	19	2017-07-10 12:15:00
14720	1868	13	19	2017-10-28 00:45:00
14721	1868	13	19	2018-09-12 21:15:00
14722	1868	13	19	2018-09-16 06:45:00
14723	1868	13	19	2017-12-22 02:30:00
14724	1868	13	19	2017-07-16 15:30:00
14725	1868	13	19	2018-06-22 20:00:00
14726	1868	13	19	2017-12-24 02:30:00
14727	1868	13	19	2017-10-26 05:15:00
14728	1868	13	19	2017-03-23 18:30:00
14729	1868	13	19	2018-09-19 16:30:00
14730	1868	13	19	2017-04-06 07:45:00
14731	1869	6	19	2019-02-25 09:00:00
14732	1870	17	12	2017-07-08 07:30:00
14733	1870	17	12	2019-03-22 01:00:00
14734	1870	17	12	2018-04-12 00:15:00
14735	1870	17	12	2019-02-12 05:30:00
14736	1871	12	5	2018-04-27 05:45:00
14737	1871	12	5	2017-11-13 09:30:00
14738	1871	12	5	2019-03-03 11:15:00
14739	1871	12	5	2018-05-07 09:00:00
14740	1871	12	5	2018-08-03 19:45:00
14741	1871	12	5	2018-02-05 13:00:00
14742	1871	12	5	2018-12-22 23:15:00
14743	1871	12	5	2019-04-05 17:15:00
14744	1871	12	5	2017-11-01 09:15:00
14745	1871	12	5	2018-07-16 23:00:00
14746	1872	17	16	2021-05-25 23:45:00
14747	1872	17	16	2021-06-26 11:30:00
14748	1872	17	16	2021-06-07 12:45:00
14749	1872	17	16	2019-08-03 08:45:00
14750	1872	17	16	2020-01-26 14:15:00
14751	1872	17	16	2019-12-10 16:30:00
14752	1872	17	16	2020-10-14 16:45:00
14753	1872	17	16	2021-06-24 03:30:00
14754	1873	16	7	2020-05-07 13:00:00
14755	1873	16	7	2019-05-09 10:30:00
14756	1873	16	7	2020-04-16 18:45:00
14757	1873	16	7	2020-10-13 01:45:00
14758	1874	10	12	2019-02-13 13:30:00
14759	1874	10	12	2019-07-01 05:45:00
14760	1874	10	12	2018-04-27 10:00:00
14761	1874	10	12	2018-11-06 07:30:00
14762	1874	10	12	2018-11-02 08:15:00
14763	1874	10	12	2018-08-06 03:45:00
14764	1874	10	12	2017-11-01 17:45:00
14765	1874	10	12	2017-08-17 06:00:00
14766	1874	10	12	2019-06-02 19:00:00
14767	1874	10	12	2018-11-08 07:15:00
14768	1874	10	12	2018-03-08 04:15:00
14769	1874	10	12	2019-04-10 04:00:00
14770	1874	10	12	2018-03-23 19:30:00
14771	1874	10	12	2018-07-23 02:00:00
14772	1874	10	12	2018-08-17 17:30:00
14773	1875	3	12	2018-06-29 10:45:00
14774	1875	3	12	2018-05-03 15:45:00
14775	1875	3	12	2019-06-25 01:30:00
14776	1875	3	12	2019-02-04 20:00:00
14777	1875	3	12	2018-09-01 09:45:00
14778	1875	3	12	2019-06-20 06:45:00
14779	1875	3	12	2018-02-23 22:30:00
14780	1875	3	12	2018-09-09 11:30:00
14781	1875	3	12	2019-01-11 06:00:00
14782	1875	3	12	2019-11-06 00:30:00
14783	1875	3	12	2018-03-04 18:45:00
14784	1875	3	12	2019-06-09 21:30:00
14785	1875	3	12	2018-05-26 18:45:00
14786	1875	3	12	2019-11-11 09:30:00
14787	1876	19	4	2020-01-26 07:30:00
14788	1876	19	4	2019-08-27 11:15:00
14789	1876	19	4	2018-09-05 06:00:00
14790	1876	19	4	2020-05-19 23:00:00
14791	1876	19	4	2020-03-08 21:00:00
14792	1876	19	4	2019-06-13 05:45:00
14793	1876	19	4	2019-02-19 01:15:00
14794	1876	19	4	2019-03-06 17:30:00
14795	1876	19	4	2019-09-07 09:45:00
14796	1876	19	4	2019-11-22 21:30:00
14797	1876	19	4	2018-12-26 17:30:00
14798	1876	19	4	2019-01-19 05:45:00
14799	1877	4	1	2020-01-05 08:30:00
14800	1877	4	1	2020-12-02 01:15:00
14801	1877	4	1	2019-03-29 03:30:00
14802	1877	4	1	2020-02-03 20:15:00
14803	1877	4	1	2020-10-11 13:00:00
14804	1877	4	1	2020-11-16 15:15:00
14805	1877	4	1	2020-03-11 00:45:00
14806	1877	4	1	2020-01-12 17:45:00
14807	1878	6	18	2018-04-08 19:15:00
14808	1878	6	18	2019-08-05 02:45:00
14809	1878	6	18	2019-09-22 10:30:00
14810	1878	6	18	2019-12-02 11:15:00
14811	1878	6	18	2019-10-15 04:45:00
14812	1878	6	18	2018-07-21 18:30:00
14813	1878	6	18	2019-11-26 07:15:00
14814	1878	6	18	2019-10-02 22:00:00
14815	1878	6	18	2019-04-09 00:00:00
14816	1878	6	18	2018-06-01 04:45:00
14817	1878	6	18	2018-03-01 01:30:00
14818	1878	6	18	2018-05-29 11:45:00
14819	1879	13	15	2018-11-06 03:00:00
14820	1879	13	15	2018-07-30 19:00:00
14821	1879	13	15	2019-09-14 03:15:00
14822	1879	13	15	2018-04-24 22:30:00
14823	1879	13	15	2019-01-10 08:00:00
14824	1879	13	15	2018-02-15 16:30:00
14825	1879	13	15	2019-12-24 01:15:00
14826	1879	13	15	2019-12-15 00:30:00
14827	1879	13	15	2019-05-01 03:00:00
14828	1879	13	15	2019-10-28 00:15:00
14829	1879	13	15	2019-01-09 18:00:00
14830	1880	19	5	2019-10-08 01:30:00
14831	1880	19	5	2019-12-21 01:00:00
14832	1880	19	5	2019-08-10 18:45:00
14833	1880	19	5	2019-02-14 05:00:00
14834	1880	19	5	2019-01-14 07:30:00
14835	1880	19	5	2019-02-12 13:45:00
14836	1880	19	5	2018-05-12 03:30:00
14837	1880	19	5	2018-07-25 08:45:00
14838	1881	20	12	2020-05-08 20:30:00
14839	1881	20	12	2020-11-18 02:15:00
14840	1881	20	12	2021-01-12 12:15:00
14841	1881	20	12	2019-10-05 18:15:00
14842	1881	20	12	2019-07-09 19:45:00
14843	1881	20	12	2020-10-19 18:15:00
14844	1882	10	4	2018-11-02 02:30:00
14845	1882	10	4	2017-09-02 21:15:00
14846	1882	10	4	2019-04-24 03:00:00
14847	1882	10	4	2017-06-18 17:00:00
14848	1882	10	4	2018-07-14 15:30:00
14849	1882	10	4	2018-11-02 00:00:00
14850	1882	10	4	2018-01-17 18:00:00
14851	1883	11	2	2020-10-19 13:15:00
14852	1883	11	2	2019-08-30 20:00:00
14853	1883	11	2	2019-03-21 21:45:00
14854	1883	11	2	2019-04-03 15:00:00
14855	1883	11	2	2020-08-24 09:45:00
14856	1883	11	2	2020-07-26 00:15:00
14857	1883	11	2	2019-04-08 07:30:00
14858	1883	11	2	2020-05-30 19:00:00
14859	1883	11	2	2019-05-17 14:15:00
14860	1883	11	2	2019-02-18 18:30:00
14861	1883	11	2	2020-11-28 16:15:00
14862	1883	11	2	2020-07-16 16:45:00
14863	1883	11	2	2019-07-21 23:00:00
14864	1883	11	2	2018-12-25 12:30:00
14865	1883	11	2	2020-06-21 15:30:00
14866	1884	16	11	2019-06-13 23:45:00
14867	1884	16	11	2020-05-29 23:30:00
14868	1885	13	11	2018-01-05 09:30:00
14869	1886	9	17	2018-04-06 00:15:00
14870	1886	9	17	2018-04-19 13:30:00
14871	1886	9	17	2018-05-03 20:30:00
14872	1886	9	17	2019-10-10 18:45:00
14873	1886	9	17	2018-07-01 00:15:00
14874	1886	9	17	2018-12-08 08:45:00
14875	1886	9	17	2019-11-25 07:00:00
14876	1886	9	17	2019-02-14 00:30:00
14877	1886	9	17	2019-08-17 20:15:00
14878	1886	9	17	2019-02-06 20:15:00
14879	1886	9	17	2018-10-11 09:15:00
14880	1886	9	17	2019-11-27 11:45:00
14881	1886	9	17	2018-11-02 09:15:00
14882	1887	12	15	2020-06-20 21:45:00
14883	1887	12	15	2020-10-18 17:45:00
14884	1887	12	15	2020-02-02 06:45:00
14885	1887	12	15	2019-07-10 23:00:00
14886	1887	12	15	2021-03-19 21:30:00
14887	1887	12	15	2019-09-05 09:45:00
14888	1887	12	15	2019-05-13 20:00:00
14889	1887	12	15	2020-06-22 21:00:00
14890	1887	12	15	2019-05-05 16:15:00
14891	1887	12	15	2020-10-22 10:45:00
14892	1887	12	15	2021-02-18 05:00:00
14893	1888	20	9	2020-09-03 08:15:00
14894	1888	20	9	2020-05-03 08:45:00
14895	1888	20	9	2020-04-24 03:00:00
14896	1888	20	9	2021-05-04 04:45:00
14897	1888	20	9	2020-09-25 05:00:00
14898	1888	20	9	2020-08-11 15:45:00
14899	1888	20	9	2021-04-27 19:00:00
14900	1888	20	9	2021-06-15 17:45:00
14901	1888	20	9	2021-07-03 14:30:00
14902	1889	14	14	2020-03-22 21:45:00
14903	1889	14	14	2019-12-28 05:30:00
14904	1889	14	14	2019-09-26 09:15:00
14905	1889	14	14	2019-04-13 20:00:00
14906	1889	14	14	2020-03-22 07:15:00
14907	1889	14	14	2020-04-01 02:45:00
14908	1889	14	14	2020-01-01 13:15:00
14909	1889	14	14	2020-03-20 19:45:00
14910	1889	14	14	2019-05-30 05:00:00
14911	1889	14	14	2020-01-11 04:30:00
14912	1889	14	14	2019-07-20 18:45:00
14913	1889	14	14	2020-07-20 09:30:00
14914	1890	17	4	2018-06-27 22:45:00
14915	1890	17	4	2018-08-03 22:45:00
14916	1891	10	16	2018-02-06 15:45:00
14917	1891	10	16	2017-06-04 11:15:00
14918	1891	10	16	2017-12-02 18:00:00
14919	1891	10	16	2018-03-24 10:45:00
14920	1891	10	16	2019-03-24 16:30:00
14921	1891	10	16	2017-07-02 04:45:00
14922	1892	19	6	2020-11-11 12:30:00
14923	1892	19	6	2020-03-19 18:30:00
14924	1892	19	6	2020-11-29 07:45:00
14925	1892	19	6	2019-11-03 01:45:00
14926	1892	19	6	2020-03-02 00:45:00
14927	1892	19	6	2019-06-28 12:45:00
14928	1893	9	11	2019-10-10 18:45:00
14929	1893	9	11	2019-01-03 22:00:00
14930	1893	9	11	2019-09-03 12:30:00
14931	1893	9	11	2019-11-19 15:45:00
14932	1893	9	11	2020-07-15 05:30:00
14933	1893	9	11	2020-09-25 18:15:00
14934	1894	10	2	2020-03-07 19:45:00
14935	1894	10	2	2019-01-14 09:00:00
14936	1894	10	2	2019-09-30 00:30:00
14937	1894	10	2	2019-05-07 00:15:00
14938	1894	10	2	2019-12-22 03:45:00
14939	1894	10	2	2019-06-06 16:15:00
14940	1894	10	2	2018-11-04 07:30:00
14941	1894	10	2	2020-08-11 22:45:00
14942	1894	10	2	2019-06-14 16:45:00
14943	1894	10	2	2020-01-01 10:45:00
14944	1895	13	8	2017-09-24 05:30:00
14945	1895	13	8	2018-02-03 22:30:00
14946	1895	13	8	2018-10-22 19:45:00
14947	1895	13	8	2018-08-09 09:30:00
14948	1895	13	8	2019-05-05 07:30:00
14949	1895	13	8	2017-08-25 14:15:00
14950	1895	13	8	2018-05-08 18:15:00
14951	1895	13	8	2017-07-03 02:15:00
14952	1895	13	8	2018-05-21 04:15:00
14953	1895	13	8	2018-01-11 18:00:00
14954	1895	13	8	2017-11-26 04:45:00
14955	1895	13	8	2018-01-19 05:30:00
14956	1895	13	8	2018-07-26 06:15:00
14957	1895	13	8	2017-07-26 03:00:00
14958	1896	4	20	2019-01-19 00:30:00
14959	1896	4	20	2019-10-10 08:30:00
14960	1896	4	20	2018-10-02 17:45:00
14961	1896	4	20	2018-12-24 22:15:00
14962	1896	4	20	2019-01-13 05:45:00
14963	1896	4	20	2018-10-11 10:45:00
14964	1896	4	20	2019-11-07 17:00:00
14965	1896	4	20	2020-01-16 20:30:00
14966	1896	4	20	2019-03-01 15:30:00
14967	1897	7	17	2018-04-17 19:00:00
14968	1897	7	17	2017-12-10 01:00:00
14969	1897	7	17	2018-05-02 01:00:00
14970	1897	7	17	2019-04-13 03:30:00
14971	1897	7	17	2019-03-13 07:30:00
14972	1898	18	5	2020-03-11 21:30:00
14973	1898	18	5	2021-04-17 22:00:00
14974	1898	18	5	2020-02-02 02:45:00
14975	1898	18	5	2019-09-03 10:00:00
14976	1898	18	5	2019-05-09 23:00:00
14977	1898	18	5	2019-10-14 04:15:00
14978	1899	4	20	2019-05-30 00:00:00
14979	1899	4	20	2017-12-24 07:00:00
14980	1899	4	20	2019-09-13 17:30:00
14981	1899	4	20	2019-02-02 06:45:00
14982	1900	10	3	2019-11-15 06:00:00
14983	1900	10	3	2018-10-29 10:15:00
14984	1900	10	3	2019-11-09 07:45:00
14985	1900	10	3	2020-02-11 06:15:00
14986	1900	10	3	2018-08-29 17:00:00
14987	1900	10	3	2019-10-20 22:45:00
14988	1900	10	3	2020-01-29 13:00:00
14989	1900	10	3	2018-07-22 16:45:00
14990	1900	10	3	2019-09-14 22:00:00
14991	1901	12	19	2021-07-26 02:30:00
14992	1901	12	19	2021-03-08 20:00:00
14993	1901	12	19	2020-01-11 09:15:00
14994	1901	12	19	2020-02-05 12:45:00
14995	1901	12	19	2021-06-06 22:15:00
14996	1901	12	19	2021-04-28 09:45:00
14997	1902	2	9	2020-01-15 15:30:00
14998	1902	2	9	2020-01-01 17:00:00
14999	1902	2	9	2020-06-05 09:45:00
15000	1902	2	9	2019-05-27 05:45:00
15001	1902	2	9	2019-07-18 22:30:00
15002	1902	2	9	2019-05-13 08:15:00
15003	1902	2	9	2019-04-24 05:00:00
15004	1902	2	9	2020-04-22 04:15:00
15005	1902	2	9	2019-05-02 10:45:00
15006	1902	2	9	2020-10-10 08:00:00
15007	1902	2	9	2019-10-24 09:45:00
15008	1903	15	10	2019-04-19 05:00:00
15009	1903	15	10	2019-03-07 11:45:00
15010	1903	15	10	2018-06-22 21:45:00
15011	1903	15	10	2019-11-06 19:45:00
15012	1903	15	10	2018-08-28 12:30:00
15013	1903	15	10	2019-11-16 21:00:00
15014	1903	15	10	2018-11-01 22:45:00
15015	1903	15	10	2018-10-09 04:00:00
15016	1903	15	10	2018-09-16 21:00:00
15017	1903	15	10	2017-12-18 02:30:00
15018	1903	15	10	2019-06-15 23:30:00
15019	1903	15	10	2019-11-29 19:45:00
15020	1904	5	2	2019-07-27 07:30:00
15021	1904	5	2	2018-12-06 09:00:00
15022	1904	5	2	2019-08-17 13:15:00
15023	1904	5	2	2018-01-24 05:00:00
15024	1904	5	2	2018-08-14 04:15:00
15025	1904	5	2	2019-05-21 09:00:00
15026	1904	5	2	2019-02-20 06:45:00
15027	1904	5	2	2018-08-08 20:30:00
15028	1904	5	2	2018-12-04 10:45:00
15029	1904	5	2	2018-01-16 09:15:00
15030	1904	5	2	2017-12-23 15:15:00
15031	1904	5	2	2019-06-02 13:15:00
15032	1904	5	2	2019-01-16 11:30:00
15033	1904	5	2	2018-08-17 04:45:00
15034	1904	5	2	2019-09-14 04:15:00
15035	1905	19	3	2019-12-05 10:00:00
15036	1905	19	3	2019-08-19 15:45:00
15037	1905	19	3	2020-01-25 06:30:00
15038	1905	19	3	2019-08-14 09:00:00
15039	1905	19	3	2021-05-06 13:45:00
15040	1905	19	3	2020-05-19 07:30:00
15041	1905	19	3	2019-12-25 07:45:00
15042	1905	19	3	2020-10-25 14:00:00
15043	1905	19	3	2021-06-23 18:45:00
15044	1905	19	3	2019-12-23 19:00:00
15045	1905	19	3	2021-02-06 18:45:00
15046	1906	14	4	2019-11-25 19:45:00
15047	1906	14	4	2018-08-05 11:30:00
15048	1906	14	4	2020-02-03 22:45:00
15049	1906	14	4	2018-08-23 23:45:00
15050	1906	14	4	2019-05-23 01:30:00
15051	1906	14	4	2020-02-15 09:45:00
15052	1906	14	4	2019-11-03 06:15:00
15053	1906	14	4	2020-01-18 08:15:00
15054	1907	9	3	2020-07-07 13:30:00
15055	1907	9	3	2020-01-19 13:45:00
15056	1907	9	3	2018-10-03 13:15:00
15057	1907	9	3	2019-11-03 05:45:00
15058	1907	9	3	2019-07-07 02:15:00
15059	1907	9	3	2019-01-26 13:30:00
15060	1907	9	3	2020-08-29 16:30:00
15061	1907	9	3	2019-12-26 15:15:00
15062	1907	9	3	2020-06-07 03:30:00
15063	1907	9	3	2020-05-18 13:15:00
15064	1907	9	3	2020-02-04 18:45:00
15065	1907	9	3	2019-02-24 01:30:00
15066	1907	9	3	2019-01-23 23:00:00
15067	1908	9	9	2019-10-06 12:45:00
15068	1908	9	9	2018-11-18 22:15:00
15069	1908	9	9	2019-09-29 02:00:00
15070	1908	9	9	2020-02-18 21:30:00
15071	1908	9	9	2019-01-20 12:30:00
15072	1908	9	9	2019-09-24 17:45:00
15073	1908	9	9	2019-02-02 05:00:00
15074	1908	9	9	2020-01-02 10:00:00
15075	1909	7	19	2018-03-02 07:45:00
15076	1909	7	19	2018-12-29 02:45:00
15077	1909	7	19	2017-09-25 02:30:00
15078	1909	7	19	2018-05-13 16:15:00
15079	1909	7	19	2018-04-19 02:30:00
15080	1909	7	19	2017-03-15 01:00:00
15081	1909	7	19	2017-11-26 04:30:00
15082	1909	7	19	2018-09-02 23:15:00
15083	1909	7	19	2018-04-08 18:45:00
15084	1909	7	19	2017-09-26 07:00:00
15085	1909	7	19	2018-04-28 16:00:00
15086	1909	7	19	2018-06-12 08:00:00
15087	1909	7	19	2018-05-08 07:15:00
15088	1909	7	19	2018-01-15 23:15:00
15089	1910	19	7	2019-03-21 04:00:00
15090	1910	19	7	2019-03-25 21:45:00
15091	1910	19	7	2019-08-11 23:15:00
15092	1910	19	7	2020-02-11 05:30:00
15093	1910	19	7	2019-04-27 21:00:00
15094	1910	19	7	2019-07-20 21:15:00
15095	1910	19	7	2020-05-04 23:30:00
15096	1910	19	7	2021-01-30 17:15:00
15097	1910	19	7	2020-09-04 17:45:00
15098	1910	19	7	2019-09-09 16:00:00
15099	1911	9	17	2020-02-21 21:45:00
15100	1911	9	17	2018-05-13 14:30:00
15101	1911	9	17	2020-03-19 02:00:00
15102	1911	9	17	2019-12-20 02:45:00
15103	1911	9	17	2018-07-19 21:45:00
15104	1912	4	18	2017-09-27 10:15:00
15105	1912	4	18	2017-06-14 18:15:00
15106	1912	4	18	2018-02-04 10:15:00
15107	1912	4	18	2019-01-15 01:30:00
15108	1912	4	18	2018-10-28 20:15:00
15109	1912	4	18	2017-12-15 19:30:00
15110	1912	4	18	2017-07-25 07:45:00
15111	1913	2	3	2020-08-24 23:45:00
15112	1913	2	3	2019-11-30 17:15:00
15113	1913	2	3	2020-03-05 11:15:00
15114	1913	2	3	2020-03-28 16:15:00
15115	1913	2	3	2021-04-20 20:00:00
15116	1913	2	3	2021-01-23 10:00:00
15117	1914	1	8	2019-02-10 09:30:00
15118	1914	1	8	2017-11-18 16:15:00
15119	1914	1	8	2017-09-02 00:00:00
15120	1914	1	8	2017-08-01 14:45:00
15121	1914	1	8	2017-08-08 12:15:00
15122	1914	1	8	2018-10-05 11:30:00
15123	1914	1	8	2018-09-03 07:15:00
15124	1914	1	8	2018-03-04 00:45:00
15125	1914	1	8	2019-03-19 05:15:00
15126	1914	1	8	2017-06-10 03:00:00
15127	1914	1	8	2017-08-01 04:30:00
15128	1915	8	10	2019-03-10 20:00:00
15129	1915	8	10	2018-06-07 20:00:00
15130	1916	9	10	2018-04-26 20:30:00
15131	1916	9	10	2018-01-25 23:45:00
15132	1916	9	10	2018-10-15 07:30:00
15133	1916	9	10	2019-03-05 01:45:00
15134	1916	9	10	2018-12-27 21:45:00
15135	1916	9	10	2018-08-17 20:45:00
15136	1916	9	10	2018-03-15 10:30:00
15137	1916	9	10	2017-10-17 09:15:00
15138	1916	9	10	2017-06-16 20:30:00
15139	1916	9	10	2017-09-16 00:45:00
15140	1916	9	10	2017-09-26 06:00:00
15141	1916	9	10	2019-04-01 08:00:00
15142	1917	19	3	2018-07-27 14:15:00
15143	1917	19	3	2018-08-08 11:30:00
15144	1917	19	3	2018-04-16 04:30:00
15145	1917	19	3	2019-10-04 07:15:00
15146	1918	5	1	2020-11-11 13:00:00
15147	1918	5	1	2021-06-08 21:00:00
15148	1918	5	1	2021-03-10 02:30:00
15149	1919	14	3	2021-08-12 05:15:00
15150	1919	14	3	2020-10-07 18:15:00
15151	1919	14	3	2021-08-29 20:15:00
15152	1919	14	3	2021-01-08 22:00:00
15153	1919	14	3	2021-09-11 08:30:00
15154	1919	14	3	2020-07-15 16:15:00
15155	1919	14	3	2020-11-10 14:15:00
15156	1919	14	3	2021-04-06 14:30:00
15157	1920	18	14	2017-07-02 10:15:00
15158	1920	18	14	2019-02-07 21:15:00
15159	1920	18	14	2018-12-15 06:30:00
15160	1920	18	14	2018-12-07 18:15:00
15161	1920	18	14	2017-07-10 04:45:00
15162	1920	18	14	2018-03-02 18:00:00
15163	1920	18	14	2019-04-09 07:15:00
15164	1920	18	14	2019-06-13 11:00:00
15165	1920	18	14	2019-06-14 08:15:00
15166	1920	18	14	2018-02-06 12:45:00
15167	1920	18	14	2017-10-25 13:30:00
15168	1920	18	14	2018-11-29 13:00:00
15169	1920	18	14	2017-11-21 18:45:00
15170	1920	18	14	2019-06-08 07:30:00
15171	1921	18	13	2019-12-01 05:00:00
15172	1921	18	13	2018-05-21 03:45:00
15173	1921	18	13	2018-12-18 18:00:00
15174	1921	18	13	2019-06-15 16:30:00
15175	1921	18	13	2018-12-11 15:45:00
15176	1921	18	13	2018-07-18 03:00:00
15177	1921	18	13	2019-06-14 12:15:00
15178	1921	18	13	2018-03-18 21:30:00
15179	1922	5	4	2020-10-08 13:45:00
15180	1922	5	4	2020-04-21 05:00:00
15181	1922	5	4	2019-10-20 20:30:00
15182	1922	5	4	2020-02-12 08:45:00
15183	1922	5	4	2019-03-15 09:15:00
15184	1922	5	4	2020-09-04 18:30:00
15185	1922	5	4	2019-02-15 00:15:00
15186	1922	5	4	2020-01-07 01:15:00
15187	1922	5	4	2019-12-26 05:00:00
15188	1922	5	4	2020-08-20 08:15:00
15189	1922	5	4	2020-09-01 08:00:00
15190	1923	3	18	2019-09-11 06:00:00
15191	1923	3	18	2018-10-25 16:00:00
15192	1923	3	18	2018-07-05 03:30:00
15193	1923	3	18	2019-02-04 21:00:00
15194	1923	3	18	2018-05-21 23:45:00
15195	1924	3	10	2019-04-11 16:15:00
15196	1924	3	10	2018-02-02 08:30:00
15197	1925	18	8	2021-01-21 23:30:00
15198	1925	18	8	2021-10-02 09:00:00
15199	1925	18	8	2021-08-08 21:00:00
15200	1925	18	8	2020-11-07 12:30:00
15201	1925	18	8	2021-04-02 02:15:00
15202	1925	18	8	2020-04-03 13:00:00
15203	1925	18	8	2020-12-04 12:15:00
15204	1925	18	8	2021-05-14 15:30:00
15205	1925	18	8	2020-03-25 13:15:00
15206	1925	18	8	2021-07-02 03:45:00
15207	1925	18	8	2019-12-25 18:30:00
15208	1925	18	8	2021-03-07 01:45:00
15209	1925	18	8	2020-02-12 00:45:00
15210	1926	5	1	2017-07-24 11:45:00
15211	1926	5	1	2018-04-20 13:30:00
15212	1926	5	1	2019-02-03 07:15:00
15213	1926	5	1	2018-04-06 20:45:00
15214	1926	5	1	2017-08-06 18:00:00
15215	1926	5	1	2018-04-27 07:00:00
15216	1926	5	1	2018-03-29 05:15:00
15217	1926	5	1	2017-05-29 10:30:00
15218	1926	5	1	2018-12-16 03:30:00
15219	1926	5	1	2018-07-13 20:30:00
15220	1926	5	1	2018-05-21 12:00:00
15221	1926	5	1	2019-01-17 07:15:00
15222	1926	5	1	2018-04-07 07:45:00
15223	1926	5	1	2017-08-05 08:15:00
15224	1926	5	1	2019-01-26 05:30:00
15225	1927	8	9	2019-08-26 03:45:00
15226	1927	8	9	2020-09-22 09:30:00
15227	1927	8	9	2020-07-21 11:30:00
15228	1927	8	9	2020-06-23 14:30:00
15229	1927	8	9	2020-08-02 19:45:00
15230	1927	8	9	2020-08-05 10:15:00
15231	1927	8	9	2021-05-10 02:15:00
15232	1927	8	9	2020-02-25 15:45:00
15233	1927	8	9	2019-08-30 13:30:00
15234	1927	8	9	2021-04-30 11:30:00
15235	1927	8	9	2020-06-03 04:00:00
15236	1927	8	9	2020-01-18 16:45:00
15237	1927	8	9	2019-08-07 04:15:00
15238	1928	6	12	2020-04-30 16:30:00
15239	1928	6	12	2020-07-23 13:45:00
15240	1928	6	12	2021-01-25 01:45:00
15241	1928	6	12	2021-05-10 09:15:00
15242	1928	6	12	2021-06-09 12:45:00
15243	1928	6	12	2021-08-12 17:30:00
15244	1928	6	12	2021-07-29 07:45:00
15245	1928	6	12	2020-02-20 06:45:00
15246	1928	6	12	2020-09-24 11:45:00
15247	1928	6	12	2020-02-13 19:30:00
15248	1928	6	12	2021-10-19 11:15:00
15249	1928	6	12	2020-07-03 02:45:00
15250	1928	6	12	2020-06-04 08:30:00
15251	1928	6	12	2021-02-01 03:15:00
15252	1928	6	12	2021-05-13 18:45:00
15253	1929	14	19	2020-06-20 08:45:00
15254	1929	14	19	2019-11-28 17:45:00
15255	1929	14	19	2020-09-08 08:30:00
15256	1929	14	19	2020-10-01 21:15:00
15257	1929	14	19	2019-06-30 07:30:00
15258	1929	14	19	2019-05-10 14:30:00
15259	1929	14	19	2020-08-25 00:00:00
15260	1930	15	20	2019-02-26 20:30:00
15261	1930	15	20	2020-07-17 23:15:00
15262	1930	15	20	2019-07-29 03:00:00
15263	1930	15	20	2019-06-07 16:30:00
15264	1930	15	20	2020-10-21 06:30:00
15265	1930	15	20	2020-08-01 22:45:00
15266	1931	3	7	2020-03-28 05:00:00
15267	1931	3	7	2020-05-28 03:00:00
15268	1931	3	7	2021-05-16 23:30:00
15269	1931	3	7	2019-12-09 17:30:00
15270	1931	3	7	2019-11-08 08:30:00
15271	1931	3	7	2021-03-06 07:30:00
15272	1932	11	15	2018-07-05 07:15:00
15273	1932	11	15	2018-07-01 00:00:00
15274	1932	11	15	2019-06-16 20:00:00
15275	1932	11	15	2019-01-04 05:15:00
15276	1933	1	13	2019-11-05 14:00:00
15277	1933	1	13	2018-12-08 05:15:00
15278	1933	1	13	2019-03-09 15:45:00
15279	1933	1	13	2020-09-06 12:15:00
15280	1934	15	20	2020-06-17 06:00:00
15281	1934	15	20	2018-09-14 20:15:00
15282	1934	15	20	2019-03-03 21:15:00
15283	1935	2	20	2020-03-02 17:15:00
15284	1935	2	20	2019-06-27 07:45:00
15285	1935	2	20	2018-08-13 08:15:00
15286	1935	2	20	2020-02-26 03:00:00
15287	1935	2	20	2018-09-16 14:00:00
15288	1935	2	20	2019-03-23 22:00:00
15289	1936	10	19	2018-06-12 11:15:00
15290	1936	10	19	2018-11-01 21:15:00
15291	1936	10	19	2019-02-02 09:00:00
15292	1936	10	19	2019-02-01 20:15:00
15293	1936	10	19	2019-02-19 16:45:00
15294	1936	10	19	2017-10-03 21:45:00
15295	1936	10	19	2018-08-13 00:00:00
15296	1936	10	19	2018-04-17 19:30:00
15297	1936	10	19	2018-02-20 01:15:00
15298	1936	10	19	2018-09-09 07:15:00
15299	1936	10	19	2018-08-21 10:15:00
15300	1936	10	19	2018-05-28 13:30:00
15301	1936	10	19	2019-02-19 06:00:00
15302	1937	18	8	2019-04-05 08:30:00
15303	1937	18	8	2019-05-27 17:30:00
15304	1937	18	8	2019-01-15 12:45:00
15305	1937	18	8	2018-08-01 03:30:00
15306	1937	18	8	2018-06-28 18:15:00
15307	1937	18	8	2018-11-03 01:15:00
15308	1937	18	8	2018-10-04 06:00:00
15309	1937	18	8	2017-08-14 21:45:00
15310	1937	18	8	2018-10-04 03:30:00
15311	1937	18	8	2018-02-21 18:45:00
15312	1938	13	4	2018-09-08 15:00:00
15313	1938	13	4	2018-06-16 23:45:00
15314	1938	13	4	2019-03-29 16:00:00
15315	1938	13	4	2019-06-08 12:15:00
15316	1938	13	4	2019-03-13 02:30:00
15317	1938	13	4	2018-07-06 09:45:00
15318	1938	13	4	2018-07-28 23:15:00
15319	1938	13	4	2019-03-24 07:00:00
15320	1938	13	4	2017-09-23 03:45:00
15321	1939	12	9	2020-05-15 18:15:00
15322	1939	12	9	2020-01-22 18:15:00
15323	1939	12	9	2020-01-25 04:00:00
15324	1939	12	9	2020-01-11 19:00:00
15325	1939	12	9	2021-07-01 22:45:00
15326	1939	12	9	2020-10-15 11:15:00
15327	1939	12	9	2020-01-14 05:45:00
15328	1939	12	9	2020-02-04 07:00:00
15329	1939	12	9	2020-08-24 14:30:00
15330	1939	12	9	2020-06-24 09:30:00
15331	1939	12	9	2020-05-08 12:00:00
15332	1939	12	9	2021-02-22 02:00:00
15333	1940	12	15	2019-08-20 03:45:00
15334	1940	12	15	2019-06-28 19:15:00
15335	1940	12	15	2021-04-08 09:45:00
15336	1940	12	15	2020-09-07 15:45:00
15337	1940	12	15	2019-07-17 03:00:00
15338	1940	12	15	2019-06-18 10:15:00
15339	1940	12	15	2019-06-30 14:00:00
15340	1940	12	15	2019-07-25 01:45:00
15341	1940	12	15	2020-12-02 12:15:00
15342	1940	12	15	2021-04-23 13:15:00
15343	1940	12	15	2021-01-26 08:45:00
15344	1940	12	15	2021-05-06 10:30:00
15345	1940	12	15	2019-08-06 09:00:00
15346	1940	12	15	2020-07-22 11:45:00
15347	1941	12	10	2018-10-18 02:45:00
15348	1941	12	10	2019-04-03 22:45:00
15349	1942	13	3	2020-12-30 16:00:00
15350	1942	13	3	2020-09-19 09:00:00
15351	1942	13	3	2021-09-18 20:00:00
15352	1942	13	3	2020-05-24 03:00:00
15353	1942	13	3	2021-07-11 22:30:00
15354	1942	13	3	2020-10-15 13:00:00
15355	1942	13	3	2020-06-23 21:00:00
15356	1942	13	3	2021-08-24 05:00:00
15357	1942	13	3	2021-05-19 14:00:00
15358	1942	13	3	2020-11-27 07:15:00
15359	1943	8	16	2019-08-22 00:00:00
15360	1943	8	16	2018-12-25 09:30:00
15361	1944	5	17	2019-06-02 12:45:00
15362	1944	5	17	2019-02-17 22:30:00
15363	1945	4	7	2019-02-24 15:15:00
15364	1945	4	7	2019-07-21 04:00:00
15365	1945	4	7	2019-12-01 14:00:00
15366	1945	4	7	2019-11-07 20:45:00
15367	1945	4	7	2020-02-05 14:45:00
15368	1945	4	7	2020-01-14 17:00:00
15369	1945	4	7	2018-09-04 01:30:00
15370	1945	4	7	2019-09-09 11:15:00
15371	1945	4	7	2019-05-26 20:15:00
15372	1946	16	5	2020-01-22 04:00:00
15373	1946	16	5	2019-10-18 15:45:00
15374	1946	16	5	2019-03-29 08:30:00
15375	1946	16	5	2019-12-26 02:30:00
15376	1946	16	5	2018-08-23 19:15:00
15377	1946	16	5	2020-01-11 12:45:00
15378	1946	16	5	2018-05-30 11:15:00
15379	1946	16	5	2020-01-10 01:45:00
15380	1946	16	5	2018-05-19 18:15:00
15381	1946	16	5	2018-11-06 12:45:00
15382	1946	16	5	2019-03-22 16:45:00
15383	1946	16	5	2019-01-11 16:45:00
15384	1946	16	5	2018-09-26 00:00:00
15385	1946	16	5	2018-09-04 13:45:00
15386	1947	11	20	2020-01-20 14:00:00
15387	1947	11	20	2019-11-17 22:30:00
15388	1947	11	20	2018-10-17 16:15:00
15389	1947	11	20	2018-07-19 19:15:00
15390	1947	11	20	2018-08-27 11:30:00
15391	1947	11	20	2018-09-02 03:30:00
15392	1947	11	20	2020-01-14 07:45:00
15393	1947	11	20	2019-09-21 01:45:00
15394	1947	11	20	2018-12-12 03:00:00
15395	1947	11	20	2019-08-13 00:15:00
15396	1947	11	20	2019-04-15 04:15:00
15397	1947	11	20	2020-04-25 05:30:00
15398	1947	11	20	2019-01-06 23:45:00
15399	1947	11	20	2020-05-22 12:00:00
15400	1948	4	20	2020-02-08 02:45:00
15401	1948	4	20	2019-07-06 05:45:00
15402	1948	4	20	2019-06-04 05:45:00
15403	1948	4	20	2021-05-17 03:30:00
15404	1948	4	20	2019-09-21 18:00:00
15405	1948	4	20	2021-03-10 03:30:00
15406	1948	4	20	2019-07-23 23:00:00
15407	1948	4	20	2021-01-26 10:15:00
15408	1948	4	20	2019-06-25 02:30:00
15409	1949	17	10	2017-11-13 00:30:00
15410	1949	17	10	2017-07-08 12:30:00
15411	1949	17	10	2018-03-04 10:45:00
15412	1949	17	10	2019-05-07 21:00:00
15413	1949	17	10	2018-07-15 08:15:00
15414	1949	17	10	2018-02-04 10:15:00
15415	1949	17	10	2017-11-29 05:15:00
15416	1949	17	10	2019-03-13 18:00:00
15417	1949	17	10	2019-03-28 04:45:00
15418	1949	17	10	2017-11-01 16:15:00
15419	1950	20	5	2018-09-09 18:30:00
15420	1950	20	5	2019-05-07 02:00:00
15421	1950	20	5	2017-11-15 03:30:00
15422	1950	20	5	2019-02-20 15:45:00
15423	1950	20	5	2018-02-26 18:45:00
15424	1950	20	5	2018-03-24 23:45:00
15425	1950	20	5	2018-02-08 04:00:00
15426	1950	20	5	2019-06-08 23:00:00
15427	1951	7	13	2019-11-24 05:30:00
15428	1951	7	13	2020-06-04 07:15:00
15429	1952	10	17	2018-09-14 18:30:00
15430	1953	6	3	2018-02-02 06:30:00
15431	1953	6	3	2019-02-03 07:00:00
15432	1953	6	3	2018-05-26 01:30:00
15433	1953	6	3	2018-09-23 19:45:00
15434	1954	1	15	2018-11-05 00:30:00
15435	1954	1	15	2018-12-24 18:00:00
15436	1954	1	15	2019-02-13 13:00:00
15437	1954	1	15	2019-05-07 11:00:00
15438	1954	1	15	2018-03-12 21:15:00
15439	1954	1	15	2019-06-29 17:00:00
15440	1954	1	15	2017-11-19 21:15:00
15441	1954	1	15	2018-04-12 18:15:00
15442	1954	1	15	2018-01-13 16:00:00
15443	1954	1	15	2017-11-15 14:00:00
15444	1954	1	15	2019-04-14 20:30:00
15445	1954	1	15	2018-06-20 07:45:00
15446	1954	1	15	2019-06-04 11:30:00
15447	1955	20	13	2021-05-29 11:30:00
15448	1956	9	12	2019-07-03 00:45:00
15449	1956	9	12	2018-11-12 00:45:00
15450	1956	9	12	2018-12-25 20:00:00
15451	1956	9	12	2019-02-07 17:15:00
15452	1956	9	12	2019-06-04 08:45:00
15453	1956	9	12	2020-04-07 04:30:00
15454	1956	9	12	2018-12-03 21:00:00
15455	1956	9	12	2020-09-12 00:15:00
15456	1957	9	11	2019-10-23 23:45:00
15457	1957	9	11	2020-12-14 04:30:00
15458	1957	9	11	2020-10-11 02:45:00
15459	1958	14	10	2021-12-17 17:30:00
15460	1958	14	10	2021-01-15 14:30:00
15461	1958	14	10	2020-05-29 07:45:00
15462	1958	14	10	2020-05-29 05:30:00
15463	1958	14	10	2020-03-11 11:30:00
15464	1958	14	10	2020-07-13 10:30:00
15465	1958	14	10	2021-08-22 23:15:00
15466	1958	14	10	2021-04-10 11:00:00
15467	1958	14	10	2020-12-21 11:15:00
15468	1958	14	10	2020-04-20 17:45:00
15469	1958	14	10	2020-01-16 19:30:00
15470	1958	14	10	2020-06-07 07:00:00
15471	1958	14	10	2021-12-07 23:00:00
15472	1958	14	10	2020-10-25 13:45:00
15473	1959	16	18	2019-03-08 04:00:00
15474	1960	2	12	2018-12-22 07:45:00
15475	1960	2	12	2019-07-08 17:15:00
15476	1960	2	12	2020-04-20 19:00:00
15477	1960	2	12	2019-11-22 21:45:00
15478	1960	2	12	2020-02-05 18:00:00
15479	1961	14	11	2018-01-15 23:45:00
15480	1961	14	11	2018-01-09 10:45:00
15481	1961	14	11	2017-07-04 00:45:00
15482	1961	14	11	2017-06-15 03:00:00
15483	1961	14	11	2018-04-21 22:45:00
15484	1961	14	11	2018-08-23 04:00:00
15485	1961	14	11	2018-07-14 03:45:00
15486	1961	14	11	2018-09-19 03:15:00
15487	1961	14	11	2017-08-10 21:15:00
15488	1961	14	11	2018-10-05 03:00:00
15489	1961	14	11	2017-11-07 07:15:00
15490	1961	14	11	2018-09-03 18:15:00
15491	1961	14	11	2017-10-18 03:00:00
15492	1961	14	11	2017-06-12 03:45:00
15493	1962	9	7	2017-10-25 10:00:00
15494	1962	9	7	2018-01-22 14:30:00
15495	1962	9	7	2018-05-21 02:15:00
15496	1962	9	7	2019-02-10 11:45:00
15497	1962	9	7	2018-11-28 22:30:00
15498	1962	9	7	2018-03-10 00:45:00
15499	1962	9	7	2018-12-05 15:15:00
15500	1962	9	7	2018-04-02 18:45:00
15501	1962	9	7	2017-06-18 17:15:00
15502	1962	9	7	2019-03-29 05:15:00
15503	1962	9	7	2017-05-07 13:00:00
15504	1962	9	7	2017-11-20 01:15:00
15505	1962	9	7	2017-10-03 00:00:00
15506	1962	9	7	2017-07-08 20:00:00
15507	1963	15	16	2020-07-12 21:00:00
15508	1963	15	16	2019-06-06 17:30:00
15509	1963	15	16	2020-09-11 21:15:00
15510	1963	15	16	2020-03-26 02:30:00
15511	1963	15	16	2021-02-24 18:15:00
15512	1963	15	16	2020-08-14 23:30:00
15513	1963	15	16	2019-08-04 12:30:00
15514	1963	15	16	2019-11-06 11:15:00
15515	1963	15	16	2021-01-29 23:15:00
15516	1964	10	5	2017-12-10 07:30:00
15517	1964	10	5	2019-06-11 00:45:00
15518	1964	10	5	2017-10-29 02:45:00
15519	1964	10	5	2018-02-03 15:30:00
15520	1964	10	5	2018-11-18 06:45:00
15521	1964	10	5	2018-12-22 03:15:00
15522	1964	10	5	2017-09-09 19:30:00
15523	1964	10	5	2019-01-04 12:00:00
15524	1964	10	5	2018-12-14 20:00:00
15525	1964	10	5	2017-12-06 08:15:00
15526	1964	10	5	2017-10-16 00:45:00
15527	1964	10	5	2018-05-05 10:15:00
15528	1964	10	5	2019-03-15 09:00:00
15529	1964	10	5	2019-01-30 04:15:00
15530	1965	16	1	2018-12-08 20:45:00
15531	1965	16	1	2018-01-25 22:30:00
15532	1966	9	2	2020-07-14 16:30:00
15533	1966	9	2	2021-09-23 17:30:00
15534	1966	9	2	2021-06-28 07:00:00
15535	1966	9	2	2021-05-29 03:45:00
15536	1966	9	2	2021-07-18 09:15:00
15537	1966	9	2	2019-10-18 07:45:00
15538	1966	9	2	2021-03-10 03:15:00
15539	1966	9	2	2021-02-02 20:45:00
15540	1966	9	2	2020-10-22 12:45:00
15541	1967	14	3	2021-05-22 07:15:00
15542	1967	14	3	2021-05-03 06:45:00
15543	1967	14	3	2020-01-15 05:45:00
15544	1967	14	3	2021-07-15 18:30:00
15545	1967	14	3	2021-07-23 10:30:00
15546	1967	14	3	2021-03-23 15:30:00
15547	1967	14	3	2020-01-20 02:00:00
15548	1967	14	3	2020-11-06 01:15:00
15549	1967	14	3	2020-12-11 17:30:00
15550	1967	14	3	2021-08-16 05:00:00
15551	1967	14	3	2021-01-01 12:15:00
15552	1968	2	16	2021-03-19 04:30:00
15553	1968	2	16	2021-04-26 19:15:00
15554	1968	2	16	2019-11-10 20:15:00
15555	1968	2	16	2020-02-14 15:30:00
15556	1969	20	8	2020-01-20 21:45:00
15557	1970	19	8	2019-12-03 19:15:00
15558	1970	19	8	2020-06-05 05:30:00
15559	1970	19	8	2020-01-13 14:00:00
15560	1970	19	8	2020-04-30 13:30:00
15561	1970	19	8	2020-07-09 11:15:00
15562	1970	19	8	2020-06-08 09:00:00
15563	1970	19	8	2020-08-08 21:30:00
15564	1970	19	8	2019-12-29 07:00:00
15565	1970	19	8	2019-11-23 22:00:00
15566	1970	19	8	2019-08-04 21:30:00
15567	1970	19	8	2020-11-20 18:45:00
15568	1970	19	8	2019-02-12 19:00:00
15569	1970	19	8	2020-08-21 20:45:00
15570	1970	19	8	2019-09-07 04:30:00
15571	1970	19	8	2020-09-20 21:45:00
15572	1971	12	18	2018-08-21 02:15:00
15573	1971	12	18	2017-09-10 09:45:00
15574	1971	12	18	2019-01-27 20:30:00
15575	1971	12	18	2017-09-21 02:45:00
15576	1971	12	18	2017-05-26 01:45:00
15577	1971	12	18	2018-10-02 18:30:00
15578	1971	12	18	2018-11-08 05:00:00
15579	1971	12	18	2018-02-12 02:15:00
15580	1971	12	18	2018-10-09 12:15:00
15581	1971	12	18	2017-02-06 11:30:00
15582	1971	12	18	2018-01-13 21:45:00
15583	1971	12	18	2017-12-03 13:30:00
15584	1971	12	18	2018-08-14 19:00:00
15585	1972	2	14	2019-11-27 05:45:00
15586	1972	2	14	2019-10-12 20:45:00
15587	1972	2	14	2019-01-10 18:45:00
15588	1972	2	14	2019-07-02 03:15:00
15589	1972	2	14	2020-05-11 16:00:00
15590	1972	2	14	2019-03-16 17:30:00
15591	1972	2	14	2019-01-06 15:15:00
15592	1972	2	14	2020-04-25 09:00:00
15593	1972	2	14	2019-08-10 19:15:00
15594	1973	7	3	2020-11-12 13:00:00
15595	1973	7	3	2020-08-12 11:45:00
15596	1973	7	3	2020-09-09 09:00:00
15597	1973	7	3	2021-07-05 23:00:00
15598	1973	7	3	2019-10-24 12:45:00
15599	1973	7	3	2020-07-15 09:00:00
15600	1973	7	3	2019-12-10 13:00:00
15601	1973	7	3	2020-03-05 05:45:00
15602	1973	7	3	2019-12-08 18:15:00
15603	1973	7	3	2021-01-27 05:00:00
15604	1973	7	3	2020-10-23 20:15:00
15605	1973	7	3	2019-10-14 07:45:00
15606	1973	7	3	2020-03-06 09:15:00
15607	1974	18	7	2019-01-21 08:45:00
15608	1974	18	7	2018-05-05 06:30:00
15609	1974	18	7	2017-12-06 02:00:00
15610	1974	18	7	2017-07-06 06:00:00
15611	1974	18	7	2018-06-16 23:45:00
15612	1974	18	7	2018-10-18 14:30:00
15613	1974	18	7	2018-11-26 00:30:00
15614	1974	18	7	2017-04-07 15:15:00
15615	1974	18	7	2017-02-02 01:30:00
15616	1974	18	7	2018-08-19 04:30:00
15617	1974	18	7	2017-03-12 09:30:00
15618	1974	18	7	2018-08-03 04:15:00
15619	1975	15	14	2019-08-10 19:15:00
15620	1975	15	14	2020-07-29 05:15:00
15621	1975	15	14	2019-04-02 14:45:00
15622	1975	15	14	2019-06-14 10:45:00
15623	1975	15	14	2019-04-27 17:45:00
15624	1975	15	14	2019-05-01 20:15:00
15625	1975	15	14	2019-08-28 23:45:00
15626	1975	15	14	2019-03-21 07:00:00
15627	1975	15	14	2020-09-08 18:15:00
15628	1975	15	14	2020-05-09 15:45:00
15629	1975	15	14	2019-09-07 05:30:00
15630	1975	15	14	2019-09-29 14:15:00
15631	1975	15	14	2019-09-22 16:00:00
15632	1976	17	14	2020-05-30 14:00:00
15633	1976	17	14	2021-01-26 16:45:00
15634	1976	17	14	2021-06-25 17:00:00
15635	1976	17	14	2020-05-15 11:15:00
15636	1976	17	14	2020-05-10 11:30:00
15637	1976	17	14	2019-08-23 20:00:00
15638	1976	17	14	2021-06-08 04:30:00
15639	1976	17	14	2020-10-30 11:15:00
15640	1976	17	14	2020-07-16 04:15:00
15641	1976	17	14	2020-08-06 05:15:00
15642	1976	17	14	2021-06-13 14:15:00
15643	1976	17	14	2019-07-15 10:30:00
15644	1976	17	14	2020-09-02 22:15:00
15645	1976	17	14	2019-07-19 15:45:00
15646	1977	11	16	2019-06-07 16:45:00
15647	1977	11	16	2019-08-14 15:15:00
15648	1977	11	16	2018-05-28 03:30:00
15649	1977	11	16	2018-04-16 07:15:00
15650	1977	11	16	2019-01-05 13:15:00
15651	1977	11	16	2019-05-11 02:30:00
15652	1977	11	16	2018-02-07 01:45:00
15653	1977	11	16	2019-08-11 15:30:00
15654	1977	11	16	2018-08-04 13:30:00
15655	1977	11	16	2018-10-08 08:30:00
15656	1977	11	16	2019-06-28 06:30:00
15657	1978	17	20	2020-06-30 00:15:00
15658	1978	17	20	2020-05-20 01:30:00
15659	1979	10	20	2018-12-05 11:15:00
15660	1979	10	20	2019-08-05 17:30:00
15661	1979	10	20	2019-07-18 19:30:00
15662	1980	12	17	2020-05-27 10:00:00
15663	1980	12	17	2020-03-06 05:45:00
15664	1980	12	17	2021-02-10 03:45:00
15665	1981	4	2	2019-06-05 15:15:00
15666	1981	4	2	2019-04-03 11:30:00
15667	1981	4	2	2018-12-22 17:45:00
15668	1981	4	2	2019-02-07 17:00:00
15669	1981	4	2	2020-09-20 01:15:00
15670	1981	4	2	2020-04-27 06:00:00
15671	1981	4	2	2019-10-24 17:30:00
15672	1982	18	2	2019-09-28 05:00:00
15673	1982	18	2	2020-02-21 06:15:00
15674	1982	18	2	2020-03-03 02:00:00
15675	1982	18	2	2019-08-11 02:15:00
15676	1982	18	2	2020-09-30 04:30:00
15677	1982	18	2	2019-12-15 12:00:00
15678	1982	18	2	2019-09-28 22:30:00
15679	1983	7	6	2018-07-21 15:00:00
15680	1983	7	6	2017-11-27 03:15:00
15681	1983	7	6	2018-01-06 22:45:00
15682	1983	7	6	2019-07-23 05:15:00
15683	1983	7	6	2019-05-10 01:30:00
15684	1983	7	6	2019-08-06 16:30:00
15685	1983	7	6	2019-01-26 21:45:00
15686	1983	7	6	2017-12-23 20:30:00
15687	1983	7	6	2017-12-10 09:45:00
15688	1983	7	6	2018-06-25 18:45:00
15689	1983	7	6	2019-04-02 14:30:00
15690	1983	7	6	2018-03-16 01:30:00
15691	1984	18	15	2021-08-16 16:15:00
15692	1984	18	15	2021-04-14 08:00:00
15693	1984	18	15	2020-03-24 12:30:00
15694	1984	18	15	2021-07-25 16:30:00
15695	1984	18	15	2020-05-28 14:15:00
15696	1984	18	15	2021-04-14 07:00:00
15697	1985	11	7	2020-04-10 06:15:00
15698	1985	11	7	2020-11-17 16:45:00
15699	1985	11	7	2020-01-05 06:15:00
15700	1985	11	7	2020-07-09 19:15:00
15701	1985	11	7	2021-05-25 05:15:00
15702	1985	11	7	2021-02-03 09:15:00
15703	1985	11	7	2021-02-12 08:30:00
15704	1985	11	7	2020-04-15 01:30:00
15705	1985	11	7	2020-11-28 18:00:00
15706	1985	11	7	2021-03-23 09:30:00
15707	1985	11	7	2020-03-20 12:15:00
15708	1985	11	7	2021-02-14 17:00:00
15709	1986	20	3	2018-10-29 11:15:00
15710	1987	15	10	2020-01-13 23:15:00
15711	1987	15	10	2018-10-19 20:15:00
15712	1987	15	10	2020-03-06 20:15:00
15713	1987	15	10	2019-12-12 05:45:00
15714	1987	15	10	2018-12-12 08:45:00
15715	1987	15	10	2019-07-11 18:30:00
15716	1988	9	15	2018-06-23 15:15:00
15717	1988	9	15	2017-11-15 20:45:00
15718	1988	9	15	2017-05-25 03:15:00
15719	1988	9	15	2017-04-30 04:30:00
15720	1988	9	15	2017-06-26 11:45:00
15721	1989	2	15	2018-10-28 04:15:00
15722	1989	2	15	2018-05-30 21:30:00
15723	1989	2	15	2018-08-30 09:15:00
15724	1989	2	15	2018-07-09 23:45:00
15725	1989	2	15	2019-01-25 11:30:00
15726	1989	2	15	2019-02-16 10:45:00
15727	1989	2	15	2019-08-01 22:00:00
15728	1989	2	15	2019-09-18 06:45:00
15729	1989	2	15	2018-03-23 10:15:00
15730	1989	2	15	2018-12-08 22:00:00
15731	1989	2	15	2019-10-30 17:15:00
15732	1989	2	15	2019-04-22 17:45:00
15733	1989	2	15	2017-11-17 07:15:00
15734	1989	2	15	2019-08-13 14:30:00
15735	1989	2	15	2018-07-15 20:30:00
15736	1990	2	19	2019-11-21 01:00:00
15737	1990	2	19	2019-10-28 18:00:00
15738	1990	2	19	2018-04-22 20:45:00
15739	1990	2	19	2018-12-17 17:00:00
15740	1990	2	19	2018-03-11 16:45:00
15741	1990	2	19	2018-08-06 03:30:00
15742	1991	10	6	2018-06-24 10:45:00
15743	1991	10	6	2017-08-13 09:15:00
15744	1991	10	6	2019-02-23 03:15:00
15745	1991	10	6	2019-02-24 06:15:00
15746	1991	10	6	2019-06-09 09:30:00
15747	1991	10	6	2017-08-28 03:30:00
15748	1991	10	6	2017-11-13 20:30:00
15749	1991	10	6	2017-07-08 14:15:00
15750	1991	10	6	2018-03-23 14:30:00
15751	1991	10	6	2018-03-11 13:45:00
15752	1992	5	8	2019-06-09 22:45:00
15753	1992	5	8	2019-04-10 01:15:00
15754	1992	5	8	2018-07-03 10:15:00
15755	1992	5	8	2018-03-03 03:30:00
15756	1992	5	8	2019-04-03 19:15:00
15757	1992	5	8	2018-09-22 21:15:00
15758	1992	5	8	2018-05-17 07:30:00
15759	1992	5	8	2019-02-01 13:15:00
15760	1992	5	8	2019-03-28 13:45:00
15761	1992	5	8	2019-09-08 21:15:00
15762	1993	18	16	2019-03-17 04:45:00
15763	1993	18	16	2019-04-29 03:00:00
15764	1993	18	16	2020-04-18 10:00:00
15765	1993	18	16	2020-07-17 11:15:00
15766	1993	18	16	2019-05-12 21:00:00
15767	1993	18	16	2020-08-27 07:15:00
15768	1994	11	1	2017-11-11 15:45:00
15769	1994	11	1	2018-03-22 03:00:00
15770	1995	2	19	2021-01-03 20:45:00
15771	1995	2	19	2020-07-03 21:45:00
15772	1996	11	6	2019-04-24 03:30:00
15773	1996	11	6	2020-05-03 06:00:00
15774	1996	11	6	2019-01-21 18:30:00
15775	1996	11	6	2020-04-13 03:00:00
15776	1996	11	6	2019-09-28 04:30:00
15777	1996	11	6	2020-02-02 08:30:00
15778	1996	11	6	2020-02-22 14:45:00
15779	1996	11	6	2020-09-18 14:00:00
15780	1996	11	6	2019-10-15 14:15:00
15781	1996	11	6	2019-08-08 00:15:00
15782	1996	11	6	2019-03-06 16:00:00
15783	1997	13	13	2021-03-03 01:00:00
15784	1997	13	13	2020-08-08 20:45:00
15785	1997	13	13	2021-01-21 18:00:00
15786	1997	13	13	2021-04-19 01:15:00
15787	1997	13	13	2019-12-14 22:15:00
15788	1997	13	13	2019-08-29 07:00:00
15789	1997	13	13	2021-01-19 21:00:00
15790	1997	13	13	2020-05-12 11:00:00
15791	1998	8	10	2021-06-17 17:15:00
15792	1999	20	13	2020-03-12 20:00:00
15793	1999	20	13	2020-05-21 02:00:00
15794	1999	20	13	2020-01-09 01:30:00
15795	1999	20	13	2019-12-30 01:00:00
15796	1999	20	13	2019-07-24 10:15:00
15797	1999	20	13	2020-02-17 23:00:00
15798	1999	20	13	2019-10-30 09:00:00
15799	1999	20	13	2018-10-27 21:30:00
15800	1999	20	13	2018-11-03 02:45:00
15801	1999	20	13	2019-02-05 09:00:00
15802	2000	18	18	2019-09-23 07:15:00
15803	2000	18	18	2019-04-11 21:30:00
15804	2000	18	18	2020-06-30 07:15:00
15805	2000	18	18	2020-04-16 05:30:00
15806	2000	18	18	2020-02-12 17:30:00
\.


--
-- Name: cars_car_seq; Type: SEQUENCE SET; Schema: driving_school; Owner: stephan
--

SELECT pg_catalog.setval('driving_school.cars_car_seq', 20, true);


--
-- Name: clients_client_seq; Type: SEQUENCE SET; Schema: driving_school; Owner: stephan
--

SELECT pg_catalog.setval('driving_school.clients_client_seq', 2000, true);


--
-- Name: employees_emp_seq; Type: SEQUENCE SET; Schema: driving_school; Owner: stephan
--

SELECT pg_catalog.setval('driving_school.employees_emp_seq', 27, true);


--
-- Name: interviews_interview_seq; Type: SEQUENCE SET; Schema: driving_school; Owner: stephan
--

SELECT pg_catalog.setval('driving_school.interviews_interview_seq', 2000, true);


--
-- Name: lessons_lesson_seq; Type: SEQUENCE SET; Schema: driving_school; Owner: stephan
--

SELECT pg_catalog.setval('driving_school.lessons_lesson_seq', 15806, true);


--
-- Name: cars cars_pkey; Type: CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.cars
    ADD CONSTRAINT cars_pkey PRIMARY KEY (car);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (client);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (emp);


--
-- Name: interviews interviews_client_key; Type: CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.interviews
    ADD CONSTRAINT interviews_client_key UNIQUE (client);


--
-- Name: interviews interviews_pkey; Type: CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.interviews
    ADD CONSTRAINT interviews_pkey PRIMARY KEY (interview);


--
-- Name: lessons lessons_pkey; Type: CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.lessons
    ADD CONSTRAINT lessons_pkey PRIMARY KEY (lesson);


--
-- Name: clients clients_car_fkey; Type: FK CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.clients
    ADD CONSTRAINT clients_car_fkey FOREIGN KEY (car) REFERENCES driving_school.cars(car);


--
-- Name: clients clients_instructor_fkey; Type: FK CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.clients
    ADD CONSTRAINT clients_instructor_fkey FOREIGN KEY (instructor) REFERENCES driving_school.employees(emp);


--
-- Name: interviews interviews_client_fkey; Type: FK CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.interviews
    ADD CONSTRAINT interviews_client_fkey FOREIGN KEY (client) REFERENCES driving_school.clients(client);


--
-- Name: interviews interviews_employee_fkey; Type: FK CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.interviews
    ADD CONSTRAINT interviews_employee_fkey FOREIGN KEY (employee) REFERENCES driving_school.employees(emp);


--
-- Name: lessons lessons_car_fkey; Type: FK CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.lessons
    ADD CONSTRAINT lessons_car_fkey FOREIGN KEY (car) REFERENCES driving_school.cars(car);


--
-- Name: lessons lessons_client_fkey; Type: FK CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.lessons
    ADD CONSTRAINT lessons_client_fkey FOREIGN KEY (client) REFERENCES driving_school.clients(client);


--
-- Name: lessons lessons_instructor_fkey; Type: FK CONSTRAINT; Schema: driving_school; Owner: stephan
--

ALTER TABLE ONLY driving_school.lessons
    ADD CONSTRAINT lessons_instructor_fkey FOREIGN KEY (instructor) REFERENCES driving_school.employees(emp);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO PUBLIC;


--
-- Name: PROCEDURE add_client(name character varying, birth date, instructor integer, car integer, interview_start timestamp without time zone); Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT ALL ON PROCEDURE driving_school.add_client(name character varying, birth date, instructor integer, car integer, interview_start timestamp without time zone) TO administrative_staff;


--
-- Name: PROCEDURE add_lesson(client_id integer, instructor_id integer, start_time timestamp without time zone); Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT ALL ON PROCEDURE driving_school.add_lesson(client_id integer, instructor_id integer, start_time timestamp without time zone) TO administrative_staff;
GRANT ALL ON PROCEDURE driving_school.add_lesson(client_id integer, instructor_id integer, start_time timestamp without time zone) TO instructor;


--
-- Name: FUNCTION get_success_rate(); Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT ALL ON FUNCTION driving_school.get_success_rate() TO administrative_staff;


--
-- Name: FUNCTION get_work_load(emp_id integer, start_date date, end_date date); Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT ALL ON FUNCTION driving_school.get_work_load(emp_id integer, start_date date, end_date date) TO administrative_staff;
GRANT ALL ON FUNCTION driving_school.get_work_load(emp_id integer, start_date date, end_date date) TO instructor;
GRANT ALL ON FUNCTION driving_school.get_work_load(emp_id integer, start_date date, end_date date) TO dummy;


--
-- Name: PROCEDURE update_client_status_passed(client_id integer, passed boolean); Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT ALL ON PROCEDURE driving_school.update_client_status_passed(client_id integer, passed boolean) TO instructor;


--
-- Name: PROCEDURE update_client_status_ready(is_ready boolean, client_id integer); Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT ALL ON PROCEDURE driving_school.update_client_status_ready(is_ready boolean, client_id integer) TO instructor;


--
-- Name: PROCEDURE update_tech_check(id integer); Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT ALL ON PROCEDURE driving_school.update_tech_check(id integer) TO auto_technician;


--
-- Name: TABLE cars; Type: ACL; Schema: driving_school; Owner: stephan
--

GRANT SELECT ON TABLE driving_school.cars TO auto_technician;


--
-- PostgreSQL database dump complete
--

