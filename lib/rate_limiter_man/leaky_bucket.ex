defmodule RateLimiterMan.LeakyBucket do
  @moduledoc """
  A leaky-bucket rate limiter that processes requests at a fixed rate (e.g. 1 request per second).

  ## Required config keys

  - `:`

  ## Optional config keys

  - `:rate_limiter_logger_level` - Determines what type of Logger statement to generate when a
  request is pushed to or popped from the queue. (default: `nil`)
    - Examples: `nil` (Logging disabled), `:debug`, `:info`

  > #### Warning {: .warning}
  >
  > The log statements may contain sensitive data (e.g. API keys). There is currently no way of
  > modifying the contents of the Logger statement.
  """

  @behaviour RateLimiterMan

  use GenServer
  alias RateLimiterMan
  require Logger

  def child_spec(arg) do
    %{
      id: RateLimiterMan.get_instance_name(arg[:config_key]),
      start: {RateLimiterMan.LeakyBucket, :start_link, [arg]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts,
      name: RateLimiterMan.get_instance_name(opts[:config_key])
    )
  end

  @impl true
  def init(%{otp_app: otp_app, config_key: config_key} = _init_arg) do
    state = %{
      request_queue: :queue.new(),
      request_queue_size: 0,
      request_queue_poll_rate: RateLimiterMan.calculate_refresh_rate(otp_app, config_key),
      send_after_ref: nil
    }

    {:ok, state, {:continue, :initial_timer}}
  end

  ## Client API

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

  Get a reference to the desired rate limiter for the following examples:

      iex> rate_limiter = RateLimiterMan.get_rate_limiter(:your_project, YourProject.SomeApi)

  Make a request with the rate limiter:

      iex> rate_limiter.make_request(
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

      iex> rate_limiter.make_request(
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
  @impl true
  def make_request(otp_app, config_key, request_handler, opts \\ []) do
    opts =
      case Keyword.get(opts, :logger_level, :not_in_opts) do
        :not_in_opts ->
          # Fall back to configured logger level
          opts
          |> Keyword.put(
            :logger_level,
            RateLimiterMan.get_config(otp_app, config_key, :rate_limiter_logger_level)
          )

        _ ->
          opts
      end

    GenServer.cast(
      RateLimiterMan.get_instance_name(config_key),
      {:enqueue_request, request_handler, opts}
    )
  end

  ## Server API

  @impl true
  def handle_continue(:initial_timer, state) do
    {:noreply, %{state | send_after_ref: schedule_timer(state.request_queue_poll_rate)}}
  end

  @impl true
  def handle_cast({:enqueue_request, request_handler, opts}, state) do
    maybe_log(
      opts[:logger_level],
      "Adding a request to the rate limiter queue: #{inspect(request_handler)}"
    )

    updated_queue = :queue.in({request_handler, opts}, state.request_queue)
    new_queue_size = state.request_queue_size + 1

    {:noreply, %{state | request_queue: updated_queue, request_queue_size: new_queue_size}}
  end

  @impl true
  def handle_info(:pop_from_request_queue, %{request_queue_size: 0} = state) do
    # There is no work to do since the queue size is zero, so schedule the next timer
    {:noreply, %{state | send_after_ref: schedule_timer(state.request_queue_poll_rate)}}
  end

  def handle_info(:pop_from_request_queue, state) do
    {{:value, {request_handler, opts}}, new_request_queue} =
      :queue.out(state.request_queue)

    # Validate options
    if not Enum.all?([opts[:send_response_to_pid], opts[:request_id]], &(not is_nil(&1))) and
         Enum.any?([opts[:send_response_to_pid], opts[:request_id]], &(not is_nil(&1))) do
      raise """
      if either option `send_response_to_pid` or `request_id` is non-nil, then both options must
      be non-nil
      """
    end

    {logger_level, opts} = Keyword.pop(opts, :logger_level)

    maybe_log(
      logger_level,
      "Popping a request from the rate limiter queue: #{inspect(request_handler)}"
    )

    Task.Supervisor.async_nolink(RateLimiterMan.TaskSupervisor, fn ->
      {req_module, req_function, req_args} = request_handler
      response = apply(req_module, req_function, req_args)

      if not is_nil(opts[:response_handler]) do
        {resp_module, resp_function} = opts[:response_handler]
        apply(resp_module, resp_function, [response])
      end

      if not is_nil(opts[:send_response_to_pid]) do
        send(
          opts[:send_response_to_pid],
          {:ok, %{request_id: opts[:request_id], response: response}}
        )
      end
    end)

    {:noreply,
     %{
       state
       | request_queue: new_request_queue,
         send_after_ref: schedule_timer(state.request_queue_poll_rate),
         request_queue_size: state.request_queue_size - 1
     }}
  end

  def handle_info({ref, _result}, state) do
    Process.demonitor(ref, [:flush])

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp maybe_log(nil, _message), do: nil
  defp maybe_log(level, message), do: Logger.log(level, [message])

  defp schedule_timer(queue_poll_rate),
    do: Process.send_after(self(), :pop_from_request_queue, queue_poll_rate)
end
