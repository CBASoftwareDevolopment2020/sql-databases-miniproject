SELECT add_lesson(69420, 2, '2019-11-11 12:00');
-- NOTICE:  The client doesnt exits

SELECT add_lesson(1, 69420, '2019-11-11 12:00');
-- NOTICE:  The employee doesnt exits

SELECT add_lesson(1, 25, '2019-11-11 12:00');
-- NOTICE:  Employee must be an instructor

SELECT add_lesson(1, 1, '2019-11-11 12:00');
-- NOTICE:  Date must be after current date

SELECT add_lesson(2001, 1, '2021-11-11 12:00');
-- NOTICE:  NOTICE:  An interview is required to book lessons