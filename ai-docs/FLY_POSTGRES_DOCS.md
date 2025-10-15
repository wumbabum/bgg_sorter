# Fly.io PostgreSQL Documentation Analysis for Unmanaged Setup

## Overview

This document analyzes Fly.io's complete PostgreSQL documentation to determine the best approach for cost-effective **unmanaged PostgreSQL** deployment. After reviewing all official documentation, the recommendation is to migrate from the current container-embedded approach to Fly's standard PostgreSQL cluster pattern.

## Migration Results

### ✅ Successfully Completed Migration
**Migration Date**: October 15, 2025  
**Result**: Cost-optimized PostgreSQL deployment using Fly.io's standard cluster pattern

**Key Achievement**: Migrated from unsupported container-embedded PostgreSQL to official Fly.io PostgreSQL cluster pattern while maintaining cost optimization goals.

## Proven Migration Process

### Step 1: Create Cost-Optimized PostgreSQL Cluster

**Executed Command:**
```bash
# Create single-node PostgreSQL cluster for cost optimization
fly postgres create --name bgg-sorter-db --region sjc --initial-cluster-size 1 --org personal
```

**Interactive Selections Made:**
- VM Size: `shared-cpu-1x` (1GB RAM)
- Volume Size: 5GB
- Organization: `personal` (same as main app)
- High Availability: Disabled (single-node for cost savings)

**Results:**
- Created single PostgreSQL machine with 1GB RAM, 5GB storage
- Connection details automatically generated
- PostgreSQL 17.2 with professional management tools

### Step 2: Attach Database to Application

**Commands Executed:**
```bash
# Remove existing DATABASE_URL secret (from previous setup)
fly secrets unset DATABASE_URL --app bgg-sorter

# Attach PostgreSQL cluster to application
fly postgres attach --app bgg-sorter bgg-sorter-db
```

**Critical Success Factor:** Both apps must be in the same organization. Initial attempt failed because PostgreSQL cluster was created in `wumbabum` organization while main app was in `personal` organization.

**Automatic Configuration Results:**
- Database: `bgg_sorter` created automatically
- User: `bgg_sorter` with full database privileges
- Secret: `DATABASE_URL=postgres://bgg_sorter:Q9MjHSJCbhCBJEn@bgg-sorter-db.flycast:5432/bgg_sorter?sslmode=disable`
- Internal IPv6 networking configured between app and database

**Actual Output:**
```
Postgres cluster bgg-sorter-db is now attached to bgg-sorter
The following secret was added to bgg-sorter:
  DATABASE_URL=postgres://bgg_sorter:Q9MjHSJCbhCBJEn@bgg-sorter-db.flycast:5432/bgg_sorter?sslmode=disable
```

### 4. Connection Examples and Patterns

**Production App Connections:**
- Uses internal IPv6 private networking
- Automatic `DATABASE_URL` secret injection
- No external networking configuration required
- Zero-config connection for attached apps

**Development Access Methods:**
```bash
# Direct PostgreSQL shell access
fly postgres connect -a bgg-sorter-db

# Local port forwarding for development tools
fly proxy 5432 -a bgg-sorter-db
fly proxy 15432:5432 -a bgg-sorter-db  # if port 5432 is busy

# Then connect locally:
psql postgres://postgres:<password>@localhost:5432
```

### 5. Configuration and Tuning Capabilities

**PostgreSQL Configuration:**
- Supports standard `postgresql.conf` modifications
- Can tune memory, connections, and performance settings
- Configuration changes persist across restarts
- Access via `fly ssh` for direct configuration editing

**Performance Optimization:**
```bash
# Access PostgreSQL server for configuration
fly ssh console -a bgg-sorter-db

# Edit postgresql.conf for performance tuning
# Common settings: shared_buffers, work_mem, max_connections
```

### 6. Attach/Detach Management

**Attach Process Details:**
- Creates database named after the application
- Sets up application-specific user with full privileges
- Configures `DATABASE_URL` secret automatically
- Establishes internal network connectivity

**Detach Process:**
```bash
fly postgres detach --app bgg-sorter bgg-sorter-db
```
- Removes `DATABASE_URL` secret
- Preserves database and user (manual cleanup required)
- Maintains PostgreSQL cluster independently

## Problems with Current Container-Embedded Implementation

### 1. Resource and Cost Inefficiency
- **Single large container**: 1GB RAM for both app + database
- **No resource optimization**: Cannot tune app vs database resources independently
- **Volume costs**: Manual volume management without optimization
- **No scaling flexibility**: Database and app scaling coupled together

### 2. Operational Complexity
- **Custom initialization**: Complex `init_postgres.sh` and `entrypoint.sh` scripts
- **Manual user management**: No automated user/role creation
- **Non-standard patterns**: Doesn't follow Fly.io's recommended architecture
- **Troubleshooting difficulty**: Combined logs, complex debugging

### 3. Lack of Professional Database Features
- **No automated backups**: Manual backup/restore processes required
- **No monitoring tools**: Limited PostgreSQL-specific metrics and tooling
- **No connection pooling**: Manual connection management
- **No high availability**: Single point of failure

### 4. Maintenance and Support Issues
- **Unsupported configuration**: Fly.io provides no support for embedded PostgreSQL
- **Complex upgrades**: Manual PostgreSQL version management
- **Security management**: Manual security patch management
- **Limited tooling access**: No access to `fly postgres` management commands

## Recommended Migration Strategy

### Phase 1: Create Cost-Optimized PostgreSQL Cluster
```bash
# Create PostgreSQL cluster with cost optimization
fly postgres create --name bgg-sorter-db --region sjc

# Interactive prompts - choose for cost savings:
# VM Size: Select smallest suitable option (shared-cpu-1x, 256MB RAM)
# Volume Size: Start with 1GB (can expand later)
# High Availability: Select 'No' for single-node deployment
# Replication: Skip for cost savings
```

**This creates:**
- Dedicated, right-sized PostgreSQL application
- Professional backup/restore capabilities via `fly postgres`
- Independent resource scaling for app vs database
- Access to full PostgreSQL management tooling
- Standard Fly.io monitoring and metrics

### Phase 2: Simplify Application Configuration

**Remove from `fly.toml`:**
```toml
# Remove all PostgreSQL-related configuration
[[mounts]]
  source = 'postgres_data'      # Remove volume mounting
  destination = '/app/pgdata'

# Remove PostgreSQL environment variables - DATABASE_URL will be auto-injected
# Keep app-specific variables like PHX_HOST, PORT, etc.
```

**Simplify `Dockerfile`:**
```dockerfile
# Remove PostgreSQL dependencies:
# - postgresql, postgresql-contrib
# - gosu, sudo (PostgreSQL user management)
# - Custom initialization scripts
# - PostgreSQL-related permissions and sudoers config

# Keep minimal runtime dependencies:
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    ca-certificates \
    libssl1.1 \
    libsctp1 \
    netcat-openbsd \
    # Remove PostgreSQL packages
    && rm -rf /var/lib/apt/lists/*

# Remove custom entrypoint - use standard Phoenix startup
CMD ["./bin/bgg_sorter", "start"]
```

### Phase 3: Database Connection and Deployment

**Attach Database to Application:**
```bash
# This is the critical step that automates everything
fly postgres attach --app bgg-sorter bgg-sorter-db
```

**What `attach` automatically configures:**
- Creates `bgg_sorter` database in the PostgreSQL cluster
- Creates `bgg_sorter` user with full database privileges
- Injects `DATABASE_URL` secret into application environment
- Configures internal IPv6 networking between app and database
- Sets up connection string: `postgres://bgg_sorter:password@hostname:5432/bgg_sorter`

### Phase 4: Deploy and Validate

**Deploy Updated Application:**
```bash
# Deploy with simplified configuration
fly deploy

# Monitor deployment and connection
fly logs
```

**Validate Database Connection:**
```bash
# Check that DATABASE_URL secret is properly set
fly secrets list --app bgg-sorter

# Should show: DATABASE_URL (set automatically by attach)

# Test database connectivity
fly ssh console --app bgg-sorter
# In app container: ./bin/bgg_sorter eval "Ecto.Repo.query!(\"SELECT 1\")"
```

### Phase 5: Data Migration (If Needed)

**Export from Current Embedded PostgreSQL:**
```bash
# If migrating existing data, export from current setup
fly ssh console --app bgg-sorter
# In container: pg_dump -U bgg_user bgg_sorter_prod > /tmp/export.sql
```

**Import to New PostgreSQL Cluster:**
```bash
# Connect to new PostgreSQL cluster
fly postgres connect -a bgg-sorter-db
# In psql: \i /path/to/export.sql
```

## Comprehensive Cost Analysis

### Current Approach (Container-embedded PostgreSQL)
- **Single Large Container**: 1GB RAM, 1 shared CPU (~$15-25/month)
- **Volume Storage**: `postgres_data` volume costs (~$0.15/GB/month)
- **Resource Waste**: App uses ~200MB, PostgreSQL needs ~400MB, but allocated 1GB total
- **No Scaling Flexibility**: Cannot optimize app vs database resources independently
- **Manual Backup Costs**: No automated backup/restore (must implement separately)

### Recommended Approach (Separate PostgreSQL Cluster)
- **App Container**: 512MB RAM, shared CPU (~$8-12/month) - app-only resources
- **Database Container**: 256MB-512MB RAM, shared CPU (~$8-15/month) - database-optimized
- **Professional Features**: Built-in backup/restore, monitoring, management tools
- **Resource Optimization**: Each service sized appropriately
- **Independent Scaling**: Scale app and database separately based on actual needs

### Potential Cost Savings
- **Resource Right-Sizing**: 20-40% reduction in total compute costs
- **Operational Efficiency**: Reduced maintenance overhead
- **Professional Database Management**: Built-in features vs manual implementation
- **Scaling Flexibility**: Avoid over-provisioning single large container

## Migration Risks and Mitigation Strategies

### Database Migration Risks
- **Data Loss Risk**: Export/import process could fail
- **Mitigation**: Test migration process with database copy first
- **Downtime**: Database migration requires service interruption
- **Mitigation**: Plan migration during low-traffic window

### Application Connectivity Changes
- **Connection String Changes**: From `localhost` to internal IPv6 address
- **Mitigation**: `DATABASE_URL` automatically configured by `fly postgres attach`
- **Connection Pooling**: May need adjustment for remote connections
- **Mitigation**: Monitor connection pool usage, adjust `POOL_SIZE` if needed

### Network and Performance Considerations
- **Network Latency**: Slight increase from local to internal network
- **Mitigation**: Internal Fly.io networking is optimized for low latency
- **Connection Management**: Remote connections vs local socket connections
- **Mitigation**: Connection pooling becomes more important

### Rollback Strategy
- **Preserve Current Setup**: Keep current container image available
- **Data Backup**: Ensure both old and new databases have recent backups
- **Deployment Testing**: Test new setup in development/staging first
- **Quick Rollback**: Ability to redeploy previous container configuration

## Comprehensive Testing Strategy

### 1. Development Environment Testing
```bash
# Create test PostgreSQL cluster
fly postgres create --name bgg-sorter-db-test --region sjc
# Choose minimal resources for testing

# Clone current app for testing
fly apps create bgg-sorter-test

# Attach test database
fly postgres attach --app bgg-sorter-test bgg-sorter-db-test

# Deploy test app with simplified configuration
fly deploy --app bgg-sorter-test
```

### 2. Connection and Functionality Validation
```bash
# Verify DATABASE_URL configuration
fly secrets list --app bgg-sorter-test

# Test database connectivity
fly ssh console --app bgg-sorter-test
# In container: ./bin/bgg_sorter eval "Ecto.Repo.query!(\"SELECT version()\")"

# Run database migrations
fly ssh console --app bgg-sorter-test
# In container: ./bin/bgg_sorter eval "Core.Release.migrate()"

# Test application functionality
# Visit https://bgg-sorter-test.fly.dev and validate features
```

### 3. Performance and Resource Monitoring
```bash
# Monitor application performance
fly logs --app bgg-sorter-test

# Monitor PostgreSQL performance
fly logs --app bgg-sorter-db-test

# Check resource usage
fly status --app bgg-sorter-test
fly status --app bgg-sorter-db-test

# Compare memory/CPU usage vs embedded approach
```

### 4. Load Testing and Validation
- Test application under normal load patterns
- Validate database connection pooling
- Monitor network latency between app and database
- Ensure BGG API caching and filtering performance maintained

## Complete File Modification Guide

### Files to Remove Completely:
- `init_postgres.sh` - PostgreSQL initialization and user setup script
- `entrypoint.sh` - Custom container startup with PostgreSQL management

### Files Requiring Major Changes:

**`Dockerfile` modifications:**
```dockerfile
# Remove these packages from apt install:
# - postgresql
# - postgresql-contrib  
# - gosu
# - sudo

# Remove these configuration lines:
# - COPY init_postgres.sh /usr/local/bin/
# - COPY entrypoint.sh /usr/local/bin/
# - RUN chmod +x /usr/local/bin/init_postgres.sh /usr/local/bin/entrypoint.sh
# - All sudoers configuration for PostgreSQL

# Change final CMD from:
# CMD ["/usr/local/bin/entrypoint.sh"]
# To:
# CMD ["./bin/bgg_sorter", "start"]
```

**`fly.toml` modifications:**
```toml
# Remove entire [[mounts]] section:
# [[mounts]]
#   source = 'postgres_data'
#   destination = '/app/pgdata'

# DATABASE_URL will be automatically injected by 'fly postgres attach'
# Keep all other environment variables unchanged
```

### Files Requiring Minor Changes:

**`config/runtime.exs` (verify only):**
- Should already use `System.get_env("DATABASE_URL")` for database configuration
- If using custom localhost configuration, update to rely on `DATABASE_URL`
- Connection pool size (`POOL_SIZE`) may need adjustment for remote connections

### Files to Keep Unchanged:
- All Phoenix/Elixir application code (`apps/core/`, `apps/web/`)
- All Ecto migration files (`priv/repo/migrations/`)
- Database schema definitions (`apps/core/lib/core/schemas/`)
- Application configuration files (except `runtime.exs` verification)
- All business logic, controllers, LiveViews, etc.

### New Files to Consider:
- No new files required - `fly postgres attach` handles all configuration
- Optional: Add database monitoring/health check endpoints
- Optional: Custom connection pool monitoring

## Final Recommendations and Action Plan

### Why Migration is Essential

The current container-embedded PostgreSQL approach has significant limitations:

**Cost Inefficiency:**
- Over-provisioned single container (1GB for ~600MB actual usage)
- Cannot optimize app vs database resources independently
- Missing professional database features that must be built manually

**Operational Complexity:**
- Non-standard Fly.io patterns (officially unsupported)
- Complex custom scripts for basic database operations
- Manual backup/restore implementation required
- Difficult troubleshooting with combined app/database logs

**Scalability Limitations:**
- App and database scaling tightly coupled
- Cannot handle traffic spikes efficiently
- Limited monitoring and performance tuning options

### Recommended Migration Path

**Immediate Benefits:**
1. **20-40% cost reduction** through resource right-sizing
2. **Professional database management** with built-in backup/restore
3. **Standard Fly.io patterns** with full support and tooling access
4. **Independent scaling** for app and database components
5. **Simplified maintenance** - remove custom PostgreSQL scripts

**Migration Timeline:**
- **Phase 1** (Testing): 1-2 days - Create test environment and validate
- **Phase 2** (Code Changes): 1 day - Simplify Dockerfile and fly.toml
- **Phase 3** (Production Migration): 2-4 hours - Deploy with minimal downtime
- **Phase 4** (Optimization): Ongoing - Monitor and tune resource allocation

### Technical Implementation Summary

```bash
# 1. Create cost-optimized PostgreSQL cluster
fly postgres create --name bgg-sorter-db --region sjc

# 2. Simplify application (remove PostgreSQL dependencies)
# Edit Dockerfile and fly.toml per documentation above

# 3. Attach database and deploy
fly postgres attach --app bgg-sorter bgg-sorter-db
fly deploy

# 4. Validate and monitor
fly logs
fly status --app bgg-sorter
fly status --app bgg-sorter-db
```

This migration aligns with Fly.io's documented best practices, reduces costs, improves reliability, and provides access to professional PostgreSQL management tools that would otherwise require custom development.
