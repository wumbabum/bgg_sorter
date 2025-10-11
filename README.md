# BggSorter

I want to create an application that utilizes the BoardGameGeek API to view a user's board game collection and display it as a Phoenix application. I plan on deploying this application to Fly.io, so it will need to be Dockerized and accessible on the internet. The core application will be part of an Umbrella app with the core app being responsible for API. API requests to the BoardGameGeek API. The BoardGameGeek API will provide a user's collection. It will also provide any images for those actual board games in that collection. The Elixir application will be responsible for filtering and sorting that application as well as providing an interface for those filtering and sorting options as well as displaying the board games. It will also have a page to input a user's username which will be used to initialize the request to the BoardGameGeek API. Let's start by making an Umbrella application in Elixir with Phoenix as a dependency. I want to have it use the same name as the current folder, bgg_sorter. 

There should only be two child apps, Core, and Web. Web should have phoenix as a dependency. when initializing the child apps, do not add unnecessary external dependencies proactively yet.

The core folder should be called 'core', not bgg_sorter_core, and 'web' is also just 'web'. Use this when initializing the applications.

## BoardGameGeek XML API2 Endpoints

The BGG XML API2 provides several endpoints for accessing board game data:

### Base URL
```
https://boardgamegeek.com/xmlapi2
```

### Primary Endpoints

#### 1. Collection
Get a user's board game collection:
```
GET /xmlapi2/collection?username={username}
```
**Parameters:**
- `username` (required): BGG username
- `version=1`: Include version info
- `subtype=boardgame`: Filter to board games only
- `excludesubtype=boardgameexpansion`: Exclude expansions
- `own=1`: Only owned games
- `rated=1`: Only rated games
- `played=1`: Only played games
- `comment=1`: Include comments
- `trade=1`: Games for trade
- `want=1`: Wanted games
- `wishlist=1`: Wishlist games
- `wishlistpriority=1-5`: Wishlist priority level
- `preordered=1`: Pre-ordered games
- `wanttoplay=1`: Want to play games
- `wanttobuy=1`: Want to buy games
- `prevowned=1`: Previously owned games
- `hasparts=1`: Games with parts
- `wantparts=1`: Games wanting parts
- `minrating=1-10`: Minimum rating
- `rating=1-10`: Exact rating
- `minbggrating=1-10`: Minimum BGG rating
- `modifiedsince=YYYY-MM-DD`: Modified since date
- `stats=1`: Include stats

#### 2. Game/Item Information
Get detailed information about specific games:
```
GET /xmlapi2/thing?id={id}
```
**Parameters:**
- `id` (required): Comma-separated list of game IDs
- `type=boardgame`: Item type (boardgame, boardgameexpansion, etc.)
- `versions=1`: Include version info
- `videos=1`: Include videos
- `stats=1`: Include statistics
- `historical=1`: Include historical data
- `marketplace=1`: Include marketplace data
- `comments=1`: Include comments
- `ratingcomments=1`: Include rating comments
- `page=1`: Comments page number
- `pagesize=100`: Comments per page

#### 3. Search
Search for games by name:
```
GET /xmlapi2/search?query={query}
```
**Parameters:**
- `query` (required): Search term
- `type=boardgame`: Search type (boardgame, boardgameexpansion, etc.)
- `exact=1`: Exact name match only

#### 4. Hot Items
Get current hot/trending games:
```
GET /xmlapi2/hot?type=boardgame
```
**Parameters:**
- `type` (required): Item type (boardgame, rpg, videogame, etc.)

#### 5. User Information
Get user profile information:
```
GET /xmlapi2/user?name={username}
```
**Parameters:**
- `name` (required): BGG username
- `buddies=1`: Include buddy list
- `guilds=1`: Include guild memberships
- `hot=1`: Include hot items
- `top=1`: Include top items
- `domain=boardgame`: Domain filter

#### 6. Guild Information
Get guild information:
```
GET /xmlapi2/guild?id={id}
```
**Parameters:**
- `id` (required): Guild ID
- `members=1`: Include member list
- `sort=username`: Sort order
- `page=1`: Page number

#### 7. Plays
Get user's logged plays:
```
GET /xmlapi2/plays?username={username}
```
**Parameters:**
- `username` (required): BGG username
- `id={id}`: Specific game ID
- `type=thing`: Play type
- `mindate=YYYY-MM-DD`: Minimum date
- `maxdate=YYYY-MM-DD`: Maximum date
- `subtype=boardgame`: Game subtype
- `page=1`: Page number

#### 8. Forums
Get forum information:
```
GET /xmlapi2/forumlist?id={id}&type=thing
```

#### 9. Forum Threads
Get forum thread information:
```
GET /xmlapi2/forum?id={id}
```

#### 10. Thread Messages
Get thread messages:
```
GET /xmlapi2/thread?id={id}
```

### Response Format
All endpoints return XML data. Common response elements include:
- Game information: name, description, year published, mechanics, categories
- User collection data: ownership status, ratings, comments
- Statistics: average ratings, complexity, player counts
- Images: thumbnails and full-size images

### Rate Limiting
- Be respectful with API calls
- Implement appropriate delays between requests
- Cache responses when possible
- The API may return HTTP 202 (Accepted) for large requests that need processing time
