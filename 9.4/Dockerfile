FROM ubuntu:trusty
MAINTAINER romeOz <serggalka@gmail.com>

ENV PG_LOCALE="en_US.UTF-8" \
	PG_VERSION=9.4 \
    PG_USER=postgres \
    PG_HOME=/var/lib/postgresql \
    PG_RUNDIR=/run/postgresql \
    PG_LOGDIR=/var/log/postgresql

ENV PG_CONFDIR="/etc/postgresql/${PG_VERSION}/main" \
    PG_BINDIR="/usr/lib/postgresql/${PG_VERSION}/bin" \
    PG_DATADIR="${PG_HOME}/${PG_VERSION}/main"

# Set the locale
RUN locale-gen ${PG_LOCALE}
ENV LANG ${PG_LOCALE}
ENV	LANGUAGE en_US:en
ENV	LC_ALL ${PG_LOCALE}

RUN apt-get install -y wget \
 && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
 && echo 'deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main' > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y postgresql-${PG_VERSION} postgresql-client-${PG_VERSION} postgresql-contrib-${PG_VERSION} lbzip2 \
 && rm -rf ${PG_HOME} \
 && rm -rf /var/lib/apt/lists/* \
 && touch /tmp/.EMPTY_DB

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 5432/tcp
VOLUME ["${PG_HOME}", "${PG_RUNDIR}"]
CMD ["/sbin/entrypoint.sh"]
