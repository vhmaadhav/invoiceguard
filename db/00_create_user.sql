-- 00_create_user.sql
-- Run as SYS in FREEPDB1. Idempotent: creates IG or resets its password.
-- Usage: sqlplus sys/<pw>@//host:port/FREEPDB1 as sysdba @00_create_user.sql <ig_password>
-- Local development only.

SET DEFINE ON
SET VERIFY OFF
WHENEVER SQLERROR EXIT FAILURE

DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM dba_users WHERE username = 'IG';
  IF l_cnt = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER ig IDENTIFIED BY "&1" QUOTA UNLIMITED ON users';
  ELSE
    EXECUTE IMMEDIATE 'ALTER USER ig IDENTIFIED BY "&1" QUOTA UNLIMITED ON users';
  END IF;
END;
/

GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE VIEW,
      CREATE SEQUENCE,
      CREATE PROCEDURE,
      CREATE TRIGGER,
      CREATE TYPE,
      CREATE JOB
  TO ig;

SET DEFINE OFF
PROMPT IG user ready.
