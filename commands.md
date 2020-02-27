# Postgres Commands

## Desciption Commands

_Show Tables and Views_

```plpgsql
\d
```

_Show Functions and Procedures_

```plpgsql
\df
```

_Show Specific Functions and Procedures_

```plpgsql
\df {NAME}
```

---

## Procedure - add_client

_Description_

```plpgsql
CALL add_client(name VARCHAR(30), birth DATE, instructor INTEGER, car INTEGER, interview_start TIMESTAMP);
```

_Raise Notice: Too young to drive_

```plpgsql
CALL add_client('Stephan', '2020-01-01', 1, 1, '2020-03-01');
```

---

## Procedure - add_lesson

_Description_

```plpgsql
CALL add_lesson(client_id INTEGER, instructor_id INTEGER, start_time TIMESTAMP);
```

_Raise Notice: The client doesnt exits_

```plpgsql
CALL add_lesson(5000, 1, '2020-03-01 12:00');
```

_Raise Notice: The employee doesnt exits_

```plpgsql
CALL add_lesson(1, 5000, '2020-03-01 12:00');
```

_Raise Notice: Date must be after current date_

```plpgsql
CALL add_lesson(1, 1, '2010-03-01 12:00');
```

_Raise Notice: The car isnt available at this date_

```plpgsql
CALL add_lesson(14, 1, '2021-07-24 22:00');
```

---

## Procedure - update_client_status_ready

_Description_

```plpgsql
CALL update_client_status_ready(is_ready BOOLEAN, client_id INTEGER);
```

_Raise Notice: A minimum of 10 participated is required, only 0 acquired._

```plpgsql
CALL update_client_status_ready(true, 3);
```

_Raise Notice: Client status set to: not ready._

```plpgsql
CALL update_client_status_ready(false, 1);
```

---

## Procedure - update_client_status_passed

_Description_

```plpgsql
CALL update_client_status_passed(client_id INTEGER, passed BOOLEAN);
```

_Raise Notice: The client must be ready before passing._

```plpgsql
CALL update_client_status_passed(3, true);
```

_Success_

```plpgsql
CALL update_client_status_passed(1, true);
```

---

## Procedure - update_tech_check

_Description_

```plpgsql
CALL update_tech_check(id INTEGER);
```

_Success_

```plpgsql
CALL update_tech_check(1);
```

---

## Function - get_success_rate

_Description_

```plpgsql
SELECT get_success_rate();
```

---

## Function - get_work_load

_Description_

```plpgsql
SELECT get_work_load(emp_id INTEGER, start_date DATE, end_date DATE);
```

_Success_

```plpgsql
SELECT get_work_load(1, '2020-01-01', '2020-06-01');
```

---
