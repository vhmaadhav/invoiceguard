-- 09_scheduler_job.sql
-- IG_VALIDATE_JOB: every 15 minutes validate DRAFT/ON_HOLD invoices, then run the
-- post-approval scan. Created DISABLED so installing never starts background work.
-- Enable on a real environment with: EXEC DBMS_SCHEDULER.ENABLE('IG_VALIDATE_JOB');

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

DECLARE
  l_cnt NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_cnt FROM user_scheduler_jobs WHERE job_name = 'IG_VALIDATE_JOB';
  IF l_cnt > 0 THEN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'IG_VALIDATE_JOB', force => TRUE);
  END IF;

  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'IG_VALIDATE_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN ig_match_pkg.validate_all_draft; ig_audit_pkg.scan_approvals; COMMIT; END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=MINUTELY;INTERVAL=15',
    enabled         => FALSE,
    auto_drop       => FALSE,
    comments        => 'InvoiceGuard: validate draft invoices and scan approvals (every 15 min)');
END;
/

SET DEFINE OFF
PROMPT Scheduler job IG_VALIDATE_JOB created (disabled).
