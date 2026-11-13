-- install.sql
-- Installs the InvoiceGuard schema as IG. Run from the db/ directory:
--   sqlplus -S ig/<pw>@//localhost:1521/FREEPDB1 @install.sql
-- Exits with failure on any SQL error or any invalid object.

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

PROMPT === 01 tables
@@01_tables.sql
PROMPT === 02 util and session packages
@@02_util_session_pkg.sql
PROMPT === 03 match package
@@03_match_pkg.sql
PROMPT === 04 workflow and audit packages
@@04_workflow_audit_pkg.sql
PROMPT === 05 triggers
@@05_triggers.sql
PROMPT === 06 views
@@06_views.sql
PROMPT === 07 reference data
@@07_reference_data.sql
PROMPT === 08 seed
@@08_seed.sql
PROMPT === 09 scheduler job
@@09_scheduler_job.sql

COMMIT;

PROMPT === invalid objects
SELECT object_type, object_name FROM user_objects WHERE status = 'INVALID' ORDER BY object_type, object_name;

DECLARE
  l_invalid NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_invalid FROM user_objects WHERE status = 'INVALID';
  DBMS_OUTPUT.PUT_LINE('Invalid objects: ' || l_invalid);
  IF l_invalid > 0 THEN
    RAISE_APPLICATION_ERROR(-20999, 'install left ' || l_invalid || ' invalid objects');
  END IF;
END;
/

PROMPT Install complete.
