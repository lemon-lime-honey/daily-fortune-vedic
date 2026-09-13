defmodule Api.Storage do
  @moduledoc """
  Handles file-based persistent storage for daily fortune records.
  Provides idempotent read/write and state transition operations.
  """
  require Logger

  @default_data_dir "data/records"

  @type record_status :: :calculated | :generated | :synced

  @doc """
  Returns the base directory for storing records.
  Can be configured via the DATA_DIR environment variable.
  """
  def base_dir do
    System.get_env("DATA_DIR") || @default_data_dir
  end

  @doc """
  Returns the absolute or relative file path for a given date string (YYYY-MM-DD).
  """
  def file_path(date_str) when is_binary(date_str) do
    Path.join(base_dir(), "#{date_str}.json")
  end

  @doc """
  Retrieves a record by date string.
  Returns `{:ok, record}` if found and valid, `{:error, :not_found}` if file does not exist,
  or `{:error, reason}` if reading or parsing fails.
  """
  def get_record(date_str) when is_binary(date_str) do
    path = file_path(date_str)

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} ->
              {:ok, data}

            {:error, reason} ->
              Logger.error("Failed to parse JSON record at #{path}: #{inspect(reason)}")
              {:error, {:corrupted_record, reason}}
          end

        {:error, reason} ->
          Logger.error("Failed to read record at #{path}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Persists calculated astrological chart data for a given date.
  If a record already exists, updates `calc_data` while preserving subsequent steps.
  """
  def save_calc_data(date_str, calc_data) when is_binary(date_str) and is_map(calc_data) do
    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

    initial_record = %{
      "date" => date_str,
      "status" => "calculated",
      "calc_data" => calc_data,
      "llm_result" => nil,
      "notion" => nil,
      "inserted_at" => now_iso,
      "updated_at" => now_iso
    }

    update_fn = fn existing ->
      existing
      |> Map.put("calc_data", calc_data)
      |> Map.put("updated_at", now_iso)
      |> Map.put_new("status", "calculated")
    end

    upsert_record(date_str, initial_record, update_fn)
  end

  @doc """
  Persists generated LLM fortune result for a given date.
  Sets status to 'generated' unless already 'synced'.
  """
  def save_llm_result(date_str, llm_result) when is_binary(date_str) and is_map(llm_result) do
    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

    initial_record = %{
      "date" => date_str,
      "status" => "generated",
      "calc_data" => nil,
      "llm_result" => llm_result,
      "notion" => nil,
      "inserted_at" => now_iso,
      "updated_at" => now_iso
    }

    update_fn = fn existing ->
      new_status =
        if Map.get(existing, "status") == "synced", do: "synced", else: "generated"

      existing
      |> Map.put("llm_result", llm_result)
      |> Map.put("status", new_status)
      |> Map.put("updated_at", now_iso)
    end

    upsert_record(date_str, initial_record, update_fn)
  end

  @doc """
  Marks a record as synced to Notion, recording Notion page metadata.
  """
  def mark_synced(date_str, notion_meta \\ %{})
      when is_binary(date_str) and is_map(notion_meta) do
    now_iso = DateTime.utc_now() |> DateTime.to_iso8601()

    update_fn = fn existing ->
      existing
      |> Map.put("notion", notion_meta)
      |> Map.put("status", "synced")
      |> Map.put("updated_at", now_iso)
    end

    case get_record(date_str) do
      {:ok, existing} ->
        updated = update_fn.(existing)
        write_record(date_str, updated)

      {:error, :not_found} ->
        record = %{
          "date" => date_str,
          "status" => "synced",
          "calc_data" => nil,
          "llm_result" => nil,
          "notion" => notion_meta,
          "inserted_at" => now_iso,
          "updated_at" => now_iso
        }

        write_record(date_str, record)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all stored records sorted by date in descending order.
  """
  def list_records do
    dir = base_dir()

    if File.dir?(dir) do
      records =
        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort(:desc)
        |> Enum.map(fn file ->
          date = String.replace_suffix(file, ".json", "")

          case get_record(date) do
            {:ok, record} -> record
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

      {:ok, records}
    else
      {:ok, []}
    end
  end

  @doc """
  Returns a list of records whose status is not 'synced'.
  """
  def get_pending_records do
    with {:ok, records} <- list_records() do
      pending = Enum.filter(records, fn r -> Map.get(r, "status") != "synced" end)
      {:ok, pending}
    end
  end

  defp upsert_record(date_str, initial_record, update_fn) do
    case get_record(date_str) do
      {:ok, existing} ->
        updated = update_fn.(existing)
        write_record(date_str, updated)

      {:error, :not_found} ->
        write_record(date_str, initial_record)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_record(date_str, record) do
    dir = base_dir()
    path = file_path(date_str)

    with :ok <- File.mkdir_p(dir),
         {:ok, json_data} <- Jason.encode(record, pretty: true),
         :ok <- File.write(path, json_data) do
      {:ok, record}
    else
      {:error, reason} ->
        Logger.error("Failed to write record to #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
