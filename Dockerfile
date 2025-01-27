# Define the Node.js version as a build argument
ARG node_version=22.12.0

# Stage 1: Install PostgreSQL dependencies
FROM node:${node_version}-slim AS pgdg
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gpg \
        lsb-release \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" \
      | tee /etc/apt/sources.list.d/pgdg.list \
    && curl https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor > /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg

# Stage 2: Intermediate stage for Git operations (if needed)
FROM node:${node_version}-slim AS intermediate
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
    && rm -rf /var/lib/apt/lists/*
COPY . .
RUN mkdir -p /tmp/sentry-versions
# Uncomment the following lines if you need Git tag information
# WORKDIR /server
# RUN git describe --tags --dirty > /tmp/sentry-versions/server
# WORKDIR /client
# RUN git describe --tags --dirty > /tmp/sentry-versions/client

# Stage 3: Final stage for the application
FROM node:${node_version}-slim

# Define build arguments and labels
ARG node_version
LABEL org.opencontainers.image.source="https://github.com/getodk/central"

# Set the working directory
WORKDIR /usr/odk

# Copy package.json and package-lock.json
COPY server/package*.json ./

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gpg \
    cron \
    wait-for-it \
    gettext \
    procps \
    netcat-traditional \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

RUN echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client-14 \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js dependencies
RUN npm ci --omit=dev --no-audit --fund=false --update-notifier=false

# Copy the rest of the application files
COPY server/ ./
COPY files/service/scripts/ ./

# Copy configuration templates and cron jobs
COPY files/service/config.json.template /usr/share/odk/
COPY files/service/crontab /etc/cron.d/odk
COPY files/service/odk-cmd /usr/bin/

# Copy sentry versions from the intermediate stage
COPY --from=intermediate /tmp/sentry-versions/ ./sentry-versions

# Expose the application port
EXPOSE 8383

# Default command (if needed)
CMD ["npm", "start"]
