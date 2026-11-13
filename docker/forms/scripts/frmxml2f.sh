#!/bin/sh
# frmxml2f: Forms XML (*_fmb.xml, *_mmb.xml) -> binary .fmb/.mmb, via oracle.forms.util.xmltools.XML2Forms.
# Replaces the installer's frmxml2f wrapper: that copy still has unfilled %ORACLE_HOME%-style placeholders.
ORACLE_HOME="${ORACLE_HOME:-/u01/oracle/fmw}"
CP="$ORACLE_HOME/jlib/frmjdapi.jar:$ORACLE_HOME/jlib/frmxmltools.jar:$ORACLE_HOME/oracle_common/modules/oracle.xdk/xmlparserv2.jar"
NLS_LANG="${NLS_LANG:-AMERICAN_AMERICA.AL32UTF8}"
export NLS_LANG
LD_LIBRARY_PATH="$ORACLE_HOME/lib:$ORACLE_HOME/oracle_common/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "${JAVA_HOME:-/u01/jdk}/bin/java" -Djava.library.path="$ORACLE_HOME/lib" -classpath "$CP" oracle.forms.util.xmltools.XML2Forms "$@"
