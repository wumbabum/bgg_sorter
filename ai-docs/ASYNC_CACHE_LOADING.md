# Async Cache Loading Implementation

## Overview

Implemented asynchronous cache loading using Elixir's `Task` to isolate BggCacher operations from the main LiveView process. This prevents OOM crashes from affecting the entire application and provides better fault tolerance.

## Implementation

### Core.BggCacheLoader Module

**Location**: `apps/core/lib/core/bgg_cache_loader.ex`

**Key Features**:
- Wraps `Core.BggCacher.load_things_cache/4` in isolated Task processes
- 10-minute timeout for large collection loads
- Comprehensive error handling with logging
- Sends async messages back to caller:
  - `{:cache_loaded, task_pid, items}` on success
  - `{:cache_error, task_pid, reason}` on failure

**API**:
```elixir
# Start async load
task = Core.BggCacheLoader.async_load_things_cache(things, filters, sort_field, sort_direction)

# Or await synchronously if needed
{:ok, items} = Core.BggCacheLoader.await_cache_load(task, timeout)
```

### CollectionLive Integration

**Location**: `apps/web/lib/web/live/collection_live.ex`

**Changes**:
1. All `Core.BggCacher.load_things_cache/4` calls now use async loader
2. New message handlers for cache responses:
   - `handle_info({:cache_loaded, ...})` - handles successful cache loads
   - `handle_info({:cache_error, ...})` - handles cache failures
3. State tracking with assigns:
   - `:pending_modal_thing_id` - identifies modal loads
   - `:pending_refilter` - identifies re-filter/sort operations

**Flow**:
```
User Action → LiveView sends message → BggCacheLoader.async_load_things_cache()
                                              ↓
                                         Task spawns
                                              ↓
                                    BggCacher.load_things_cache()
                                              ↓
LiveView receives {:cache_loaded, ...} ← Task sends result
         ↓
    Update UI
```

## OOM Prevention Improvements

### 1. Task Isolation ✅

**Problem**: Cache loading failures or OOM in main process crashes entire LiveView.

**Solution**: Tasks run in isolated processes. If Task OOMs or crashes:
- LiveView receives `{:DOWN, ...}` message (handled automatically by Task)
- User sees error message
- Other users unaffected

### 2. Fixed List Concatenation ✅

**Problem**: `BggCacher.update_stale_things/1` used `acc ++ chunk_things` in reduce loop, causing O(n²) memory allocations.

**Solution**: Changed to `Enum.flat_map` which builds list efficiently:

```elixir
# Before (O(n²)):
Enum.reduce([], fn chunk, acc -> acc ++ chunk_things end)

# After (O(n)):
Enum.flat_map(fn chunk -> chunk_things end)
```

**Impact**: For 3000-game collection with 150 chunks:
- Before: ~22,500 list copy operations
- After: ~1 final list construction

### 3. Remaining OOM Risks

**Still Need Addressing**:

1. **Duplicate Collection Storage** (Priority: HIGH)
   - `:original_collection_items` - full unfiltered dataset
   - `:all_collection_items` - full filtered dataset
   - For 3000 games: ~12MB per user session
   - **Recommendation**: Only store original, compute filtered on-demand

2. **Mechanics Preloading** (Priority: MEDIUM)
   - Each Thing preloads full Mechanic structs
   - 3000 games × 4 mechanics = 12,000 additional records
   - **Recommendation**: Lazy load mechanics or use IDs only

3. **No Pagination at Database Level** (Priority: LOW)
   - All data loaded into memory, paginated client-side
   - **Recommendation**: Add `limit`/`offset` support in BggCacher

## Memory Estimates (3000-game collection)

### Before Changes:
- LiveView process: ~12MB per user
- BGG cache loading: 22,500 list copies (O(n²))
- **Concurrent users before OOM (512MB VM)**: ~30 users

### After Changes:
- LiveView process: ~12MB per user (unchanged)
- BGG cache loading: Single list construction (O(n))
- Task isolation: Failures don't crash LiveView
- **Concurrent users before OOM (512MB VM)**: ~30 users (memory unchanged, but more resilient)

## Testing

### New Tests

**File**: `apps/core/test/core/bgg_cache_loader_test.exs`

- ✅ Async cache loading sends correct messages
- ✅ Error handling and logging
- ✅ Timeout configuration (10 minutes)
- ✅ Await functionality

### Existing Tests

- ✅ All Web.CollectionLive tests pass
- ✅ Core.BggCacher tests pass (1 pre-existing schema version failure)
- ✅ Core.BggGateway tests maintained

## Deployment Recommendations

### 1. Monitor Task Processes

Add telemetry for Task lifecycle:
```elixir
[:bgg_sorter, :cache_loader, :start]
[:bgg_sorter, :cache_loader, :stop]
[:bgg_sorter, :cache_loader, :exception]
```

### 2. Consider Increasing Memory

If user concurrency grows:
- Current: 512MB Fly.io VM
- Recommended: 1GB for >50 concurrent users

### 3. Future Optimizations

1. **Database-level pagination**:
   ```elixir
   from(t in Thing, limit: ^per_page, offset: ^offset)
   ```

2. **Remove duplicate collections**:
   - Store only `:original_collection_items`
   - Compute filtered/sorted on-demand

3. **Lazy mechanics loading**:
   - Don't preload mechanics by default
   - Load on modal open only

## Logging

All cache operations now log:
- ✅ Task start with metadata (thing count, filters, sort)
- ✅ Success with loaded item count
- ✅ Failures with full error details and stacktraces
- ✅ Crashes captured in isolated process

Example logs:
```
[info] Starting async cache load for 500 things
[info] Successfully loaded 482 cached items

[error] Cache loading crashed: %RuntimeError{message: "OOM"}
** (RuntimeError) OOM
    (core 0.1.0) lib/core/bgg_cacher.ex:150
```

## Configuration

**Timeout**: Set in `Core.BggCacheLoader`
```elixir
@cache_timeout_ms :timer.minutes(10)  # 600,000ms
```

**Rate Limiting**: Set in `Core.BggCacher`
```elixir
@rate_limit_delay_ms 1000  # 1 second between BGG API chunks
```

## Related Files

- `apps/core/lib/core/bgg_cache_loader.ex` - Async wrapper
- `apps/core/lib/core/bgg_cacher.ex` - Cache logic (fixed list concat)
- `apps/web/lib/web/live/collection_live.ex` - LiveView integration
- `apps/core/test/core/bgg_cache_loader_test.exs` - Tests
