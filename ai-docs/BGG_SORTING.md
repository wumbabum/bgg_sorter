# BGG Sorting & Filtering Performance Issues and Fixes

## Overview

This document outlines critical performance issues discovered and resolved in the BggSorter application's sorting and filtering system. The issues involved unnecessary BGG API calls when cached data was already available, and database casting errors when filtering games with non-numeric values.

## Issues Identified

### 1. Advanced Search Always Triggering BGG API Reloads

**Problem:** When clicking "Search Collection" in advanced search for the same username, the application always made new BGG API requests instead of using data already in the LiveView state.

**Root Cause:** The `reapply_filters_to_collection/2` function in `collection_live.ex` always returned `{:reload_needed, socket}` regardless of whether cached data was available.

**Impact:** 
- Unnecessary network requests to BGG API
- Slower user experience (network latency vs. instant filtering)
- Defeats the purpose of the intelligent caching system

### 2. Column Sorting Always Triggering BGG API Reloads

**Problem:** Clicking column headers to sort (e.g., "Players", "Rating", "Weight") always triggered full collection reloads from BGG API.

**Root Cause:** The `handle_params/3` function's sort parameter change handler always called `{:load_collection_with_filters, username, filters}` without checking for cached data availability.

**Impact:**
- Every column sort required a full BGG API round-trip
- Sorting appeared slow and showed loading states unnecessarily
- Inconsistent with the database-optimized caching architecture

### 3. Database Casting Errors with Non-Numeric Values

**Problem:** When applying filters that would result in 0 results, PostgreSQL threw casting errors trying to convert non-numeric strings (like `"Not Ranked"`) to integers/floats.

**Root Cause:** Database filter queries used `CAST(? AS INTEGER)` and `CAST(? AS FLOAT)` without checking if the values were actually numeric first.

**Specific Error:**
```
invalid input syntax for type integer: "Not Ranked"
```

**Impact:**
- Application errors when users applied restrictive filters
- Poor user experience with database error messages
- Fallback to BGG API reload due to database filtering failure

## Solutions Implemented

### 1. Fixed Advanced Search Filtering

**File:** `apps/web/lib/web/live/collection_live.ex`

**Changes:** Modified `reapply_filters_to_collection/2` (lines 1052-1092) to:
- Check if `original_collection_items` is available in socket state
- Use `Core.BggCacher.load_things_cache/4` for database-level filtering when data exists
- Only fall back to BGG API reload when cached data is unavailable
- Apply database-level filtering with proper error handling

**Result:**
- Advanced search now uses cached data for instant filtering
- BGG API calls only occur when cache is empty
- Maintains database-optimized filtering performance

### 2. Fixed Column Sorting Performance

**File:** `apps/web/lib/web/live/collection_live.ex`

**Changes:** Modified sort parameter handling in `handle_params/3` (lines 256-309) to:
- Check for cached data availability before reloading
- Use `Core.BggCacher.load_things_cache/4` for database-level sorting
- Apply sorting with the same filters and mechanics currently active
- Only reload from BGG API when cached data is unavailable

**Result:**
- Column sorting now uses cached data with database-level operations
- No BGG API calls for sorting operations
- Instant visual feedback with proper loading states

### 3. Fixed Database Casting Errors

**File:** `apps/core/lib/core/bgg_cacher.ex`

**Changes:** Added regex validation before PostgreSQL casting operations:

**Integer Fields (rank, players, playtime):**
- Added `? ~ '^[0-9]+$'` checks before `CAST(? AS INTEGER)`
- Combined multiple fragment conditions into single queries

**Float Fields (average, averageweight):**
- Added `? ~ '^[0-9.]+$'` checks before `CAST(? AS FLOAT)`
- Handles decimal numbers properly

**Example:** Rank filter (lines 242-254):
```elixir
fragment(
  "? ~ '^[0-9]+$' AND CAST(? AS INTEGER) > 0 AND CAST(? AS INTEGER) <= ?",
  t.rank, t.rank, t.rank, ^max_rank
)
```

**Result:**
- No more database casting errors
- Games with non-numeric values (like "Not Ranked") are properly excluded
- Robust filtering that handles real-world BGG data inconsistencies

## Architecture Benefits

### Database-First Approach Maintained
- All filtering and sorting still performed at the PostgreSQL level
- Leverages existing specialized indexes for optimal performance
- Consistent with the established caching architecture

### Performance Optimizations
- **Cache Hit Strategy:** Always check cached data before API calls
- **Network Optimization:** Eliminate unnecessary BGG API requests
- **User Experience:** Instant feedback for sorting and filtering operations
- **Error Resilience:** Graceful fallbacks when database operations fail

### Consistent Patterns
- Both filtering and sorting now follow the same cached-data-first approach
- Uniform error handling with appropriate fallbacks
- Maintains the hybrid server/client filtering architecture

## Implementation Details

### Key Functions Modified

1. **`reapply_filters_to_collection/2`** - Now checks cached data availability
2. **Sort parameter handling in `handle_params/3`** - Uses cached data for sorting
3. **Database filter functions in `BggCacher`** - Added numeric validation

### Logging Improvements

**Before Fix:**
```
[info] Original collection not available for advanced search, reloading from API
[info] Loading collection with filters: %{...}
[info] BGG API params: [own: 1, stats: 1]
```

**After Fix:**
```
[info] Applying filters using database cache with 67 items
[info] Re-sorting 67 cached items with new sort: players asc
```

### Error Handling Strategy
- **Primary:** Use cached data with database operations
- **Secondary:** Fall back to BGG API reload on database errors
- **Tertiary:** Display appropriate error messages to users

## Future Considerations

### Monitoring
- Track cache hit rates for filtering and sorting operations
- Monitor BGG API call frequency to ensure fixes are effective
- Watch for any new database casting errors with different data patterns

### Potential Enhancements
- Consider client-side sorting for small collections as a performance optimization
- Implement more sophisticated caching invalidation strategies
- Add user preferences for sorting/filtering behavior

### Data Quality
- The regex patterns handle current BGG data patterns but may need updates if BGG changes their data format
- Consider data normalization during import to reduce filtering complexity

## Testing Recommendations

1. **Performance Testing:**
   - Verify sorting operations don't trigger BGG API calls
   - Test advanced search with various filter combinations
   - Measure response times for cached vs. fresh data operations

2. **Edge Case Testing:**
   - Games with "Not Ranked" values
   - Empty or null numeric fields
   - Extreme filter values that would result in 0 results
   - Large collections (100+ games) sorting performance

3. **Integration Testing:**
   - Verify mechanics filtering still works with updated architecture
   - Test URL state persistence across all operations
   - Confirm fallback behavior when cache is unavailable

## Conclusion

These fixes significantly improve the user experience by eliminating unnecessary network requests while maintaining the robust database-optimized filtering and sorting capabilities. The caching system now works as originally intended, providing instant feedback for user interactions while gracefully handling edge cases in BGG data.