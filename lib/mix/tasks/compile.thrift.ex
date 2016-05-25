defmodule Mix.Tasks.Compile.Thrift do
  use Mix.Task

  @moduledoc """
  Generate Erlang source files from .thrift schema files.

  When this task runs, it first checks the modification times of all source
  files that were generated by the set of .thrift files.  If the generated
  files are older than the .thrift file that generated them, this task will
  skip regenerating them.

  ## Command line options

    * `--force` - forces compilation regardless of modification times

  ## Configuration

    * `:thrift_files` - list of .thrift schema files to compile

    * `:thrift_output` - output directory into which the generated Erlang
      source file will be generated. Defaults to `"src"`.

    * `:thrift_options` - list of additional options that will be passed to
      the Thrift compiler.

    * `:thrift_version` - thrift compiler `Version` requirement
  """

  @spec run(OptionParser.argv) :: :ok | :noop
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])
    force        = opts[:force]

    project        = Mix.Project.config
    thrift_files   = project[:thrift_files] || []
    thrift_options = project[:thrift_options] || []
    thrift_version = project[:thrift_version]
    output_dir     = project[:thrift_output] || "src"

    stale_files = Enum.filter(thrift_files, fn file ->
      force || stale?(file, output_dir)
    end)

    if(thrift_version && !Enum.empty?(stale_files)) do
      unless(Version.match?(v = get_thrift_version, thrift_version)) do
        Mix.raise "Unsupported Thrift version #{v} (requires #{thrift_version})"
      end
    end

    unless Enum.empty?(stale_files) do
      File.mkdir_p!(output_dir)
      options = build_options(output_dir, thrift_options)
      Enum.each stale_files, &generate(&1, options)
    end
  end

  defp get_thrift_version do
    case System.cmd("thrift", ~w[-version]) do
      {s, 0} -> hd(Regex.run(~r/\b(\d+\.\d+\.\d+)\b/, s, capture: :first) || [])
      {_, e} -> Mix.raise "Failed to execute `thrift -version` (error #{e})"
    end
  end

  defp get_generated_files(thrift_file, output_dir) do
    basename = Path.basename(thrift_file, ".thrift")
    pattern  = basename <> "_{constants,thrift,types}.{erl,hrl}"
    Mix.Utils.extract_files([output_dir], pattern)
  end

  defp stale?(thrift_file, output_dir) do
    targets = get_generated_files(thrift_file, output_dir)
    Enum.empty?(targets) || Mix.Utils.stale?([thrift_file], targets)
  end

  defp build_options(output_dir, user_options) do
    opts = ~w[--out] ++ [output_dir]
    unless Enum.member?(user_options, "--gen") do
      opts = opts ++ ~w[--gen erl]
    end
    opts ++ user_options
  end

  defp generate(thrift_file, options) do
    args = options ++ [thrift_file]
    case System.cmd("thrift", args) do
      {_, 0} -> Mix.shell.info "Compiled #{thrift_file}"
      {_, e} -> Mix.shell.error "Failed to compile #{thrift_file} (error #{e})"
    end
  end
end
