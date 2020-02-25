CALL add_lesson(69420, 2, '2019-11-11 12:00');
-- NOTICE:  The client doesnt exits

CALL add_lesson(1, 69420, '2019-11-11 12:00');
-- NOTICE:  The employee doesnt exits

CALL add_lesson(1, 25, '2019-11-11 12:00');
-- NOTICE:  Employee must be an instructor

CALL add_lesson(1, 1, '2019-11-11 12:00');
-- NOTICE:  Date must be after current date

CALL add_lesson(2001, 1, '2021-11-11 12:00');
-- NOTICE:  An interview is required to book lessons

CALL add_lesson(1, 1, '2021-11-11 12:00');
-- NOTICE:  Client 1 successfully added to lessons

CALL add_lesson(1, 1, '2021-11-11 12:00');
-- NOTICE:  Client 1 successfully added to lessons