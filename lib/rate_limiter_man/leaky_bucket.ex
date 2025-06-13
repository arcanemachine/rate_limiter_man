defmodule RateLimiterMan.LeakyBucket do
  @moduledoc """
  A leaky-bucket rate limiter that processes requests at a fixed rate (e.g. 1 request per second).

  > #### TODO {: .warning}
  >
  > Add more documentation.
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

  ## -- Client facing function --

  @doc """
  Call a function using the rate limiter.

  ## Receiving a response

  To receive a response from the rate limiter, you must pass in the following `opts`:

    - `from` - The PID of the process that will receive the response (e.g. `self()`)
    - `request_id` - A unique identifier (e.g. a random number, or the `x-request-id` header)

  Then, add a receive block where you want the response to be received:

      iex> receive do
      ...>   {:ok, %{request_id: request_id, resp: resp}} when request_id == your_request_id ->
      ...>     resp
      ...> after
      ...>   30_000 -> {:error, :gateway_timeout}
      ...> end

  ## Examples

  Get a reference to the desired rate limiter for the following examples:

      iex> rate_limiter = RateLimiterMan.get_rate_limiter(YourProject.RateLimiter)

  Make a request using the rate limiter:

      iex> rate_limiter.make_request(
      ...>   _otp_app = :your_project,
      ...>   _config_key = YourProject.RateLimiter,
      ...>   _request_handler = {IO, :puts, ["Hello world!"]}
      ...> )
      :ok

  Or, make a request using the rate limiter, and have the rate limiter send the response back to
  the caller via message passing:

      # Generate a unique request ID
      iex> request_id = System.unique_integer()

      # Make the request
      iex> rate_limiter.make_request(
      ...>   _otp_app = :your_project,
      ...>   _config_key = YourProject.RateLimiter,
      ...>   _request_handler = {String, :duplicate, ["Hello world! ", 2]},
      ...>   _response_handler = nil,
      ...>   from: self(),
      ...>   request_id: unique_request_id
      ...> )
      :ok

      # Receive the response for further processing
      iex> receive do
      ...>   {:ok, %{request_id: request_id, resp: resp}} when request_id == unique_request_id ->
      ...>     resp
      ...> after
      ...>   30_000 -> {:error, :gateway_timeout}
      ...> end
      "Hello world! Hello world! "
  """
  @impl true
  def make_request(otp_app, config_key, request_handler, response_handler \\ nil, opts \\ [])

  def make_request(otp_app, config_key, request_handler, nil, opts) do
    make_request(
      otp_app,
      config_key,
      request_handler,
      {RateLimiterMan, :skip_response_handler},
      opts
    )
  end

  def make_request(_otp_app, config_key, request_handler, response_handler, opts) do
    GenServer.cast(
      RateLimiterMan.get_instance_name(config_key),
      {:enqueue_request, request_handler, response_handler, opts}
    )
  end

  ## -- Server Callbacks --

  @impl true
  def handle_continue(:initial_timer, state) do
    {:noreply, %{state | send_after_ref: schedule_timer(state.request_queue_poll_rate)}}
  end

  @impl true
  def handle_cast({:enqueue_request, request_handler, response_handler, opts}, state) do
    Logger.debug("Adding a request to the rate limiter queue: #{inspect(request_handler)}")

    updated_queue = :queue.in({request_handler, response_handler, opts}, state.request_queue)
    new_queue_size = state.request_queue_size + 1

    {:noreply, %{state | request_queue: updated_queue, request_queue_size: new_queue_size}}
  end

  @impl true
  def handle_info(:pop_from_request_queue, %{request_queue_size: 0} = state) do
    # There is no work to do since the queue size is zero, so schedule the next timer
    {:noreply, %{state | send_after_ref: schedule_timer(state.request_queue_poll_rate)}}
  end

  def handle_info(:pop_from_request_queue, state) do
    {{:value, {request_handler, response_handler, opts}}, new_request_queue} =
      :queue.out(state.request_queue)

    Logger.debug("Popping a request from the rate limiter queue: #{inspect(request_handler)}")

    Task.Supervisor.async_nolink(RateLimiterMan.TaskSupervisor, fn ->
      {req_module, req_function, req_args} = request_handler
      {resp_module, resp_function} = response_handler

      response = apply(req_module, req_function, req_args)
      apply(resp_module, resp_function, [response])

      if sender_pid = opts[:from] do
        # Send the response to the specified process
        send(sender_pid, {:ok, %{request_id: Keyword.fetch!(opts, :request_id), resp: response}})
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

  defp schedule_timer(queue_poll_rate) do
    Process.send_after(self(), :pop_from_request_queue, queue_poll_rate)
  end
end
