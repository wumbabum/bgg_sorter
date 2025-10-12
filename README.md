# BggSorter

A Phoenix LiveView application that interfaces with the BoardGameGeek API to browse, filter, and sort board game collections. Features advanced search capabilities, real-time filtering, game detail modals, and a database-backed caching system for optimal performance.

## Use it live:
https://bgg-sorter.fly.dev/

## Stack
- **Elixir 1.15.6+** with **Erlang 26.1.2+**
- **PostgreSQL 15+** (for caching system)
- **Docker** or **Podman** (for containerized deployment)

### Bare metal installation

1. **Clone and setup:**
   ```bash
   git clone <repository-url>
   cd bgg_sorter
   mix deps.get
   ```

2. **Setup database:**
   ```bash
   # Create and migrate database
   mix ecto.create
   mix ecto.migrate
   ```

3. **Setup and build assets:**
   ```bash
   mix assets.setup
   mix assets.build
   ```

4. **Start the application:**
   ```bash
   mix phx.server
   ```

5. **Visit:** [http://localhost:7384](http://localhost:7384)

### Testing

```bash
# Run all tests
mix test

# Run tests with full coverage and quality checks
mix all_tests
```

**That's it!** The application will be available at [http://localhost:7384](http://localhost:7384)

### Docker/Podman container
For Docker, use `docker compose up`
For Podman, use `podman-compose up`

## My blurb about how i wanted the app to work.

The web interface will use Phoenix LiveView to create a reactive board game collection browser. Users enter their BGG username to load their collection, then filter and sort games client-side by name, year, rating, number of players, and other attributes. Number of players should include any game that has a minimum number of players to maximum number of players that includes the number entered on the form. Clicking any game opens a modal with detailed information, statistics, and images loaded asynchronously. The interface will feature clean responsive design, fast filtering, graceful error handling with retry options, and caching of loaded game details for optimal performance. LiveView's server-side state management and WebSocket reactivity will provide seamless real-time updates while maintaining accessibility standards.

This plan met a significant roadblock when I realized that boardgamegeek will give you a full list of a user's board games with one request, but leaves out a bunch of important details like number of players. If you want that data, you can only request max 20 at a time. I used warp and claude to create a cacheing solution where I make rate limited request to save that data and use the saved data instead of requesting it from board game geek to do filtering. The app will re-request data if the data is more than a week old.

### Warning
A lot of this is vibe coded, especially the frontend and styling, with fairly loose guidance. I would hate to subject anyone on this poor code. My biggest complaints:
1. AI didn't use easy to use control structures. I took my time at the beginning to set it on the right track, and it lasted until the end, but clearly it's desperate to derail itself.
2. AI did not do a great job of state management for the frontend. It's a mess. A proper frontend would have given more thought to when reloading was necessary, and when the existing phoenix live session could be used instead. There are definitely bugs in navigation that will change the data you are looking at.
3. I didn't test filtering on all the fields, and I'm pretty sure AI hallunicated that they all work. Player count works, and that's what I cared about most.
