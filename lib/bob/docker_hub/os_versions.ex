defmodule Bob.DockerHub.OSVersions do
  @max_alpine_versions 2

  # TODO: Automate picking ubuntu and debian os versions

  @static_os_versions %{
    "ubuntu" => [
      "groovy-20210325",
      "focal-20210325",
      "bionic-20210325",
      "xenial-20210114",
      "trusty-20191217"
    ],
    "debian" => [
      "buster-20210326",
      "stretch-20210326",
      "jessie-20210326"
    ]
  }

  def get_os_versions do
    Map.put(@static_os_versions, "alpine", get_alpine_versions())
  end

  defp get_alpine_versions() do
    "library/alpine"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Enum.flat_map(fn {version, _} ->
      case Version.parse(version) do
        {:ok, version} -> [version]
        :error -> []
      end
    end)
    |> Enum.reduce(%{}, fn version, acc ->
      Map.update(acc, "#{version.major}.#{version.minor}", version, fn current ->
        higher_version(current, version)
      end)
    end)
    |> Map.values()
    |> Enum.sort(:desc)
    |> Enum.take(@max_alpine_versions)
    |> Enum.map(fn version -> to_string(version) end)
  end

  defp higher_version(version1, version2) do
    case Version.compare(version1, version2) do
      :gt -> version1
      :lt -> version2
      _ -> version1
    end
  end
end
