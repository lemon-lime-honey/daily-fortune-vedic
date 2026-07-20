defmodule Api.NotionClient do
  @moduledoc """
  Client for interacting with the Notion API to create pages in a database.
  """

  @doc """
  Creates a new page in a Notion database with the fortune content and structured metadata.
  """
  def append_fortune(title, content, metadata) do
    api_key = System.get_env("NOTION_API_KEY")
    database_id = System.get_env("NOTION_TARGET_ID")

    if is_nil(api_key) or api_key == "" or api_key == "mock_notion_key" do
      # Mock success during testing/dev if no key is configured
      {:ok, %{"object" => "page", "id" => "mock_page_id"}}
    else
      url = "https://api.notion.com/v1/pages"

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Notion-Version", "2022-06-28"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        "parent" => %{"database_id" => database_id},
        "properties" => %{
          "Name" => %{
            "title" => [
              %{
                "type" => "text",
                "text" => %{"content" => title}
              }
            ]
          },
          "Date" => %{
            "date" => %{"start" => metadata.date}
          },
          "Dasha" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => metadata.dasha}
              }
            ]
          },
          "Transit Moon" => %{
            "select" => %{"name" => metadata.transit_moon}
          },
          "Score" => %{
            "number" => metadata.score
          },
          "Tithi" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => metadata.tithi}
              }
            ]
          },
          "Nakshatra" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => metadata.nakshatra}
              }
            ]
          },
          "Yoga" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => metadata.yoga}
              }
            ]
          },
          "Karana" => %{
            "rich_text" => [
              %{
                "type" => "text",
                "text" => %{"content" => metadata.karana}
              }
            ]
          },
          "Weekday" => %{
            "select" => %{"name" => metadata.weekday}
          },
          "Tara Bala" => %{
            "select" => %{"name" => metadata.tara_bala}
          },
          "Transit Moon SAV" => %{
            "number" => metadata.transit_moon_sav
          },
          "Transit Moon BAV" => %{
            "number" => metadata.transit_moon_bav
          },
          "Activated Triggers" => %{
            "multi_select" => Enum.map(metadata.activated_triggers, &%{"name" => &1})
          }
        },
        "children" => [
          %{
            "object" => "block",
            "type" => "paragraph",
            "paragraph" => %{
              "rich_text" => [
                %{
                  "type" => "text",
                  "text" => %{"content" => content}
                }
              ]
            }
          }
        ]
      }

      case Req.post(url, json: body, headers: headers) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
