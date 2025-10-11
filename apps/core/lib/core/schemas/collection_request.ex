defmodule Core.Schemas.CollectionRequest do
  @moduledoc """
  Schema for validating BGG collection API request parameters.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: []}

  embedded_schema do
    field :username, :string
    field :version, :integer
    field :subtype, :string
    field :excludesubtype, :string
    field :own, :integer
    field :rated, :integer
    field :played, :integer
    field :comment, :integer
    field :trade, :integer
    field :want, :integer
    field :wishlist, :integer
    field :wishlistpriority, :integer
    field :preordered, :integer
    field :wanttoplay, :integer
    field :wanttobuy, :integer
    field :prevowned, :integer
    field :hasparts, :integer
    field :wantparts, :integer
    field :minrating, :integer
    field :rating, :integer
    field :minbggrating, :integer
    field :modifiedsince, :string
    field :stats, :integer
  end

  @doc "Validates collection request parameters."
  def changeset(collection_request, attrs) do
    collection_request
    |> cast(attrs, [
      :username,
      :version,
      :subtype,
      :excludesubtype,
      :own,
      :rated,
      :played,
      :comment,
      :trade,
      :want,
      :wishlist,
      :wishlistpriority,
      :preordered,
      :wanttoplay,
      :wanttobuy,
      :prevowned,
      :hasparts,
      :wantparts,
      :minrating,
      :rating,
      :minbggrating,
      :modifiedsince,
      :stats
    ])
    |> validate_required([:username])
    |> validate_inclusion(:version, [1])
    |> validate_inclusion(:subtype, ["boardgame", "boardgameexpansion"])
    |> validate_inclusion(:excludesubtype, ["boardgameexpansion"])
    |> validate_inclusion(:own, [0, 1])
    |> validate_inclusion(:rated, [0, 1])
    |> validate_inclusion(:played, [0, 1])
    |> validate_inclusion(:comment, [0, 1])
    |> validate_inclusion(:trade, [0, 1])
    |> validate_inclusion(:want, [0, 1])
    |> validate_inclusion(:wishlist, [0, 1])
    |> validate_inclusion(:wishlistpriority, [1, 2, 3, 4, 5])
    |> validate_inclusion(:preordered, [0, 1])
    |> validate_inclusion(:wanttoplay, [0, 1])
    |> validate_inclusion(:wanttobuy, [0, 1])
    |> validate_inclusion(:prevowned, [0, 1])
    |> validate_inclusion(:hasparts, [0, 1])
    |> validate_inclusion(:wantparts, [0, 1])
    |> validate_inclusion(:minrating, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> validate_inclusion(:rating, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> validate_inclusion(:minbggrating, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> validate_format(:modifiedsince, ~r/^\d{4}-\d{2}-\d{2}$/)
    |> validate_inclusion(:stats, [0, 1])
  end
end
