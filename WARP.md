# BggSorter - Warp Agent Instructions

This document contains project-specific rules and design patterns for the BggSorter application. It should be read by Warp agents before working on this codebase.

## Project Overview

BggSorter is an Elixir Phoenix umbrella application that interfaces with the BoardGameGeek API to view, filter, and sort a user's board game collection. The application consists of two main components:

- **Core**: API client and business logic for BGG integration
- **Web**: Phoenix web interface for user interaction

## Architecture Patterns

### Umbrella Application Structure
```
bgg_sorter/
├── apps/
│   ├── core/           # BGG API client and business logic
│   │   ├── lib/
│   │   │   ├── core/
│   │   │   │   ├── bgg_gateway.ex          # Main BGG API interface
│   │   │   │   └── bgg_gateway/
│   │   │   │       └── req_client.ex       # HTTP client with Behaviour
│   │   │   └── core.ex
│   │   └── test/
│   │       ├── core/
│   │       │   ├── bgg_gateway_test.exs
│   │       │   └── bgg_gateway/
│   │       │       └── req_client_test.exs
│   │       └── support/
│   │           └── mocks.ex
│   └── web/            # Phoenix web interface
│       ├── lib/web/
│       └── test/
├── config/
└── deps/
```

### Design Principles

#### 1. Behaviour-Driven HTTP Clients
- HTTP clients MUST implement behaviours for testability
- Use Mox for testing with proper mocks
- All function parameters are explicit (no optional defaults)
- Configuration-based client injection for test/production environments

**Example Pattern:**
```elixir
# Define behaviour inside client module
defmodule Core.BggGateway.ReqClient do
  defmodule Behaviour do
    @callback get(String.t(), map(), map()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  end
  
  @behaviour Behaviour
  @impl Behaviour
  def get(url, params, headers), do: Req.get(url, params: params, headers: headers)
end

# Gateway uses configurable client
defp req_client do
  Application.get_env(:core, :bgg_req_client, Core.BggGateway.ReqClient)
end
```

#### 2. Testing Strategy
- Use Mox for HTTP client mocking
- Real API response data in tests (limited to 3 items for maintainability)
- Test both success and error scenarios
- Mock expectations must match exact function signatures

**Configuration:**
```elixir
# config/test.exs
config :core, :bgg_req_client, Core.MockReqClient

# test/support/mocks.ex
Mox.defmock(Core.MockReqClient, for: Core.BggGateway.ReqClient.Behaviour)
```

#### 3. Documentation Standards
- Keep @doc comments concise (one line descriptions)
- Let @callback and @spec be self-documenting
- Avoid verbose parameter/return descriptions
- Focus on module-level @moduledoc for context

**Good:**
```elixir
@doc "Retrieves a user's board game collection from BoardGameGeek."
@spec collection(String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
```

**Avoid:**
```elixir
@doc """
Retrieves a user's board game collection from BoardGameGeek.

## Parameters
  - username: BGG username (required)
  - opts: Options (optional)
  
## Returns
  - {:ok, response} on success
  - {:error, reason} on failure
"""
```

### Elixir Coding Standards

Follow the established Elixir rules in the project's Warp rules, specifically:

1. **File Structure**: Mirror module namespace in file paths
2. **Testing**: Every public function must have tests
3. **Error Handling**: Use `{:ok, result}` / `{:error, reason}` patterns
4. **Pipelines**: Use `with` construct for multi-step operations
5. **Function Signatures**: Be explicit with all parameters

### BoardGameGeek API Integration

#### API Endpoints Used
- **Collection**: `GET /xmlapi2/collection?username={username}`
- **Base URL**: `https://boardgamegeek.com/xmlapi2`

#### Key Behaviors
- BGG API may return HTTP 202 (processing) initially
- Invalid usernames return HTTP 200 with error XML
- All responses are XML format
- Rate limiting considerations for production use

#### Response Patterns
**Success (HTTP 200):**
```xml
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<items totalitems="72" termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
  <item objecttype="thing" objectid="68448" subtype="boardgame">
    <name sortindex="1">7 Wonders</name>
    <yearpublished>2010</yearpublished>
    <!-- ... -->
  </item>
</items>
```

**Error (HTTP 200):**
```xml
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<errors>
  <error>
    <message>Invalid username specified</message>
  </error>
</errors>
```

## Development Workflow

### Running Tests
```bash
# All tests including credo and dialyzer. Only use when testing end to end when explicitly asked, not after every change.
mix all_tests

# Specific test file  
mix test apps/core/test/core/bgg_gateway_test.exs
```
Do not rely on running mix test --trace for detailed output, just mix test is fine.

## Warp Agent Guidelines

### When starting a new warp context
1. Read this WARP.md file completely
2. Understand the current architecture and patterns
3. Check existing test coverage for similar functionality
4. Follow established naming and structure conventions

### When Adding New Features
1. **API Integration**: Follow the BggGateway pattern with behaviour-based clients
2. **Testing**: Create mocked tests with real API response data (limited samples)
3. **Documentation**: Keep @doc comments concise and focused
4. **Error Handling**: Use explicit `{:ok, result}` / `{:error, reason}` patterns

### When Modifying Existing Code
1. **Maintain Compatibility**: Don't break existing function signatures without updating all tests
2. **Update Tests**: Ensure all affected tests pass after changes
3. **Documentation**: Update @doc comments if behavior changes significantly
4. **Consistency**: Match existing patterns rather than introducing new styles

### Code Quality Expectations
- All public functions must have corresponding tests
- Mock real API responses (limited to 3 items for maintainability)  
- Use explicit parameter passing (avoid optional defaults in new code)
- Follow Elixir community conventions and project-specific rules
- Compile cleanly without warnings

### Testing Philosophy
- **Fast Tests**: Use mocks to avoid real HTTP calls
- **Real Data**: Base mocks on actual API responses
- **Comprehensive Coverage**: Test both success and error scenarios
- **Maintainable**: Keep test data small but representative

This document serves as the source of truth for how Warp agents should approach work on the BggSorter project. When in doubt, refer to existing patterns in the codebase and follow established Elixir conventions.
