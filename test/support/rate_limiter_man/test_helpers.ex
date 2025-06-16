defmodule RateLimiterMan.TestHelpers do
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias RateLimiterMan.TestConstants, as: TC

  @doc """
  Assert that a `task_supervisor_pid` process has the expected `children`, then return its PID.
  """
  @spec assert_task_supervisor_has_children(pid(), [pid()]) :: pid()
  def assert_task_supervisor_has_children(task_supervisor_pid, children) do
    assert Task.Supervisor.children(task_supervisor_pid) == children

    task_supervisor_pid
  end

  @doc "Assert that a TaskSupervisor process has been started, then return its PID."
  @spec assert_task_supervisor_started(pid()) :: pid()
  def assert_task_supervisor_started(task_supervisor_pid) do
    assert Process.alive?(task_supervisor_pid) == true

    task_supervisor_pid
  end

  def get_max_requests_per_second_from_rate_limiter_config(otp_app, config_key) do
    Application.fetch_env!(otp_app, config_key)
    |> Keyword.fetch!(:rate_limiter_max_requests_per_second)
  end

  def get_rate_limiter_algorithm_from_rate_limiter_config(otp_app, config_key) do
    Application.fetch_env!(otp_app, config_key) |> Keyword.fetch!(:rate_limiter_algorithm)
  end

  @doc """
  Add a unique rate limiter config to the global application state, then return the config key for
  the new config.

  This function has an `on_exit/1` call to ensure that the config item is removed from the global
  application state after the test has completed.

  ## Options

  Any options are passed as values to their respective rate limiter config keys (e.g.
  `:rate_limiter_algorithm`, `:rate_limiter_max_requests_per_second`).
  """
  @spec put_rate_limiter_config(keyword()) :: atom()
  def put_rate_limiter_config(opts \\ []) do
    config_key = get_random_config_key()

    Application.put_env(TC.otp_app(), config_key,
      rate_limiter_algorithm:
        Keyword.get(opts, :rate_limiter_algorithm, RateLimiterMan.LeakyBucket),
      rate_limiter_max_requests_per_second:
        Keyword.get(opts, :rate_limiter_max_requests_per_second, 100)
    )

    on_exit(fn -> Application.delete_env(TC.otp_app(), config_key) end)

    config_key
  end

  @doc "A setup function that adds a rate limiter config to the context map's `:config_keys`."
  @spec setup_rate_limiter_config(map(), keyword()) :: %{config_keys: [atom()]}
  def setup_rate_limiter_config(context, opts \\ []) do
    config_keys = context[:config_keys] || []
    config_key = put_rate_limiter_config(opts)

    %{config_keys: config_keys ++ [config_key]}
  end

  @doc "A setup helper function that starts a rate limiter TaskSupervisor."
  @spec setup_task_supervisor_and_rate_limiter(map(), keyword()) :: %{config_keys: list()}
  def setup_task_supervisor_and_rate_limiter(context, opts \\ []) do
    context = context || %{}
    initial_config_keys = context[:config_keys] || []

    config_key = put_rate_limiter_config(opts)

    children = [
      RateLimiterMan.new_task_supervisor(),
      RateLimiterMan.new_rate_limiter(TC.otp_app(), config_key)
    ]

    opts = [strategy: :one_for_one, name: RateLimiterMan.Supervisor]

    supervisor_spec = %{
      id: RateLimiterMan.Supervisor,
      start: {Supervisor, :start_link, [children, opts]}
    }

    {:ok, _supervisor_pid} = start_supervised(supervisor_spec)

    %{config_keys: initial_config_keys ++ [config_key]}
  end

  @doc "Start a rate limiter TaskSupervisor, then return its PID."
  @spec start_task_supervisor :: pid()
  def start_task_supervisor do
    task_supervisor_spec = RateLimiterMan.new_task_supervisor()

    {:ok, task_supervisor_pid} = start_supervised(task_supervisor_spec)

    task_supervisor_pid
  end

  defp get_random_config_key, do: String.to_atom("rate_limiter_#{System.unique_integer()}")
end
