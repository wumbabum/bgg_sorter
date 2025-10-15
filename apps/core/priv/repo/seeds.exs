# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Core.Repo.insert!(%Core.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

require Logger
alias Core.Repo
alias Core.Schemas.Mechanic

# Popular BoardGameGeek mechanics - seeded for immediate availability
mechanics_to_seed = [
  "Action Point Allowance System",
  "Area Control / Area Influence",
  "Area Movement",
  "Auction/Bidding",
  "Card Drafting",
  "Cooperative Play",
  "Deck, Bag, and Pool Building",
  "Dice Rolling",
  "End Game Bonuses",
  "Hand Management",
  "Hex-and-Counter",
  "Modular Board",
  "Pattern Building",
  "Pick-up and Deliver",
  "Player Elimination",
  "Point to Point Movement",
  "Role Playing",
  "Roll / Spin and Move",
  "Route/Network Building",
  "Secret Unit Deployment",
  "Set Collection",
  "Simultaneous Action Selection",
  "Storytelling",
  "Take That",
  "Tile Placement",
  "Trading",
  "Trick-taking",
  "Variable Player Powers",
  "Variable Set-up",
  "Voting",
  "Worker Placement",
  "Area Enclosure",
  "Betting and Bluffing",
  "Campaign / Battle Card Driven",
  "Chit-Pull System",
  "Co-operative Play",
  "Command Cards",
  "Commodity Speculation",
  "Connection",
  "Contract Fulfillment",
  "Crayon Rail System",
  "Cube Tower",
  "Deduction",
  "Grid Movement",
  "Hidden Roles",
  "Income",
  "Investment",
  "Line Drawing",
  "Market",
  "Memory",
  "Negotiation",
  "Network and Route Building",
  "Once-Per-Game Abilities",
  "Paper-and-Pencil",
  "Partnerships",
  "Physical Removal",
  "Programmed Movement",
  "Push Your Luck",
  "Real-Time",
  "Rock-Paper-Scissors",
  "Semi-Cooperative Game",
  "Simulation",
  "Stock Holding",
  "Team-Based Game",
  "Time Track",
  "Turn Order: Claim Action",
  "Turn Order: Progressive",
  "Turn Order: Random",
  "Variable Phase Order",
  "Wargame"
]

Logger.info("Seeding #{length(mechanics_to_seed)} popular mechanics...")

current_time = DateTime.utc_now() |> DateTime.truncate(:second)

mechanics_params =
  mechanics_to_seed
  |> Enum.map(fn name ->
    %{
      id: Ecto.UUID.generate(),
      name: name,
      slug: Mechanic.generate_slug(name),
      inserted_at: current_time,
      updated_at: current_time
    }
  end)

# Use insert_all with on_conflict to avoid duplicates
{inserted_count, _} =
  Repo.insert_all(
    Mechanic,
    mechanics_params,
    on_conflict: :nothing,
    conflict_target: :name,
    returning: false
  )

Logger.info(
  "Successfully seeded #{inserted_count} mechanics (#{length(mechanics_to_seed) - inserted_count} already existed)"
)

Logger.info("Total mechanics in database: #{Repo.aggregate(Mechanic, :count)}")
