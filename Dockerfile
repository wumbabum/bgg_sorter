# Multi-stage Dockerfile for BggSorter Phoenix Umbrella Application
# Optimized for minimal production image size

# Build stage
FROM elixir:1.15.6 AS build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
COPY apps/core/mix.exs apps/core/
COPY apps/web/mix.exs apps/web/
RUN mix deps.get --only=prod

# Compile dependencies
RUN mix deps.compile

# Copy application source
COPY apps apps

# Install asset compilation tools (esbuild, tailwind)
RUN mix assets.setup

# Compile assets and application
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Build the release
RUN MIX_ENV=prod mix release

# Clean up build artifacts
RUN rm -rf ~/.hex ~/.mix

# Runtime stage - use same Debian base as Elixir image for library compatibility
FROM debian:bullseye-slim AS app

# Install runtime dependencies for Debian
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    ca-certificates \
    libssl1.1 \
    libsctp1 \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN groupadd -g 1000 app && \
    useradd -u 1000 -g app -s /bin/bash -m app

# Prepare app directory
WORKDIR /app
RUN chown app:app /app

# Copy the release from build stage
COPY --from=build --chown=app:app /app/_build/prod/rel/bgg_sorter ./

USER app

# Set environment variables
ENV HOME=/app
ENV MIX_ENV=prod
ENV PHX_SERVER=true

# Expose port
EXPOSE 7384

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD nc -z localhost 7384 || exit 1

# Start the application
CMD ["./bin/bgg_sorter", "start"]
