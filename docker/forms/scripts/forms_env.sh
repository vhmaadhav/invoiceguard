# Sourced by deploy_ig.sh, start.sh and the forms wrappers. Environment for the Oracle Forms 14.1.2
# command-line tools (frmxml2f, frmcmp_batch) and the runtime inside the forms container.
# Verified in the container:
#   TERM must be a known terminal type. vt100, xterm or unset gave FRM-91500; vt220 compiles.
#   EZConnect (//host:port/svc) in userid= gave "Form not created"; a TNS alias (IGDB) works.
#   FORMS_API_TK_BYPASS=TRUE is needed headless, otherwise JDAPI fails with "Failed to create new forms context".
export ORACLE_HOME="${ORACLE_HOME:-/u01/oracle/fmw}"
export MW_HOME="${MW_HOME:-$ORACLE_HOME}"
export DOMAIN_HOME="${DOMAIN_HOME:-/u01/oracle/user_projects/domains/ig_forms_domain}"
export FORMS_INSTANCE="${FORMS_INSTANCE:-forms1}"   # components/FORMS/forms1 from the domain template
export JAVA_HOME="${JAVA_HOME:-/u01/jdk}"
export CT_JAVA_HOME="$JAVA_HOME"
export O_JDK_HOME="$JAVA_HOME"
export TERM="${TERM:-vt220}"
export ORACLE_TERM="${ORACLE_TERM:-vt220}"
# Single-byte charset: a UTF-8 NLS_LANG makes the web runtime look for fmrweb_utf8, which this install lacks
export NLS_LANG="${NLS_LANG:-AMERICAN_AMERICA.WE8ISO8859P1}"
export FORMS_API_TK_BYPASS="${FORMS_API_TK_BYPASS:-TRUE}"
export TNS_ADMIN="${IG_TNS_ADMIN:-/u01/ig/tns}"
export LD_LIBRARY_PATH="$JAVA_HOME/lib/server:$JAVA_HOME/lib:$ORACLE_HOME/lib:$ORACLE_HOME/oracle_common/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# IG database alias used by every userid= (see deploy_ig.sh, which writes the file)
IG_TNS_ALIAS="IGDB"
IG_TNS_LINE="IGDB=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=${IG_DB_HOST:-invoiceguard-db})(PORT=${IG_DB_PORT:-1521}))(CONNECT_DATA=(SERVICE_NAME=${IG_DB_SERVICE:-FREEPDB1})))"
