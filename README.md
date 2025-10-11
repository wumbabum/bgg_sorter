# BggSorter

I want to create an application that utilizes the BoardGameGeek API to view a user's board game collection and display it as a Phoenix application. I plan on deploying this application to Fly.io, so it will need to be Dockerized and accessible on the internet. The core application will be part of an Umbrella app with the core app being responsible for API. API requests to the BoardGameGeek API. The BoardGameGeek API will provide a user's collection. It will also provide any images for those actual board games in that collection. The Elixir application will be responsible for filtering and sorting that application as well as providing an interface for those filtering and sorting options as well as displaying the board games. It will also have a page to input a user's username which will be used to initialize the request to the BoardGameGeek API. Let's start by making an Umbrella application in Elixir with Phoenix as a dependency. I want to have it use the same name as the current folder, bgg_sorter. 

There should only be two child apps, Core, and Web. Web should have phoenix as a dependency. when initializing the child apps, do not add unnecessary external dependencies proactively yet.

The core folder should be called 'core', not bgg_sorter_core, and 'web' is also just 'web'. Use this when initializing the applications.
