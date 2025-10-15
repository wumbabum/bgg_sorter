defmodule Core.Release do
  @moduledoc """
  Release management functions for database migrations and setup in production environments.

  This module provides helper functions to run database operations during deployment,
  particularly useful for containerized deployments where manual intervention is limited.
  """

  @app :core

  @doc """
  Runs database migrations for the Core application.

  This function can be called during deployment to ensure the database schema
  is up to date before starting the application.

  ## Examples

      # From a release console:
      Core.Release.migrate()
      
      # From command line:
      ./bin/bgg_sorter eval "Core.Release.migrate()"
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rolls back the database to a previous migration version.

  ## Parameters

    - version: The migration version to rollback to
    
  ## Examples

      Core.Release.rollback(20251012070159)
  """
  def rollback(version) do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    end
  end

  @doc """
  Creates the database if it doesn't exist.

  Useful for initial deployment setup.
  """
  def create_database do
    load_app()

    for repo <- repos() do
      case repo.__adapter__.storage_up(repo.config) do
        :ok ->
          IO.puts("Database created for #{inspect(repo)}")

        {:error, :already_up} ->
          IO.puts("Database already exists for #{inspect(repo)}")

        {:error, term} ->
          IO.warn("Failed to create database for #{inspect(repo)}: #{inspect(term)}")
      end
    end
  end

  @doc """
  Drops the database.

  ⚠️  WARNING: This will permanently delete all data.
  Only use in development or when you're absolutely sure.
  """
  def drop_database do
    load_app()

    for repo <- repos() do
      case repo.__adapter__.storage_down(repo.config) do
        :ok ->
          IO.puts("Database dropped for #{inspect(repo)}")

        {:error, :already_down} ->
          IO.puts("Database does not exist for #{inspect(repo)}")

        {:error, term} ->
          IO.warn("Failed to drop database for #{inspect(repo)}: #{inspect(term)}")
      end
    end
  end

  @doc """
  Resets the database by dropping, creating, and migrating.

  ⚠️  WARNING: This will permanently delete all data.
  Only use in development environments.
  """
  def reset_database do
    drop_database()
    create_database()
    migrate()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
