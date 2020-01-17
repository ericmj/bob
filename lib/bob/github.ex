defmodule Bob.GitHub do
  @github_url "https://api.github.com/"

  def diff(repo, build_path) do
    existing = fetch_repo_refs(repo)
    built = Bob.Repo.fetch_built_refs(build_path)

    Enum.filter(existing, fn {name, ref} ->
      case Map.fetch(built, name) do
        {:ok, ^ref} -> false
        _other -> true
      end
    end)
  end

  def fetch_repo_refs(repo) do
    branches = github_request(@github_url <> "repos/#{repo}/branches")
    tags = github_request(@github_url <> "repos/#{repo}/tags")
    response_to_refs(branches) ++ response_to_refs(tags)
  end

  defp response_to_refs(response) do
    Enum.map(response, &{&1["name"], &1["commit"]["sha"]})
  end

  defp github_request(url) do
    user = Application.get_env(:bob, :github_user)
    token = Application.get_env(:bob, :github_token)

    opts = [:with_body, basic_auth: {user, token}]
    {:ok, 200, headers, body} = :hackney.request(:get, url, [], "", opts)
    body = Jason.decode!(body)

    if url = next_link(headers) do
      body ++ github_request(url)
    else
      body
    end
  end

  defp next_link(headers) do
    headers = Map.new(headers, fn {key, value} -> {String.downcase(key), value} end)
    links = Map.get(headers, "link", "") |> String.split(",", trim: true)

    Enum.find_value(links, fn link ->
      [link, rel] = String.split(link, ";", trim: true, parts: 2)

      if String.trim(rel) == "rel=\"next\"" do
        link
        |> String.trim()
        |> String.trim_leading("<")
        |> String.trim_trailing(">")
      end
    end)
  end
end
