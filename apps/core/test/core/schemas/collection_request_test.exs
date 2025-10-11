defmodule Core.Schemas.CollectionRequestTest do
  use ExUnit.Case

  alias Core.Schemas.CollectionRequest

  describe "changeset/2" do
    test "valid changeset with required username" do
      attrs = %{username: "testuser"}
      changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without username" do
      attrs = %{}
      changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :username)
    end

    test "valid changeset with all parameters" do
      attrs = %{
        username: "testuser",
        version: 1,
        subtype: "boardgame",
        excludesubtype: "boardgameexpansion",
        own: 1,
        rated: 1,
        played: 0,
        comment: 1,
        trade: 0,
        want: 1,
        wishlist: 0,
        wishlistpriority: 3,
        preordered: 0,
        wanttoplay: 1,
        wanttobuy: 0,
        prevowned: 1,
        hasparts: 0,
        wantparts: 1,
        minrating: 5,
        rating: 8,
        minbggrating: 6,
        modifiedsince: "2025-01-01",
        stats: 1
      }

      changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
      assert changeset.valid?
    end

    test "validates version inclusion" do
      attrs = %{username: "testuser", version: 2}
      changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :version)
    end

    test "validates subtype inclusion" do
      attrs = %{username: "testuser", subtype: "invalidtype"}
      changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :subtype)

      # Valid subtypes
      valid_attrs = %{username: "testuser", subtype: "boardgame"}
      valid_changeset = CollectionRequest.changeset(%CollectionRequest{}, valid_attrs)
      assert valid_changeset.valid?

      valid_attrs2 = %{username: "testuser", subtype: "boardgameexpansion"}
      valid_changeset2 = CollectionRequest.changeset(%CollectionRequest{}, valid_attrs2)
      assert valid_changeset2.valid?
    end

    test "validates excludesubtype inclusion" do
      attrs = %{username: "testuser", excludesubtype: "invalidtype"}
      changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :excludesubtype)

      # Valid excludesubtype
      valid_attrs = %{username: "testuser", excludesubtype: "boardgameexpansion"}
      valid_changeset = CollectionRequest.changeset(%CollectionRequest{}, valid_attrs)
      assert valid_changeset.valid?
    end

    test "validates binary flags are 0 or 1" do
      binary_fields = [
        :own,
        :rated,
        :played,
        :comment,
        :trade,
        :want,
        :wishlist,
        :preordered,
        :wanttoplay,
        :wanttobuy,
        :prevowned,
        :hasparts,
        :wantparts,
        :stats
      ]

      Enum.each(binary_fields, fn field ->
        # Invalid value
        invalid_attrs = Map.put(%{username: "testuser"}, field, 2)
        invalid_changeset = CollectionRequest.changeset(%CollectionRequest{}, invalid_attrs)
        refute invalid_changeset.valid?
        assert Keyword.has_key?(invalid_changeset.errors, field)

        # Valid values
        valid_attrs_0 = Map.put(%{username: "testuser"}, field, 0)
        valid_changeset_0 = CollectionRequest.changeset(%CollectionRequest{}, valid_attrs_0)
        assert valid_changeset_0.valid?

        valid_attrs_1 = Map.put(%{username: "testuser"}, field, 1)
        valid_changeset_1 = CollectionRequest.changeset(%CollectionRequest{}, valid_attrs_1)
        assert valid_changeset_1.valid?
      end)
    end

    test "validates wishlistpriority range" do
      # Invalid values
      invalid_attrs = %{username: "testuser", wishlistpriority: 0}
      invalid_changeset = CollectionRequest.changeset(%CollectionRequest{}, invalid_attrs)
      refute invalid_changeset.valid?
      assert Keyword.has_key?(invalid_changeset.errors, :wishlistpriority)

      invalid_attrs2 = %{username: "testuser", wishlistpriority: 6}
      invalid_changeset2 = CollectionRequest.changeset(%CollectionRequest{}, invalid_attrs2)
      refute invalid_changeset2.valid?
      assert Keyword.has_key?(invalid_changeset2.errors, :wishlistpriority)

      # Valid values (1-5)
      Enum.each([1, 2, 3, 4, 5], fn priority ->
        valid_attrs = %{username: "testuser", wishlistpriority: priority}
        valid_changeset = CollectionRequest.changeset(%CollectionRequest{}, valid_attrs)
        assert valid_changeset.valid?
      end)
    end

    test "validates rating ranges" do
      rating_fields = [:minrating, :rating, :minbggrating]

      Enum.each(rating_fields, fn field ->
        # Invalid values
        invalid_attrs_low = Map.put(%{username: "testuser"}, field, 0)

        invalid_changeset_low =
          CollectionRequest.changeset(%CollectionRequest{}, invalid_attrs_low)

        refute invalid_changeset_low.valid?
        assert Keyword.has_key?(invalid_changeset_low.errors, field)

        invalid_attrs_high = Map.put(%{username: "testuser"}, field, 11)

        invalid_changeset_high =
          CollectionRequest.changeset(%CollectionRequest{}, invalid_attrs_high)

        refute invalid_changeset_high.valid?
        assert Keyword.has_key?(invalid_changeset_high.errors, field)

        # Valid values (1-10)
        Enum.each([1, 5, 10], fn rating ->
          valid_attrs = Map.put(%{username: "testuser"}, field, rating)
          valid_changeset = CollectionRequest.changeset(%CollectionRequest{}, valid_attrs)
          assert valid_changeset.valid?
        end)
      end)
    end

    test "validates modifiedsince date format" do
      # Invalid date formats
      invalid_dates = ["2025/01/01", "01-01-2025", "2025-1-1", "invalid-date", "25-01-01"]

      Enum.each(invalid_dates, fn date ->
        attrs = %{username: "testuser", modifiedsince: date}
        changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
        refute changeset.valid?
        assert Keyword.has_key?(changeset.errors, :modifiedsince)
      end)

      # Valid date formats
      valid_dates = ["2025-01-01", "2024-12-31", "2000-06-15"]

      Enum.each(valid_dates, fn date ->
        attrs = %{username: "testuser", modifiedsince: date}
        changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
        assert changeset.valid?
      end)
    end

    test "allows nil values for optional fields" do
      attrs = %{
        username: "testuser",
        version: nil,
        subtype: nil,
        own: nil,
        stats: nil
      }

      changeset = CollectionRequest.changeset(%CollectionRequest{}, attrs)
      assert changeset.valid?
    end
  end
end
