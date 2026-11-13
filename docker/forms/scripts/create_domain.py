# WLST (Jython 2.7) script: create the Forms WebLogic domain.
# Run with:  $MW_HOME/oracle_common/common/bin/wlst.sh /opt/ig/create_domain.py
#
# Not verified against Oracle's WLST reference for 14.1.2. The Forms template name is not
# quoted in any page we read ("Oracle Forms - 14.1.2.0.0 [forms]" is the Configuration Wizard
# label). Set FORMS_TEMPLATE to the template .jar path to skip discovery.
import os, sys

MW = os.environ.get('MW_HOME', '/u01/oracle/fmw')
DOMAIN = os.environ.get('DOMAIN_HOME', '/u01/oracle/user_projects/domains/ig_forms_domain')
PREFIX = os.environ.get('IG_RCU_PREFIX', 'IGF')
DB_URL = os.environ.get('IG_RCU_JDBC_URL', 'jdbc:oracle:thin:@//invoiceguard-db:1521/FREEPDB1')
RCU_PW = os.environ['IG_RCU_PASSWORD']
WLS_PW = os.environ['IG_WLS_PASSWORD']
DOMAIN_NAME = 'ig_forms_domain'

if os.path.isdir(DOMAIN):
    print('Domain already exists, skipping: ' + DOMAIN)
    sys.exit(0)


def find_template():
    if os.environ.get('FORMS_TEMPLATE'):
        return os.environ['FORMS_TEMPLATE']
    # Base Forms 14.1.2 domain template (the install ships several; the others are reconfig/UA/FADS variants).
    base = os.path.join(MW, 'forms', 'common', 'templates', 'wls', 'forms_template.jar')
    if os.path.isfile(base):
        return base
    hits = []
    for root, dirs, files in os.walk(MW):
        for f in files:
            p = os.path.join(root, f)
            if f.lower().endswith('.jar') and 'forms' in p.lower() and 'template' in p.lower():
                hits.append(p)
    if len(hits) != 1:
        print('Could not pick a single Forms template jar, candidates:')
        for h in hits:
            print('  ' + h)
        print('Set FORMS_TEMPLATE to the right one.')
        sys.exit(1)
    return hits[0]


TEMPLATE = find_template()
print('Template: ' + TEMPLATE)
# Base domain template, then extension templates. WLST refuses readTemplate() on a template with
# prerequisites, so the prerequisites (listed by WLST in the error text for forms_template.jar) are
# added first. addTemplate() calls that fail on a missing dependency are retried in later passes.
BASE_TEMPLATE = os.path.join(MW, 'wlserver', 'common', 'templates', 'wls', 'wls.jar')
PREREQS = [
    'oracle_common/common/templates/wls/oracle.wc_skin_template.jar',
    'oracle_common/common/templates/wls/oracle.wc_composer_template.jar',
    'oracle_common/common/templates/wls/oracle.opss.rest_template.jar',
    'oracle_common/common/templates/wls/oracle.wsmjksmgmt_template.jar',
    'oracle_common/common/templates/wls/oracle.wsmagent_template.jar',
    'wlserver/common/templates/wls/wls_schema.jar',
    'oracle_common/common/templates/wls/oracle.security.sso_template.jar',
    'oracle_common/common/templates/wls/oracle.wsmpolicyattachment_template.jar',
    'oracle_common/common/templates/wls/oracle.state-management.memory-provider-template.jar',
    'oracle_common/common/templates/wls/oracle.jrf.ws.core_template.jar',
    'oracle_common/common/templates/wls/oracle.cie.runtime_template.jar',
    'oracle_common/common/templates/wls/oracle.ums.client_template.jar',
    'oracle_common/common/templates/wls/oracle.opss_jrf_metadata_template.jar',
    'oracle_common/common/templates/wls/oracle.adf.template.jar',
    'wlserver/common/templates/wls/wls_coherence_template.jar',
    'oracle_common/common/templates/wls/oracle.clickhistory_template.jar',
    'wlserver/common/templates/wls/wls_jrf.jar',
    'oracle_common/common/templates/wls/oracle.jrf_base_template.jar',
    'oracle_common/common/templates/wls/oracle.jrf_template.jar',
    'oracle_common/common/templates/wls/oracle.wsm.console.core_template.jar',
    'em/common/templates/wls/oracle.emas_wls_template.jar',
    'em/common/templates/wls/oracle.em_wls_template.jar',
    'em/common/templates/wls/oracle.em_forms_template.jar',
]
readTemplate(BASE_TEMPLATE)
pending = [os.path.join(MW, p) for p in PREREQS] + [TEMPLATE]
for attempt in range(6):
    failed = []
    for t in pending:
        try:
            addTemplate(t)
            print('added ' + os.path.basename(t))
        except Exception as e:
            failed.append(t)
    pending = failed
    if not pending:
        break
if pending:
    print('Templates not added: ' + ', '.join(os.path.basename(t) for t in pending))
    sys.exit(1)

# Admin user password (domain name fixed)
cd('/')
set('Name', DOMAIN_NAME)
cd('/Security/' + DOMAIN_NAME + '/User/weblogic')
cmo.setPassword(WLS_PW)

# AdminServer on 7001
cd('/Servers/AdminServer')
set('ListenPort', 7001)

# Managed server for Forms on 9001
try:
    cd('/Servers/WLS_FORMS')
except:
    cd('/')
    create('WLS_FORMS', 'Server')
    cd('/Servers/WLS_FORMS')
set('ListenPort', 9001)

# Point every JDBC resource at the IG database with the IGF_* schema for its component.
# Offline WLST: navigate with cd()/ls(); cmo.getJDBCSystemResources() does not exist offline.
cd('/JDBCSystemResources')
jdbc_names = ls(returnMap='true')
for name in jdbc_names:
    low = name.lower()
    comp = 'STB'
    if 'mds' in low:
        comp = 'MDS'
    elif 'iau' in low or 'audit' in low:
        comp = 'IAU'
    elif 'opss' in low:
        comp = 'OPSS'
    elif 'wls' in low:
        comp = 'WLS'
    user = PREFIX + '_' + comp
    res = name  # offline layout: /JDBCSystemResources/<n>/JdbcResource/<n>/JDBCDriverParams
    base = '/JDBCSystemResources/%s/JdbcResource/%s/JDBCDriverParams/NO_NAME_0' % (name, res)
    cd(base)
    set('Url', DB_URL)
    set('PasswordEncrypted', RCU_PW)
    cd(base + '/Properties/NO_NAME_0')
    try:
        cd('Property/user')
    except:
        cd(base + '/Properties/NO_NAME_0')
        create('user', 'Property')
        cd('Property/user')
    set('Value', user)
    print('JDBC %s -> %s' % (name, user))
cd('/')

setOption('ServerStartMode', 'dev')
writeDomain(DOMAIN)
closeTemplate()
print('Domain written: ' + DOMAIN)
