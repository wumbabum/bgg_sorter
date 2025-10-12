# Fly.io Deployment Guide for BggSorter

## Prerequisites

1. Install the Fly.io CLI: `brew install flyctl`
2. Authenticate: `fly auth login`

## Required Secrets

Before deploying, you **must** set these secrets using `fly secrets set`:

### 1. SECRET_KEY_BASE (Required)
Generate a secure secret key:
```bash
# Generate the secret
SECRET_KEY_BASE=$(mix phx.gen.secret)

# Set it in Fly.io
fly secrets set SECRET_KEY_BASE="$SECRET_KEY_BASE"
```

### 2. DATABASE_URL (Automatic with Fly PostgreSQL)
This will be automatically set when you attach a PostgreSQL database:
```bash
# Create and attach PostgreSQL database
fly postgres create --name bgg-sorter-db
fly postgres attach --app bgg-sorter bgg-sorter-db
```

## Environment Variables Already Configured

The following environment variables are already configured in `fly.toml`:

- ✅ `PHX_HOST` = "bgg-sorter.fly.dev"
- ✅ `PORT` = "7384" 
- ✅ `MIX_ENV` = "prod"
- ✅ `PHX_SERVER` = "true"
- ✅ `POOL_SIZE` = "10"
- ✅ `ELIXIR_ERL_OPTIONS` = "+fnu" (UTF-8 support)
- ✅ `LANG` = "en_US.UTF-8" (locale support)
- ✅ `LC_ALL` = "en_US.UTF-8" (locale support)
- ✅ `ECTO_IPV6` = "true" (IPv6 database connections)

## Deployment Steps

1. **Create the Fly.io app** (if not already created):
   ```bash
   fly apps create bgg-sorter
   ```

2. **Create and attach PostgreSQL database**:
   ```bash
   fly postgres create --name bgg-sorter-db
   fly postgres attach --app bgg-sorter bgg-sorter-db
   ```

3. **Set required secrets**:
   ```bash
   fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
   ```

4. **Deploy the application**:
   ```bash
   fly deploy
   ```

5. **Check deployment status**:
   ```bash
   fly status
   fly logs
   ```

## Application Features

Once deployed, the application will have:

- ✅ **Database-backed caching system** for BGG API responses (1-week TTL)
- ✅ **Advanced search capabilities** with 9 filter types
- ✅ **Phoenix LiveView** real-time interface
- ✅ **BGG API integration** with rate limiting (1-second delays)
- ✅ **Responsive design** matching BoardGameGeek styling
- ✅ **Modal system** for detailed game information
- ✅ **Pagination** with URL state preservation

## URLs

After deployment, access your application at:
- **Main App**: https://bgg-sorter.fly.dev
- **Advanced Search**: https://bgg-sorter.fly.dev/collection?advanced_search=true

## Troubleshooting

- **Database connection issues**: Ensure `DATABASE_URL` is set by checking `fly secrets list`
- **Application won't start**: Check `fly logs` for detailed error messages
- **Health check failures**: The app uses the root path `/` for health checks
- **Performance issues**: The app is configured with 512MB RAM and 1 shared CPU

## Configuration Details

The application uses the following key configurations:

- **Database**: PostgreSQL with IPv6 support and connection pooling (10 connections)
- **Web Server**: Bandit HTTP server on port 7384
- **Static Assets**: Served from `/static/` with proper caching headers
- **Health Checks**: HTTP GET to `/` every 30 seconds with 10-second grace period
- **Auto Scaling**: Configured to auto-start/stop machines with minimum 0 running