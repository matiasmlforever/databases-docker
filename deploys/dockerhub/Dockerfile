# PostgreSQL 11 Production Image with Embedded Configuration
FROM postgres:11-bullseye

# Build arguments (will be set during docker build)
ARG POSTGRES_USER=postgres
ARG POSTGRES_PASSWORD=defaultpass
ARG POSTGRES_DB=postgres
ARG APP_USER=app_user
ARG APP_PASSWORD=defaultapppass
ARG APP_DATABASE=app_db
ARG BUILD_DATE
ARG VERSION=1.0.0

# Set environment variables
ENV POSTGRES_USER=${POSTGRES_USER}
ENV POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
ENV POSTGRES_DB=${POSTGRES_DB}
ENV APP_USER=${APP_USER}
ENV APP_PASSWORD=${APP_PASSWORD}
ENV APP_DATABASE=${APP_DATABASE}
ENV POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256 --auth-local=scram-sha-256"

# Metadata labels
LABEL maintainer="matias.lecaros@learsoftware.cl"
LABEL description="PostgreSQL 11 production image with embedded security configuration"
LABEL version="${VERSION}"
LABEL build-date="${BUILD_DATE}"
LABEL postgres.version="11"
LABEL postgres.user="${POSTGRES_USER}"
LABEL postgres.database="${POSTGRES_DB}"

# Create directories for scripts and configuration
RUN mkdir -p /opt/scripts /opt/conf

# Copy configuration files to the image
COPY conf/postgres11.conf /opt/conf/postgresql.conf
COPY conf/pg_hba.conf /opt/conf/pg_hba.conf

# Copy and set up scripts
COPY scripts/init-db.sh /docker-entrypoint-initdb.d/01-init-db.sh
COPY scripts/health-check.sh /opt/scripts/health-check.sh
COPY scripts/backup.sh /opt/scripts/backup.sh

# Set proper permissions for all scripts
RUN chmod +x /docker-entrypoint-initdb.d/01-init-db.sh \
    && chmod +x /opt/scripts/health-check.sh \
    && chmod +x /opt/scripts/backup.sh \
    && chown -R postgres:postgres /opt/scripts \
    && chown -R postgres:postgres /opt/conf

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /opt/scripts/health-check.sh

# Expose PostgreSQL port
EXPOSE 5432

# Use the embedded configuration files
CMD ["postgres", "-c", "config_file=/opt/conf/postgresql.conf", "-c", "hba_file=/opt/conf/pg_hba.conf"]