defmodule Api.NotionClient do
  @moduledoc """
  Client for interacting with the Notion API.
  """

  @doc """
  Appends fortune content to a Notion page.
  """
  def append_fortune(title, content) do
    api_key = System.get_env("NOTION_API_KEY")
    page_id = System.get_env("NOTION_TARGET_ID")

    if is_nil(api_key) or api_key == "" or api_key == "mock_notion_key" do
      # Mock success during testing/dev if no key is configured
      {:ok, %{"object" => "list", "results" => []}}
    else
      url = "https://api.notion.com/v1/blocks/#{page_id}/children"

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Notion-Version", "2022-06-28"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        "children" => [
          %{
            "object" => "block",
            "type" => "heading_2",
            "heading_2" => %{
              "rich_text" => [
                %{
                  "type" => "text",
                  "text" => %{"content" => title}
                }
              ]
            }
          },
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

      case Req.patch(url, json: body, headers: headers) do
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
