# syntax=docker/dockerfile:1
#
# Oracle Forms 14.1.2.0.0 on Oracle Linux 9 (server side: WebLogic domain with WLS_FORMS).
# Every step here was a manual fix in the first container; see docker/forms/README.md section 3.
#
# Build context : docker/forms/
# Named context : installers/   (scripts/forms_up.sh passes --build-context installers=<path>)
#
# Installers are bind-mounted during RUN, so the 2+ GB archives are not copied into any layer.

ARG OL_IMAGE=oraclelinux:9-slim
ARG JDK_TGZ=jdk-21.0.8_linux-x64_bin.tar.gz

FROM ${OL_IMAGE} AS base
ARG JDK_TGZ
# CodeReady Builder: binutils, gcc, glibc-devel, libaio-devel, motif(-devel), libstdc++-devel/-static, make.
#   Needed to relink frmweb and libfrmjapi (ins_forms.mk) and for the libgcc_s.a shim.
# EPEL (via oracle-epel-release-el9): xdotool, used by the FSAL helpers inside this container.
RUN set -e; \
    sed -i '/^\[ol9_codeready_builder\]/,/^\[/ s/^enabled=0/enabled=1/' /etc/yum.repos.d/oracle-linux-ol9.repo; \
    microdnf install -y oracle-epel-release-el9; \
    microdnf install -y \
      unzip tar which procps-ng hostname shadow-utils \
      libaio libnsl openssl sysstat glibc-langpack-en \
      xorg-x11-server-Xvfb ImageMagick xdotool \
      binutils gcc glibc-devel libaio-devel motif motif-devel \
      libstdc++-devel libstdc++-static make; \
    microdnf clean all
# Oracle JDK 21 (the Forms/FMW installers reject OpenJDK)
RUN --mount=type=bind,from=installers,target=/mnt/installers,readonly \
    set -e; test -f "/mnt/installers/${JDK_TGZ}" || { echo "missing installers/${JDK_TGZ}"; exit 1; }; \
    mkdir -p /u01/jdk && tar -xzf "/mnt/installers/${JDK_TGZ}" -C /u01/jdk --strip-components=1 \
    && /u01/jdk/bin/java -version
ENV JAVA_HOME=/u01/jdk \
    PATH=/u01/jdk/bin:$PATH \
    LANG=en_US.UTF-8 \
    MW_HOME=/u01/oracle/fmw \
    DOMAIN_HOME=/u01/oracle/user_projects/domains/ig_forms_domain
RUN groupadd -g 54321 oinstall \
    && useradd -u 54321 -g oinstall -m oracle \
    && mkdir -p /u01/oracle /u01/ig /u01/oracle/user_projects /opt/ig/bin \
    && chown -R oracle:oinstall /u01/oracle /u01/ig /opt/ig

FROM base AS forms
ARG INFRA_JAR=fmw_14.1.2.0.0_infrastructure.jar
ARG FORMS_BIN=fmw_14.1.2.0.0_fr_linux64.bin
COPY --chown=oracle:oinstall oraInst.loc /opt/ig/oraInst.loc
COPY --chown=oracle:oinstall rsp/ /opt/ig/rsp/
USER oracle
WORKDIR /opt/ig

# 1. Fusion Middleware Infrastructure (silent install, no configuration)
RUN --mount=type=bind,from=installers,target=/mnt/installers,readonly \
    test -f "/mnt/installers/${INFRA_JAR}" || { echo "missing installers/${INFRA_JAR}"; exit 1; } ; \
    java -jar "/mnt/installers/${INFRA_JAR}" -silent \
      -responseFile /opt/ig/rsp/infra.rsp -invPtrLoc /opt/ig/oraInst.loc \
    && rm -rf /tmp/OraInstall* /tmp/*.log

# 2. Forms and Reports (silent install into the Infrastructure home; the .bin is run in place
#    from the read-only mount, it self-extracts to /tmp)
RUN --mount=type=bind,from=installers,target=/mnt/installers,readonly \
    set -e; \
    test -f "/mnt/installers/${FORMS_BIN}" || { echo "missing installers/${FORMS_BIN}"; exit 1; } ; \
    "/mnt/installers/${FORMS_BIN}" -silent -responseFile /opt/ig/rsp/forms.rsp -invPtrLoc /opt/ig/oraInst.loc ; \
    rm -rf /tmp/OraInstall* /tmp/*.log

# 3. Build fixes for OL9 (were manual in the first container):
#    a. libgcc_s.a shim: the Oracle makefiles link -lgcc_s statically; OL9 ships only libgcc_eh.a.
#    b. relink frmweb and libfrmjapi.so with ins_forms.mk (the shipped binaries fail at run time here).
RUN set -e; \
    ORACLE_HOME=/u01/oracle/fmw; \
    ln -sfn "$(gcc -print-file-name=libgcc_eh.a)" "$ORACLE_HOME/lib/libgcc_s.a"; \
    cd "$ORACLE_HOME/forms/lib"; \
    make -f ins_forms.mk frmweb_install ORACLE_HOME="$ORACLE_HOME"; \
    make -f ins_forms.mk libso_relink_install ORACLE_HOME="$ORACLE_HOME"; \
    # the web runtime looks for fmrweb.res under admin/resource; the installer only ships templates/resource
    mkdir -p "$ORACLE_HOME/forms/admin/resource/US"; \
    cp -n "$ORACLE_HOME/forms/templates/resource/US/fmrweb.res" "$ORACLE_HOME/forms/templates/resource/US/fmrweb_utf8.res" "$ORACLE_HOME/forms/admin/resource/US/"; \
    p="$(find "$ORACLE_HOME" -type f -name frmcmp_batch 2>/dev/null | head -1)"; \
    [ -n "$p" ] || { echo "ERROR: frmcmp_batch not found under $ORACLE_HOME"; exit 1; }; \
    mkdir -p /opt/ig/bin; ln -sfn "$p" /opt/ig/bin/frmcmp_batch; echo "frmcmp_batch -> $p"

COPY --chown=oracle:oinstall scripts/ /opt/ig/
RUN chmod 755 /opt/ig/*.sh \
    && ln -sfn /opt/ig/frmxml2f.sh /opt/ig/bin/frmxml2f
ENV PATH=/opt/ig/bin:/u01/oracle/fmw/oracle_common/common/bin:$PATH
EXPOSE 7001 9001
CMD ["tail", "-f", "/dev/null"]
