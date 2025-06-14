defmodule RateLimiterMan.TestHelpers do
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias RateLimiterMan.TestConstants, as: TC

  @doc """
  Add a unique rate limiter config to the global application state, then return the config key for
  the new config.

  This function has an `on_exit/1` call to ensure that the config item is removed from the global
  application state after the test has completed.
  """
  @spec add_rate_limiter_config :: atom()
  def add_rate_limiter_config do
    config_key = get_random_config_key()

    Application.put_env(TC.otp_app(), config_key, TC.rate_limiter_config_example())

    on_exit(fn -> Application.delete_env(TC.otp_app(), config_key) end)

    config_key
  end

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

  @doc "A setup helper function that starts a rate limiter TaskSupervisor."
  @spec setup_task_supervisor_and_rate_limiter(map()) :: %{config_keys: list()}
  def setup_task_supervisor_and_rate_limiter(context) do
    initial_config_keys = context[:config_keys] || []
    config_key = add_rate_limiter_config()

    children = [
      RateLimiterMan.add_task_supervisor(),
      RateLimiterMan.add_rate_limiter(TC.otp_app(), config_key)
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
    task_supervisor_spec = RateLimiterMan.add_task_supervisor()

    {:ok, task_supervisor_pid} = start_supervised(task_supervisor_spec)

    task_supervisor_pid
  end

  @doc "A setup function that adds a rate limiter config to the context map's `:config_keys`."
  @spec setup_rate_limiter_config(map()) :: %{config_keys: [atom()]}
  def setup_rate_limiter_config(context) do
    config_keys = context[:config_keys] || []
    config_key = add_rate_limiter_config()

    %{config_keys: config_keys ++ [config_key]}
  end

  defp get_random_config_key, do: String.to_atom("rate_limiter_#{System.unique_integer()}")
end
