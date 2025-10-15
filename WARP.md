# BggSorter - Warp Agent Instructions

This document contains project-specific rules and design patterns for the BggSorter application. It should be read by Warp agents before working on this codebase.

## General Preferences

- Make summaries short, 15 lines at most, preferably shorter
- Prefer 'case' and 'with' control structures with `{:ok, data}` or `{:error, reason}` return values
- Prefer short documentation comments, no examples

## Project Overview

BggSorter is an Elixir Phoenix umbrella application that interfaces with the BoardGameGeek API to view, filter, and sort a user's board game collection.

**Components:**
- **Core**: API client, business logic, and database-backed caching system for BGG integration
- **Web**: Phoenix LiveView interface with advanced search, filtering, sorting, and pagination

## Current Architecture ✅ PRODUCTION READY

### Core Systems
- **BggGateway**: BGG API client with collection/things endpoints (see `apps/core/lib/core/bgg_gateway.ex`)
- **Thing Schema**: Ecto schema with database persistence (see `apps/core/lib/core/schemas/thing.ex`)
- **BggCacher**: Database-backed caching system with 1-week TTL and rate limiting (see `apps/core/lib/core/bgg_cacher.ex`)
- **Database**: PostgreSQL with specialized indexes for filtering and sorting performance

### Web Interface
- **Collection Display**: BGG-styled table with pagination (20 items/page)
- **Advanced Search**: 7 filters (name, players, time, rating, rank, weight, description)
- **Column Sorting**: 4 sortable columns (Name, Players, Rating, Weight) with visual indicators
- **Modal System**: Detailed game information with async loading
- **URL State Management**: All filters, sorts, and pagination preserved in URLs

### Data Flow Architecture

**Database-First Design:**
- All filtering and sorting performed in PostgreSQL with specialized indexes
- Complete game data cached locally with intelligent freshness detection (1-week TTL)
- BGG API rate-limited to 1 req/second with 20-item chunking
- Hybrid server/client filtering: BGG API pre-filtering + client-side complex filters

**Key API Functions:**
```elixir
# Main caching entry point
Core.BggCacher.load_things_cache(things, filters, sort_field, sort_direction)

# BGG API endpoints
Core.BggGateway.collection(username, params)  # User collections
Core.BggGateway.things(ids, opts)            # Detailed game data
```

### Current Implementation Details ✅ PRODUCTION READY

**Filtering Architecture:**
- **Server-Side**: BGG API native filters (rating-based) applied first
- **Client-Side**: Complex filters applied after caching (players, name search, time, weight, description)
- **Database-Level**: All filters converted to SQL WHERE clauses with proper type casting
- **Performance**: 70-90% faster than previous client-side-only approach

**Sorting Implementation:**
- **4 Sortable Columns**: Name, Players, Rating, Weight with bidirectional support
- **Visual Indicators**: Triangle indicators show current sort direction with hover effects
- **Database Optimized**: All sorting performed in PostgreSQL with specialized indexes
- **URL State**: Sort parameters preserved in bookmarkable URLs

**Caching System:**
- **Database-Backed**: Thing schema with `last_cached` field for freshness detection
- **Intelligent Updates**: Checksum-based optimization to skip unnecessary updates
- **Performance**: Sub-millisecond lookups for cached data, efficient batch processing for stale items
- **Error Resilience**: Graceful handling of BGG API failures with comprehensive logging

**Key Performance Characteristics:**
- **Cache Hit Rate**: Sub-millisecond database lookups
- **Memory Efficiency**: Streams large datasets without loading everything into memory
- **Predictable Pagination**: Consistent page sizes (20 items/page) with complete data filtering
- **API Efficiency**: Minimizes BGG API calls through intelligent caching
- **Benchmark Results**: 70-90% performance improvements, 60% memory reduction vs client-side processing

**Database Optimization:**
- **9 Specialized Indexes**: Covering all sort directions and filter+sort combinations
- **Query Patterns**: Pre-calculated expressions (LOWER, CAST) matching actual queries
- **Composite Indexes**: Rating+name, players+rating combinations for complex operations

**Filter System Details:**
- **7 Advanced Filters**: Name search, players, time, rating, rank, weight, description
- **Smart Defaults**: Weight filters auto-default (min→0, max→5) when only one value provided
- **Simplified UX**: Playing time uses single input with range inclusion logic

## Development Environment

### Docker Configuration ✅ COMPLETED
- Multi-stage Dockerfile with official Elixir 1.15.6 base image
- Zero configuration: `docker compose up` works out-of-the-box
- Production ready with minimal runtime image
- Asset compilation resolved (tailwind/esbuild compatibility)
- Database migration helpers and health checks included

### Testing
```bash
mix all_tests     # Comprehensive testing with credo and dialyzer
mix test          # Standard execution (preferred)
```

**Testing Preferences:**
- Use `mix test` for standard execution
- Run once, analyze, fix, repeat
- 84+ tests across core and web applications

**Current Test Coverage:**
- **Core Tests**: Complete coverage of BggGateway, BggCacher, Thing schema with database integration
- **Web Tests**: LiveView integration, sorting, filtering, pagination with state management
- **Integration Tests**: End-to-end cache workflows, BGG API integration, error resilience
- **Performance**: Test suite completes in ~4.6 seconds with no regressions

### Deployment Status

**Production Readiness:**
- **Zero Breaking Changes**: Fully backward compatible architecture
- **Performance Optimized**: Database-level operations with comprehensive indexing
- **Mobile Friendly**: Responsive design works on all screen sizes
- **BGG Visual Compliance**: Matches BoardGameGeek design patterns
- **SEO Friendly**: All state preserved in bookmarkable URLs
- **Error Resilience**: Graceful handling of BGG API failures and partial cache updates

## Warp Agent Guidelines

### When Working on BggSorter
1. **Architecture**: Understand database-first design with caching system
2. **Patterns**: Use existing BggGateway and BggCacher patterns
3. **Database Operations**: Prefer database-level filtering/sorting over client-side processing
4. **Testing**: Create comprehensive tests with real BGG API response data

### Code Quality Standards
- All public functions must have corresponding tests
- Use explicit `{:ok, result}` / `{:error, reason}` patterns
- Keep @doc comments concise (one line descriptions)
- Follow Elixir community conventions and umbrella app structure
- Database operations should leverage indexes and proper SQL patterns

### Performance Considerations
- **Caching First**: Use BggCacher for all BGG data access
- **Database Optimization**: Filter and sort in PostgreSQL when possible
- **Rate Limiting**: Respect BGG API limits (1 req/sec, 20 items/chunk)
- **Memory Efficiency**: Stream large datasets, avoid loading everything into memory

### Server and MCP Guidelines
- **Phoenix Server**: Use MCP `get_logs` tool to check server logs instead of running `mix phx.server` directly
- **MCP Server**: If MCP tools are unavailable or server/MCP server is not running, ask the user to start them
- **Testing**: Prefer using MCP tools for database queries and code evaluation over shell commands when available

## BGG Mechanics Integration ✅ COMPLETED

### Overview

The BGG XML API2 contains comprehensive mechanics data that can be integrated into BggSorter using a proper relational database design. The current array-based implementation needs to be replaced with dedicated tables and efficient join operations.

### Full Migration Plan

**See [MECHANICS_MIGRATION.md](./ai-docs/MECHANICS_MIGRATION.md) for the complete 8-phase implementation plan**, including:

- **Phase 0**: Rollback current implementation
- **Phases 1-2**: Create Mechanic and ThingMechanic schemas with proper indexing
- **Phases 3-4**: Update Thing associations and BGG XML parsing
- **Phases 5-6**: Implement efficient upserts and join-based filtering
- **Phases 7-8**: Add preloading throughout application and comprehensive testing

## AI Documentation

Warp agents can reference these specialized documents in the `ai-docs/` directory:

- `BGG_SORTING.md` - Sorting and filtering performance issues and fixes
- `BGG_STYLING_UPDATES.md` - Visual styling improvements and BGG design compliance
- `FLY_DEPLOYMENT.md` - Fly.io deployment configuration and procedures
- `MECHANICS_MIGRATION.md` - Complete 8-phase mechanics integration implementation
- `MECHANICS_UI.md` - Comprehensive mechanics UI system implementation
- `WARP_ORIGINAL.md` - Historical Warp agent instructions and project evolution
