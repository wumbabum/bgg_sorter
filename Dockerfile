# syntax=docker/dockerfile:1.6
#
# Multi-stage Dockerfile for BggSorter Phoenix Umbrella Application.
# Optimized for minimal production image size AND fast iterative
# deploys via BuildKit cache mounts. The `# syntax=` directive above
# enables `RUN --mount=type=cache,...`, which keeps apt/hex/mix state
# warm on Fly's Depot builder between deploys without baking that
# state into the shipped image.

# Build stage
FROM elixir:1.15.6 AS build

# Install build dependencies. Cache /var/cache/apt and /var/lib/apt/lists
# so subsequent builds skip the package download + index refresh. The
# cache lives on the builder, not in the image, so no rm -rf is needed.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      ca-certificates

# Prepare build dir
WORKDIR /app

# Install hex + rebar. Cache the hex registry and mix archives so
# repeated builds don't re-download these.
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies. Hex's package cache lives in /root/.hex.
COPY mix.exs mix.lock ./
COPY config config
COPY apps/core/mix.exs apps/core/
COPY apps/web/mix.exs apps/web/
COPY apps/dispatch/mix.exs apps/dispatch/
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only=prod

# Compile dependencies. This is the largest single time sink in a cold
# build (~50s). The compiled artifacts land in /app/deps/<dep>/_build,
# which is part of the image layer; the cache mount only speeds up
# repeat work (e.g. when only one dep changes and rebar/hex registry
# stays warm).
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.compile

# Copy application source
COPY apps apps

# Install asset compilation tools (esbuild, tailwind). These download
# pre-built binaries on first run.
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix assets.setup

# Compile assets and application
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Build the release (only bgg_sorter release exists)
RUN MIX_ENV=prod mix release

# Clean up any leftover non-cached hex/mix state from the image layer.
# The cache mounts above were detached before this RUN, so this only
# removes the in-image directories (if any), not the cached registries.
RUN rm -rf ~/.hex ~/.mix

# Runtime stage - use same Debian base as Elixir image for library compatibility
FROM debian:bullseye-slim AS app

# Install runtime dependencies for Debian, with the same apt cache trick.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
      openssl \
      ca-certificates \
      libssl1.1 \
      libsctp1 \
      netcat-openbsd

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
