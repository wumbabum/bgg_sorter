defmodule Core.Schemas.MechanicTest do
  use Core.DataCase, async: true

  alias Core.Schemas.Mechanic

  describe "changeset/2" do
    test "creates valid changeset with name and slug" do
      params = %{
        name: "Hand Management",
        slug: "hand-management"
      }

      changeset = Mechanic.changeset(%Mechanic{}, params)

      assert changeset.valid?
      assert get_change(changeset, :name) == "Hand Management"
      assert get_change(changeset, :slug) == "hand-management"
    end

    test "requires name field" do
      params = %{slug: "test-slug"}

      changeset = Mechanic.changeset(%Mechanic{}, params)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires slug field" do
      params = %{name: "Test Mechanic"}

      changeset = Mechanic.changeset(%Mechanic{}, params)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "validates unique constraint on name" do
      # First mechanic
      first_params = %{name: "Hand Management", slug: "hand-management"}

      {:ok, _first_mechanic} =
        %Mechanic{}
        |> Mechanic.changeset(first_params)
        |> Repo.insert()

      # Second mechanic with same name
      duplicate_params = %{name: "Hand Management", slug: "hand-management-2"}
      changeset = Mechanic.changeset(%Mechanic{}, duplicate_params)

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(failed_changeset).name
    end

    test "validates unique constraint on slug" do
      # First mechanic
      first_params = %{name: "Hand Management", slug: "hand-management"}

      {:ok, _first_mechanic} =
        %Mechanic{}
        |> Mechanic.changeset(first_params)
        |> Repo.insert()

      # Second mechanic with same slug
      duplicate_params = %{name: "Hand Management 2", slug: "hand-management"}
      changeset = Mechanic.changeset(%Mechanic{}, duplicate_params)

      assert {:error, failed_changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(failed_changeset).slug
    end
  end

  describe "generate_slug/1" do
    test "converts name to URL-friendly slug" do
      assert Mechanic.generate_slug("Hand Management") == "hand-management"
      assert Mechanic.generate_slug("Worker Placement") == "worker-placement"

      assert Mechanic.generate_slug("Area Control / Area Influence") ==
               "area-control-area-influence"
    end

    test "handles special characters" do
      assert Mechanic.generate_slug("Co-op Game") == "co-op-game"
      assert Mechanic.generate_slug("Trick-taking") == "trick-taking"
      assert Mechanic.generate_slug("Roll & Move") == "roll-move"
    end

    test "handles multiple spaces" do
      assert Mechanic.generate_slug("Multiple   Spaces   Here") == "multiple-spaces-here"
      assert Mechanic.generate_slug("  Leading and trailing  ") == "leading-and-trailing"
    end

    test "handles empty or whitespace-only strings" do
      assert Mechanic.generate_slug("") == ""
      assert Mechanic.generate_slug("   ") == ""
    end

    test "preserves numbers" do
      assert Mechanic.generate_slug("1 vs Many") == "1-vs-many"
      assert Mechanic.generate_slug("2 Player Only") == "2-player-only"
    end
  end
end
