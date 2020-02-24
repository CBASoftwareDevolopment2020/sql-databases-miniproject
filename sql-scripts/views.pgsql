CREATE OR REPLACE VIEW archive AS 
SELECT * 
FROM clients 
WHERE status = 'passed';

--

CREATE OR REPLACE VIEW failed_first_attempt AS 
SELECT * 
FROM clients 
WHERE attempts > 1 OR (attempts = 1 AND status != 'passed');