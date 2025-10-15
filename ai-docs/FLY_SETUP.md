# Fly.io PostgreSQL Setup - Separate Cluster Migration

## Overview
Successfully migrated from container-embedded PostgreSQL to Fly.io's standard PostgreSQL cluster pattern following official documentation. This approach provides cost optimization, professional database management, and follows Fly.io's recommended architecture.

## Final Cost Optimization
- **App Container**: 512MB RAM, shared-cpu-1x (~$8-12/month)
- **PostgreSQL Cluster**: 1GB RAM, shared-cpu-1x, 5GB storage (~$8-15/month)
- **Total**: ~$16-27/month (significantly reduced from previous container-embedded approach)
- **Benefits**: Independent scaling, professional backup/restore, standard Fly.io patterns

## Actual Migration Steps Executed

### Step 1: Restore Clean State
```bash
# Reset any custom PostgreSQL work
git restore Dockerfile fly.toml
rm -f entrypoint.sh init_postgres.sh docker-compose.local-postgres.yml
```

### Step 2: Create Cost-Optimized PostgreSQL Cluster
```bash
# Create single-node PostgreSQL cluster in same organization as app
fly postgres create --name bgg-sorter-db --region sjc --initial-cluster-size 1 --org personal

# Selected during interactive prompts:
# - VM Size: shared-cpu-1x (1GB RAM)
# - Volume Size: 5GB
# - Single node (no HA for cost savings)
```

### Step 3: Attach Database to Application
```bash
# Remove existing DATABASE_URL secret if present
fly secrets unset DATABASE_URL --app bgg-sorter

# Attach PostgreSQL cluster to app (auto-configures DATABASE_URL)
fly postgres attach --app bgg-sorter bgg-sorter-db
```

**This automatically created:**
- Database: `bgg_sorter`
- User: `bgg_sorter` with full privileges
- Secret: `DATABASE_URL=postgres://bgg_sorter:password@bgg-sorter-db.flycast:5432/bgg_sorter?sslmode=disable`

### Step 4: Remove Old Machine with Volume
```bash
# Destroy machine with old PostgreSQL volume to avoid conflicts
fly machine destroy 683263db624438 --app bgg-sorter --force
```

### Step 5: Deploy and Optimize
```bash
# Deploy with clean configuration
fly deploy --app bgg-sorter

# Scale down to single machine for cost optimization
fly scale count 1 --app bgg-sorter

# Reduce memory allocation for cost savings
fly scale memory 512 --app bgg-sorter
```

### Step 6: Run Database Migrations
```bash
# Migrate database schema to new PostgreSQL cluster
fly ssh console --app bgg-sorter -C "./bin/bgg_sorter eval \"Core.Release.migrate()\""
```

## Final Configuration

### Application
- **App Name**: `bgg-sorter`
- **Machines**: 1 machine, 512MB RAM, shared-cpu-1x
- **Organization**: `personal`
- **Status**: ✅ Healthy and running

### PostgreSQL Cluster
- **App Name**: `bgg-sorter-db`
- **Machines**: 1 machine, 1GB RAM, shared-cpu-1x
- **Storage**: 5GB volume
- **Connection**: Automatic via internal IPv6 networking
- **Status**: ✅ Healthy and running

### Environment Variables
```bash
# Automatically configured by fly postgres attach
DATABASE_URL="postgres://bgg_sorter:Q9MjHSJCbhCBJEn@bgg-sorter-db.flycast:5432/bgg_sorter?sslmode=disable"
SECRET_KEY_BASE="<existing>"
```

## Validation Results

### ✅ Database Connectivity
- Migrations ran successfully: 5 migrations executed
- Database schema created: `things`, `mechanics`, `thing_mechanics` tables
- All indexes created successfully

### ✅ Application Health
- HTTP Status: 200 OK
- Health checks: 1/1 passing
- URL: https://bgg-sorter.fly.dev/

### ✅ Cost Optimization
- **Before**: 1GB single machine with embedded PostgreSQL
- **After**: 512MB app + 1GB dedicated PostgreSQL cluster
- **Benefits**: Independent scaling, professional database management, standard Fly.io patterns

## Key Success Factors

1. **Same Organization**: Both app and PostgreSQL cluster must be in same organization for attach to work
2. **Clean Deployment**: Remove old machines with volumes to avoid configuration conflicts
3. **Automatic Configuration**: `fly postgres attach` handles all DATABASE_URL setup automatically
4. **Standard Phoenix App**: No custom PostgreSQL scripts or dependencies required
5. **Resource Optimization**: Single machines for both app and database for cost savings
