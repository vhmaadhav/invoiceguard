-- uninstall.sql
-- Drops every IG_ object owned by IG (tables, views, packages, triggers, scheduler job).
-- Safe to run when nothing is installed.

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT FAILURE

DECLARE
  TYPE t_names IS TABLE OF VARCHAR2(128) INDEX BY PLS_INTEGER;
  TYPE t_types IS TABLE OF VARCHAR2(30) INDEX BY PLS_INTEGER;
  l_jobs  t_names;
  l_names t_names;
  l_types t_types;
  l_n     PLS_INTEGER;
BEGIN
  SELECT job_name BULK COLLECT INTO l_jobs
    FROM user_scheduler_jobs WHERE job_name LIKE 'IG\_%' ESCAPE '\';
  FOR i IN 1 .. l_jobs.COUNT LOOP
    DBMS_SCHEDULER.DROP_JOB(job_name => l_jobs(i), force => TRUE);
  END LOOP;

  -- several passes so dependent objects (views on tables, etc.) drop in a safe order
  FOR pass IN 1 .. 4 LOOP
    SELECT object_name, object_type BULK COLLECT INTO l_names, l_types
      FROM user_objects
     WHERE object_name LIKE 'IG\_%' ESCAPE '\'
       AND object_type IN ('VIEW', 'PACKAGE', 'TABLE')
     ORDER BY CASE object_type WHEN 'VIEW' THEN 1 WHEN 'PACKAGE' THEN 2 ELSE 3 END;
    EXIT WHEN l_names.COUNT = 0;
    FOR i IN 1 .. l_names.COUNT LOOP
      BEGIN
        IF l_types(i) = 'TABLE' THEN
          EXECUTE IMMEDIATE 'DROP TABLE "' || l_names(i) || '" CASCADE CONSTRAINTS PURGE';
        ELSE
          EXECUTE IMMEDIATE 'DROP ' || l_types(i) || ' "' || l_names(i) || '"';
        END IF;
      EXCEPTION
        WHEN OTHERS THEN NULL;  -- retried on the next pass
      END;
    END LOOP;
  END LOOP;

  SELECT COUNT(*) INTO l_n FROM user_objects WHERE object_name LIKE 'IG\_%' ESCAPE '\';
  DBMS_OUTPUT.PUT_LINE('IG objects remaining: ' || l_n);
END;
/
