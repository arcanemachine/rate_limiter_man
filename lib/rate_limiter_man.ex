defmodule RateLimiterMan do
  @moduledoc """
  A rate limiter implementation, based heavily on a blog post by [Alex
  Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

  This package handles logic for limiting the rate at which HTTP requests are sent.
  """

  @callback make_request(atom(), atom(), tuple(), keyword()) :: :ok

  @doc false
  def calculate_refresh_rate(otp_app, config_key) do
    max_requests_per_second = get_max_requests_per_second(otp_app, config_key)

    floor(:timer.seconds(1) / max_requests_per_second)
  end

  @doc false
  def fetch_config!(otp_app, config_key, subkey),
    do: Application.fetch_env!(otp_app, config_key) |> Keyword.fetch!(subkey)

  @doc false
  def get_config(otp_app, config_key, subkey, default \\ nil),
    do: Application.fetch_env!(otp_app, config_key) |> Keyword.get(subkey, default)

  @doc "Get the process name for a rate limiter instance by its `config_key`."
  def get_instance_name(config_key),
    do: String.to_atom("#{inspect(config_key)}_leaky_bucket_rate_limiter")

  def get_max_requests_per_second(otp_app, config_key),
    do: fetch_config!(otp_app, config_key, :rate_limiter_max_requests_per_second)

  @doc """
  Get the configured rate limiter for a given `otp_app` and `config_key`.

  ## Examples

      iex> RateLimiterMan.get_rate_limiter(:your_project, YourProject.SomeApi)
      RateLimiterMan.LeakyBucket
  """
  def get_rate_limiter(otp_app, config_key),
    do: get_config(otp_app, config_key, :rate_limiter_algorithm)

  @doc """
  Call a function via the rate limiter.

  The `otp_app` must be the atom name of your OTP application, as configured in `mix.exs` (e.g.
  `:your_project`).

  The `config_key` must be the namespace in your project's config where the rate limiter
  instance's config exists. This value must match the value that was used to create the rate
  limiter instance in your application's supervision tree.

  The `request_handler` is a tuple that is passed to `Kernel.apply/3`, which represents the
  function to be called by the rate limiter.

  The response may be handled in the following ways:
    - Send the response to a process (e.g. the process that called the rate limiter)
    - Handle the response as an async task
    - Do nothing with the response

  ## Options

  ### Generic options

  - `:logger_level` - Determines what type of Logger statement to generate when a
  request is pushed to or popped from the queue. If this option is not given, the config value
  for `:rate_limiter_logger_level` in the `config_key` will be used (default: `nil`)
    - Examples: `nil` (Logging disabled), `:debug`, `:info`

  > #### Warning {: .warning}
  >
  > The log statements may contain sensitive data (e.g. API keys). There is currently no way of
  > modifying the contents of the Logger statement.

  ### Send the response to a process

  To receive a response from the rate limiter, you must pass in the following `opts`:

  - `:send_response_to_pid` - The process that will receive the response (default: `nil`)
    - Examples: `self()`, `pid(0, 1, 2)`

  - `:request_id` - A unique identifier for the request, such as a random number or an
  `x-request-id` header) (default: `nil`)
    - Examples: `"abc"`, `123`

  ### Handle the response as an async task

  To handle the response by calling a function as an async task, you must pass in the following
  `opts`:

  - `:response_handler` - A 2-item tuple that contains the name of the module, and an atom name of
  the 1-arity function that will handle the response.
    - Example: `{YourProject.SomeApi, :handle_response}`

  ### Do nothing

  To do nothing with the response, just omit any of the options used in the previous handler
  strategies.

  ## Examples

  Make a request with the rate limiter:

      iex> RateLimiterMan.make_request(
      ...>   _otp_app = :your_project,
      ...>   _config_key = YourProject.RateLimiter,
      ...>   _request_handler = {IO, :puts, ["Hello world!"]}
      ...> )
      :ok

  ### Handle the response as an async task

  To handle the response as an async task, you must pass in the following `opts`:

  - `:response_handler` - A 2-item tuple that contains the name of the module, and the atom name
  of the 1-arity function that will handle the response.
    - Example: `{YourProject.SomeApi, :your_response_handler}`

  ### Send the response to a process

  Make a request using the rate limiter, and have the rate limiter send the response back to the
  caller via message passing:

  Generate a unique request ID:

      iex> request_id = System.unique_integer()

  Make the request:

      iex> RateLimiterMan.make_request(
      ...>   _otp_app = :your_project,
      ...>   _config_key = YourProject.RateLimiter,
      ...>   _request_handler = {Enum, :join, [["Hello", "world!"], " "]},
      ...>   send_response_to_pid: self(),
      ...>   request_id: request_id
      ...> )
      :ok

  Get the response back from the rate limiter:

      iex> response = RateLimiterMan.receive_response(request_id)
      "Hello world!"
  """
  def make_request(otp_app, config_key, request_handler, opts \\ []) do
    rate_limiter = get_rate_limiter(otp_app, config_key)

    rate_limiter.make_request(otp_app, config_key, request_handler, opts)
  end

  @doc """
  Add a rate limiter instance to your application's supervision tree.

  For more information on adding a rate limiter to your application, see the [README](README.md).

  > #### Tip {: .tip}
  >
  > The TaskSupervisor must be added to your supervision tree before adding any rate limiters.
  > For more information, see `RateLimiterMan.TaskSupervisor`.

  > #### Tip {: .tip}
  >
  > To temporarily disable a rate limiter when starting your application, change the config for
  > the `:rate_limiter_algorithm` to `RateLimiterMan.None`.

  ## Examples

  `lib/your_project/application.ex`
  ```elixir
  defmodule YourProject.Application do
    use Application

    @impl true
    def start(_type, _args) do
      children =
        [
          # Add the task supervisor before adding any rate limiters
          RateLimiterMan.TaskSupervisor,
          RateLimiterMan.new_rate_limiter(:your_project, YourProject.SomeApi),
          RateLimiterMan.new_rate_limiter(:your_project, YourProject.SomeOtherApi)
        ]

      opts = [strategy: :one_for_one, name: YourProject.Supervisor]

      Supervisor.start_link(children, opts)
    end
  end
  ```
  """
  def new_rate_limiter(otp_app, config_key),
    do: {get_rate_limiter(otp_app, config_key), %{otp_app: otp_app, config_key: config_key}}

  @doc "Receive a response from a rate limiter."
  def receive_response(unique_request_id, timeout \\ :timer.seconds(15)) do
    receive do
      {:ok, %{request_id: request_id, response: response}} when request_id == unique_request_id ->
        response
    after
      timeout -> {:error, :timeout}
    end
  end
end
