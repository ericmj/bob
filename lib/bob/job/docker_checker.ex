defmodule Bob.Job.DockerChecker do
  @erlang_tag_regex ~r"^([^-]+)-([^-]+)-(.+)$"
  @elixir_tag_regex ~r"^(.+)-erlang-([^-]+)-([^-]+)-(.+)$"

  @archs ["amd64", "arm64"]

  @builds %{
    "alpine" => ["3.12.0"],
    "ubuntu" => ["focal-20200703", "bionic-20200630", "xenial-20200619", "trusty-20191217"],
    "debian" => ["buster-20200607", "stretch-20200607", "jessie-20200607"]
  }

  def run() do
    erlang()
    elixir()
    manifests()
  end

  def priority(), do: 1
  def weight(), do: 1

  def erlang() do
    tags = erlang_tags()
    expected_tags = expected_erlang_tags()

    Enum.each(diff(expected_tags, tags), fn {erlang, os, os_version, arch} ->
      Bob.Queue.add({Bob.Job.BuildDockerErlang, arch}, [erlang, os, os_version])
    end)
  end

  def expected_erlang_tags() do
    refs = erlang_refs()

    for {os, os_versions} <- @builds,
        ref <- refs,
        build_erlang_ref?(os, ref),
        os_version <- os_versions,
        build_erlang_ref?(os, os_version, ref),
        arch <- @archs,
        build_erlang_ref?(arch, os, os_version, ref),
        "OTP-" <> erlang = ref,
        key = {erlang, os, os_diff(os, os_version), arch},
        value = {erlang, os, os_version, arch},
        do: {key, value}
  end

  defp build_erlang_ref?(_os, "OTP-18.0-rc2"), do: false
  defp build_erlang_ref?("alpine", "OTP-17" <> _), do: false
  defp build_erlang_ref?("alpine", "OTP-18" <> _), do: false
  defp build_erlang_ref?(_os, "OTP-" <> version), do: not String.contains?(version, "-")
  defp build_erlang_ref?(_os, _ref), do: false

  defp build_erlang_ref?("debian", "buster-" <> _, "OTP-17" <> _), do: false
  defp build_erlang_ref?("debian", "buster-" <> _, "OTP-18" <> _), do: false
  defp build_erlang_ref?("debian", "buster-" <> _, "OTP-19" <> _), do: false
  defp build_erlang_ref?("ubuntu", "focal-" <> _, "OTP-17" <> _), do: false
  defp build_erlang_ref?("ubuntu", "focal-" <> _, "OTP-18" <> _), do: false
  defp build_erlang_ref?("ubuntu", "focal-" <> _, "OTP-19" <> _), do: false
  defp build_erlang_ref?(_os, _os_version, _ref), do: true

  defp build_erlang_ref?("arm64", "ubuntu", "trusty-" <> _, "OTP-17" <> _), do: false
  defp build_erlang_ref?("arm64", "ubuntu", "trusty-" <> _, "OTP-18" <> _), do: false
  defp build_erlang_ref?("arm64", "debian", "jessie-" <> _, _ref), do: false
  defp build_erlang_ref?(_arch, _os, _os_version, _ref), do: true

  defp erlang_refs() do
    "erlang/otp"
    |> Bob.GitHub.fetch_repo_refs()
    |> Enum.map(fn {ref_name, _ref} -> ref_name end)
  end

  def erlang_tags() do
    Enum.flat_map(@archs, &erlang_tags/1)
  end

  def erlang_tags(arch) do
    "hexpm/erlang-#{arch}"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Enum.map(fn {tag, [^arch]} ->
      [erlang, os, os_version] = Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)
      key = {erlang, os, os_diff(os, os_version), arch}
      value = {erlang, os, os_version, arch}
      {key, value}
    end)
  end

  def elixir() do
    tags = elixir_tags()
    expected_tags = expected_elixir_tags()

    Enum.each(diff(expected_tags, tags), fn {elixir, erlang, os, os_version, arch} ->
      Bob.Queue.add({Bob.Job.BuildDockerElixir, arch}, [elixir, erlang, os, os_version])
    end)
  end

  def expected_elixir_tags() do
    # TODO: Base this on builds.txt instead

    refs = elixir_refs()

    tags =
      for ref <- refs,
          "v" <> elixir = ref,
          arch <- @archs,
          {_, {erlang, os, os_version, ^arch}} <- erlang_tags(arch),
          not skip_elixir?(elixir, erlang),
          compatible_elixir_and_erlang?(elixir, erlang),
          key = {elixir, erlang, os, os_diff(os, os_version), arch},
          value = {elixir, erlang, os, os_version, arch},
          do: {key, value}

    tags
    |> Enum.sort(:desc)
    |> Enum.uniq_by(fn {key, _value} -> key end)
    |> Enum.map(fn {_key, value} -> {value, value} end)
  end

  defp elixir_refs() do
    "elixir-lang/elixir"
    |> Bob.GitHub.fetch_repo_refs()
    |> Enum.map(fn {ref_name, _ref} -> ref_name end)
    |> Enum.filter(&build_elixir_ref?/1)
  end

  def elixir_tags() do
    Enum.flat_map(@archs, &elixir_tags/1)
  end

  def elixir_tags(arch) do
    "hexpm/elixir-#{arch}"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Enum.map(fn {tag, [^arch]} ->
      [elixir, erlang, os, os_version] =
        Regex.run(@elixir_tag_regex, tag, capture: :all_but_first)

      key = {elixir, erlang, os, os_version, arch}
      {key, key}
    end)
  end

  defp build_elixir_ref?("v0." <> _), do: false

  defp build_elixir_ref?("v" <> version) do
    match?({:ok, %Version{pre: []}}, Version.parse(version))
  end

  defp build_elixir_ref?(_), do: false

  defp diff(expected, current) do
    current = MapSet.new(current, fn {key, _value} -> key end)

    Enum.flat_map(expected, fn {key, value} ->
      if MapSet.member?(current, key) do
        []
      else
        [value]
      end
    end)
    |> Enum.sort()
  end

  defp compatible_elixir_and_erlang?(elixir, erlang) do
    compatibles =
      case elixir do
        "1.0.5" -> ["17", "18"]
        "1.0." <> _ -> ["17"]
        "1.1." <> _ -> ["17", "18"]
        "1.2." <> _ -> ["18"]
        "1.3." <> _ -> ["18", "19"]
        "1.4.5" -> ["18", "19", "20"]
        "1.4." <> _ -> ["18", "19"]
        "1.5." <> _ -> ["18", "19", "20"]
        "1.6.6" -> ["19", "20", "21"]
        "1.6." <> _ -> ["19", "20"]
        "1.7." <> _ -> ["19", "20", "21", "22"]
        "1.8." <> _ -> ["20", "21", "22"]
        "1.9." <> _ -> ["20", "21", "22"]
        "1.10.0" -> ["21", "22"]
        "1.10.1" -> ["21", "22"]
        "1.10.2" -> ["21", "22"]
        "1.10." <> _ -> ["21", "22", "23"]
      end

    Enum.any?(compatibles, &String.starts_with?(erlang, &1))
  end

  defp skip_elixir?(elixir, erlang) when elixir in ~w(1.0.0 1.0.1 1.0.2 1.0.3) do
    String.starts_with?(erlang, "17.5")
  end

  defp skip_elixir?(_elixir, _erlang) do
    false
  end

  def manifests() do
    erlang_tags = group_archs(erlang_tags())
    erlang_manifest_tags = erlang_manifest_tags()
    diff_manifests("erlang", erlang_tags, erlang_manifest_tags)

    elixir_tags = group_archs(elixir_tags())
    elixir_manifest_tags = elixir_manifest_tags()
    diff_manifests("elixir", elixir_tags, elixir_manifest_tags)
  end

  def erlang_manifest_tags() do
    "hexpm/erlang"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Map.new(fn {tag, archs} ->
      [erlang, os, os_version] = Regex.run(@erlang_tag_regex, tag, capture: :all_but_first)
      {{erlang, os, os_version}, archs}
    end)
  end

  def elixir_manifest_tags() do
    "hexpm/elixir"
    |> Bob.DockerHub.fetch_repo_tags()
    |> Map.new(fn {tag, archs} ->
      [elixir, erlang, os, os_version] =
        Regex.run(@elixir_tag_regex, tag, capture: :all_but_first)

      {{elixir, erlang, os, os_version}, archs}
    end)
  end

  defp group_archs(enum) do
    enum
    |> Enum.map(fn {_key, value} -> value end)
    |> Enum.group_by(
      &Tuple.delete_at(&1, tuple_size(&1) - 1),
      &elem(&1, tuple_size(&1) - 1)
    )
  end

  defp diff_manifests(kind, expected, current) do
    Enum.each(Enum.sort(expected), fn {key, expected_archs} ->
      if expected_archs -- Map.get(current, key, []) != [] do
        Bob.Queue.add(Bob.Job.DockerManifest, [kind, key, expected_archs])
      end
    end)
  end

  defp os_diff("alpine", version) do
    version = Version.parse!(version)
    {version.major, version.minor}
  end

  defp os_diff(os, version) when os in ["ubuntu", "debian"] do
    [version, _] = String.split(version, "-", parts: 2)
    version
  end
end
