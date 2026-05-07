# Performance and Scalability Issues

## Problem Statement

BggSorter is experiencing performance and memory issues that limit concurrent user capacity and create inefficiencies during data loading operations. These issues become critical as user concurrency increases.

## Current Architecture Constraints

### Memory Limitations
- **Fly.io VM**: 512MB RAM (recently scaled to 1GB)
- **Per-user memory footprint**: ~26MB for a 3000-game collection
- **Concurrent user capacity**: 10-15 users with large collections before OOM risk
- **Critical threshold**: Production OOM crashes observed with concurrent users

### Data Loading Behavior
- Full collections loaded into memory even when displaying only 20 items per page
- No database-level pagination - all filtering and sorting done in memory
- LiveView processes store complete datasets in state

## Identified Issues

### 1. Duplicate Collection Storage (CRITICAL)

**Problem**: Each LiveView session stores collection data twice in memory:
- `:original_collection_items` - Full unfiltered dataset
- `:all_collection_items` - Full filtered dataset

**Impact**:
- 3000-game collection = ~12MB × 2 = ~24MB per user
- Doubles memory consumption unnecessarily
- No architectural reason for maintaining both copies

**When it occurs**: Every collection load, every filter application

---

### 2. Lack of Database-Level Pagination (HIGH)

**Problem**: The database query loads all records into memory:
```elixir
Core.Repo.all()  # Loads entire collection
```
Then pagination happens client-side in LiveView.

**Impact**:
- Loads 3000 games when user only needs 20
- Memory waste: ~99% of loaded data unused on current page
- Query performance: No LIMIT/OFFSET optimization

**Why it exists**: Originally designed for client-side filtering flexibility

---

### 3. Mechanics Preloading (MEDIUM)

**Problem**: Every Thing record preloads full Mechanic associations:
```elixir
preload: [:mechanics]
```

**Impact**:
- 3000 games × 4 mechanics avg = 12,000 mechanic records in memory
- Each Mechanic struct ~50-100 bytes
- Additional ~1-2MB per user
- Mechanics duplicated in both original and filtered collections

**When it's needed**: Only for modal detail views, not list display

---

### 4. Orphaned Tasks on Page Reload (MEDIUM)

**Problem**: When users reload the page, async Tasks continue running:

1. User loads page → LiveView spawns Task for BGG API call
2. User reloads page → Old LiveView process dies, Task keeps running
3. Task completes → Sends messages to dead process (lost)
4. New LiveView spawns another Task for same data

**Impact**:
- Multiple concurrent Tasks for identical data
- Wasted BGG API calls (rate limited at 1/4 seconds)
- Wasted CPU and memory resources
- Tasks hold references to data until completion
- No cleanup or cancellation mechanism

**Frequency**: Every page reload, every navigation change

---

### 5. No Request Deduplication (MEDIUM)

**Problem**: Multiple users requesting the same collection triggers duplicate work:

**Scenario**:
- User A requests collection for "username123"
- User B requests collection for "username123" (2 seconds later)
- User C reloads page for "username123"

**Current behavior**: 3 separate BGG API calls, 3 separate database operations, 3 separate cache loading processes

**Impact**:
- BGG API rate limiting (1 request per 4 seconds)
- Database load from redundant queries
- Memory waste from duplicate processing
- Slower response times for subsequent users

---

### 6. No Result Caching Between Requests (LOW)

**Problem**: No in-memory cache of loaded collections between user sessions.

**Impact**:
- Popular collections loaded repeatedly
- Every user triggers fresh BGG API call
- Database queries repeated unnecessarily

**Example**: 10 users viewing "popular_user" triggers 10 identical BGG API calls within minutes

---

## Memory Estimates (3000-game collection)

### Current State (Per User):
```
Original collection:         ~12MB
Filtered collection:         ~12MB  
Mechanics (preloaded 2x):     ~2MB
LiveView overhead:            ~1MB
──────────────────────────────────
Total per user:              ~27MB
```

### Concurrent User Capacity:
```
1GB total RAM
- 300MB (Erlang VM, database, system)
──────────────────────────────────
700MB available for users
700MB / 27MB = ~26 concurrent users maximum
```

**With large collections (3000+ games): Only 10-15 users before OOM risk**

---

## Observed Symptoms

### Production Issues:
- ✗ OOM crashes with concurrent users
- ✗ Slow page loads for large collections (3000+ games)
- ✗ High memory usage per user session
- ✗ BGG API rate limit exhaustion

### Development Observations:
- ✗ Page reloads spawn orphaned Tasks (visible in logs)
- ✗ Progress tracking shows full collection processing even when mostly cached
- ✗ Same collection loaded multiple times by different users
- ✗ Memory usage grows linearly with concurrent users

---

## Performance Goals

### Memory Targets:
- **Reduce per-user memory**: From ~27MB to <5MB
- **Support concurrent users**: 100+ users on 1GB VM
- **Eliminate duplicate storage**: Single source of truth for collection data

### Loading Efficiency:
- **Database pagination**: Only load data needed for current page
- **Lazy loading**: Load mechanics only when needed (modal views)
- **Request deduplication**: Share load operations across concurrent requests

### API Efficiency:
- **Reduce BGG API calls**: Cache results between user sessions
- **Handle rate limits**: Respect 4-second delay without blocking multiple users
- **Avoid redundant calls**: Deduplicate concurrent requests

---

## Constraints and Requirements

### Must Maintain:
- ✓ Client-side filtering functionality (instant filter updates)
- ✓ Advanced search with multiple filter criteria
- ✓ Sorting capabilities (4 sortable columns)
- ✓ Pagination (20 items per page)
- ✓ Progress tracking for large collections (>60 games)
- ✓ Modal detail views with full mechanics data
- ✓ URL state management (bookmarkable URLs)

### Cannot Break:
- ✓ Existing user experience (speed, features)
- ✓ BGG API integration (collection, things endpoints)
- ✓ Database caching system (1-week TTL)
- ✓ Test suite (all existing tests must pass)

### Technical Boundaries:
- ✓ Elixir/Phoenix LiveView architecture
- ✓ PostgreSQL database with existing schema
- ✓ Fly.io deployment environment
- ✓ BGG API rate limits (1 request per 4 seconds, 20 items per chunk)

---

## Success Criteria

### Memory Usage:
- [ ] Per-user memory footprint reduced by at least 80%
- [ ] Support 100+ concurrent users on 1GB VM without OOM
- [ ] No duplicate collection storage in LiveView state

### Performance:
- [ ] Page loads complete in <2 seconds for cached collections
- [ ] Filter/sort operations remain instant (client-side when possible)
- [ ] BGG API calls minimized through intelligent caching

### Reliability:
- [ ] No orphaned Tasks on page reload
- [ ] No redundant API calls for concurrent requests
- [ ] Graceful handling of concurrent user load

### Monitoring:
- [ ] Clear visibility into cache hit rates
- [ ] Request deduplication metrics
- [ ] Memory usage per LiveView process

---

## Known Working Patterns

### Database-Level Operations:
- Filtering and sorting already implemented in `BggCacher`
- Complex SQL queries with proper indexing
- Efficient Ecto query composition

### Async Task Isolation:
- Tasks prevent OOM from crashing LiveView
- Progress tracking working for large collections
- Error handling and logging in place

### Caching Strategy:
- Database-backed cache with 1-week TTL
- Intelligent freshness detection
- Checksum-based mechanics updates

---

## Related Documentation

- `ASYNC_CACHE_LOADING.md` - Async Task implementation and OOM prevention
- `ASYNC_CACHE_PROGRESS.md` - Progress tracking architecture
- `BGG_SORTING.md` - Sorting and filtering performance
- `WARP.md` - Overall project architecture and design patterns
