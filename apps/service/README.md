# Service App

A lightweight service application that only depends on the `core` module. It provides mix tasks and utility functions for data analysis without requiring the full web application stack.

## Overview

The service app is designed to run standalone data processing tasks that leverage the BoardGameGeek API integration from the `core` module. It's optimized for batch processing and analysis workflows that don't need the Phoenix web framework.

## Architecture

- **Dependencies**: Only depends on `core` app
- **No Web Stack**: Excludes Phoenix, LiveView, and web-related dependencies
- **Standalone**: Can run independently of the main web application
- **Rate Limited**: Implements respectful API usage patterns

## Mix Tasks

### `analyze_mechanics`

**Purpose**: Analyzes game mechanics frequency across BoardGameGeek's top-ranked games to identify the most common mechanics used in highly-rated board games.

#### Usage
```bash
mix cmd --app service mix analyze_mechanics
```

#### What It Does

**Step 1: Data Input**
- Reads game rankings from `boardgames_ranks.csv` in the umbrella root directory
- Extracts the top 1000 game IDs from the CSV file
- Validates and filters valid game IDs

**Step 2: API Data Retrieval**
- Makes chunked HTTP requests to BoardGameGeek's XML API2 `/thing` endpoint
- Processes games in batches of 20 (BGG API limit) for maximum efficiency
- Uses `Core.BggGateway.things/2` with `stats=1` parameter for complete data
- Implements 4-second delays between chunks to respect BGG API rate limits
- Continues processing even if individual chunks fail (robust error handling)

**Step 3: Mechanics Extraction**
- Parses XML responses from BGG API using SweetXML
- Extracts mechanics data from `<link type="boardgamemechanic" value="Mechanic Name" />` elements
- Handles games with no mechanics data gracefully
- Stores mechanics as arrays of strings for each game

**Step 4: Data Analysis**
- Flattens all mechanics from all games into a single list
- Counts frequency of each unique mechanic across the dataset
- Calculates percentage representation for each mechanic
- Ranks mechanics by frequency (most common first)
- Selects top 100 mechanics for output

**Step 5: Output Generation**
- Creates `mechanics_count.csv` in the umbrella root directory
- Formats data with proper CSV escaping for commas and quotes in mechanic names
- Logs top 10 mechanics to console for immediate feedback

#### Technical Specifications

**Rate Limiting & Chunking**
- Processes games in chunks of 20 (BGG API limit)
- 4-second delay between chunk requests (not individual games)
- Total processing time: ~3-4 minutes for 1000 games (50 chunks)
- Prevents API abuse and respects BGG's service limits

**Progress Monitoring**
- Logs progress for each chunk processed (every 20 games)
- Shows chunk number and game range being processed
- Provides estimated completion time based on chunks remaining

**Error Handling**
- Continues processing if individual chunks fail to load
- Logs warnings for failed chunk requests without stopping execution
- Returns empty mechanics array for games with no data
- Graceful degradation ensures partial results even with API issues

**Memory Efficiency**
- Streams CSV data instead of loading entire file into memory
- Processes games in chunks of 20 to balance efficiency and memory usage
- Uses Elixir's efficient data structures for frequency counting

#### Input Requirements

**CSV File Format** (`boardgames_ranks.csv`):
```csv
id,name,yearpublished,rank,bayesaverage,average,usersrated,is_expansion,...
224517,"Brass: Birmingham",2018,1,8.40009,8.57316,54412,0,...
161936,"Pandemic Legacy: Season 1",2015,2,8.35603,8.50961,56336,0,...
```

- Must be located in umbrella root directory
- First column must contain BGG game IDs
- Header row is automatically skipped
- Task processes first 1000 data rows after header

#### Output Format

**CSV Output** (`mechanics_count.csv`):
```csv
mechanic,count,percentage
Hand Management,850,85.0
Variable Player Powers,800,80.0
Set Collection,750,75.0
...
```

**Fields**:
- `mechanic`: Name of the game mechanic (properly CSV-escaped)
- `count`: Number of games in top 1000 that use this mechanic
- `percentage`: Percentage of analyzed games using this mechanic (rounded to 2 decimal places)

**Sorting**: Results sorted by count (descending), showing most common mechanics first

#### Example Output

Typical mechanics found in top board games:
1. **Hand Management** - Managing cards or resources in hand
2. **Variable Player Powers** - Each player has unique abilities
3. **Set Collection** - Collecting sets of items for points
4. **Tile Placement** - Placing tiles to build areas or patterns
5. **Worker Placement** - Placing workers to take actions
6. **Deck Building** - Constructing your deck during play
7. **Area Control** - Controlling regions for benefits
8. **Engine Building** - Building combinations that generate resources
9. **Drafting** - Selecting from a shared pool of options
10. **Resource Management** - Managing limited resources efficiently

#### Use Cases

**Game Design Analysis**
- Identify trending mechanics in successful games
- Understand mechanic frequency in top-rated games
- Research mechanic combinations and patterns

**Market Research**
- Analyze popular game mechanics for business insights
- Track mechanic evolution over time
- Identify underutilized mechanics with potential

**Academic Research**
- Study game design trends and patterns
- Analyze correlation between mechanics and ratings
- Research game complexity and mechanic relationships

**Personal Interest**
- Discover new mechanics to explore
- Understand what makes games highly rated
- Find games with preferred mechanic combinations

#### Troubleshooting

**Common Issues**:
- **"Could not find boardgames_ranks.csv"**: Ensure CSV file is in umbrella root directory
- **Network timeouts**: BGG API may be slow; process will retry automatically
- **Partial results**: Some games may fail to load; task continues with available data
- **Memory usage**: Large datasets processed efficiently with streaming

**Monitoring Progress**:
```bash
# Run in background and monitor logs
nohup mix cmd --app service mix analyze_mechanics > mechanics_analysis.log 2>&1 &

# Monitor progress
tail -f mechanics_analysis.log

# Check if still running
ps aux | grep analyze_mechanics
```

## Dependencies

**Internal**:
- `core` app - Provides `Core.BggGateway` for API integration
- BGG API integration with rate limiting and XML parsing
- Ecto schemas for data validation

**External Libraries** (inherited from core):
- `req` - HTTP client for API requests
- `sweet_xml` - XML parsing for BGG API responses
- Standard Elixir libraries for data processing

## Development

**Adding New Tasks**:
1. Create new file in `lib/mix/tasks/`
2. Follow existing patterns for rate limiting and error handling
3. Use `Core.BggGateway` for BGG API integration
4. Document comprehensively in this README

**Testing Tasks**:
```bash
# Test with smaller dataset first
# Modify Stream.take(1000) to Stream.take(5) in task file
mix cmd --app service mix analyze_mechanics

# Verify output format and data quality
head -10 mechanics_count.csv
```

