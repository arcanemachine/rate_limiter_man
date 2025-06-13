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

  ## Handling the response

  The response may be handled in the following ways:
    - Send the response to a process (e.g. the process that called the rate limiter)
    - Handle the response as an async task
    - Do nothing with the response

  ### Send the response to a process

  To receive a response from the rate limiter, you must pass in the following `opts`:

  - `:send_response_to_pid` - The process that will receive the response (e.g. `self()`)

  - `:request_id` - A unique identifier for the request (e.g. a random number, or an
  `x-request-id` header)

  Then, add a receive block where you want the response to be received:

      iex> receive do
      ...>   {:ok, %{request_id: request_id, resp: resp}} when request_id == your_request_id ->
      ...>     resp
      ...> after
      ...>   30_000 -> {:error, :gateway_timeout}
      ...> end

  ### Handle the response as an async task

  To handle the response as an async task, you must pass in the following `opts`:

  - `:async_response_handler` - A 2-item tuple that contains the name of the module, and an atom
  name of the 1-arity function that will handle the response.
    - Example: `{YourProject.SomeApi, :handle_response}`

  ### Do nothing

  To do nothing with the response, simply omit any of the options used in the previous handler
  strategies.

  ## Examples

  Get a reference to the desired rate limiter for the following examples:

      iex> rate_limiter = RateLimiterMan.get_rate_limiter(YourProject.RateLimiter)

  Make a request with the rate limiter:

      iex> rate_limiter.make_request(
      ...>   _otp_app = :your_project,
      ...>   _config_key = YourProject.RateLimiter,
      ...>   _request_handler = {IO, :puts, ["Hello world!"]}
      ...> )
      :ok

  ### Send the response to a process

  Make a request using the rate limiter, and have the rate limiter send the response back to the
  caller via message passing:

  Generate a unique request ID:

      iex> request_id = System.unique_integer()

  Make the request:

      iex> rate_limiter.make_request(
      ...>   _otp_app = :your_project,
      ...>   _config_key = YourProject.RateLimiter,
      ...>   _request_handler = {String, :duplicate, ["Hello world! ", 2]},
      ...>   send_response_to_pid: self(),
      ...>   request_id: unique_request_id
      ...> )
      :ok

  Receive the response from the rate limiter:

      iex> response = RateLimiterMan.receive_response(request_id)
      "Hello world! Hello world! "
  """
  @impl true
  def make_request(config_key, request_handler, opts \\ []) do
    GenServer.cast(
      RateLimiterMan.get_instance_name(config_key),
      {:enqueue_request, request_handler, opts}
    )
  end

  ## -- Server Callbacks --

  @impl true
  def handle_continue(:initial_timer, state) do
    {:noreply, %{state | send_after_ref: schedule_timer(state.request_queue_poll_rate)}}
  end

  @impl true
  def handle_cast({:enqueue_request, request_handler, opts}, state) do
    Logger.debug("Adding a request to the rate limiter queue: #{inspect(request_handler)}")

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

    # Sanity check: Ensure that request ID is present if respond-to PID is given
    if not is_nil(opts[:send_response_to_pid]) and is_nil(opts[:request_id]) do
      raise "request_id must be given if send_response_to_pid is given"
    end

    Logger.debug("Popping a request from the rate limiter queue: #{inspect(request_handler)}")

    Task.Supervisor.async_nolink(RateLimiterMan.TaskSupervisor, fn ->
      {req_module, req_function, req_args} = request_handler
      response = apply(req_module, req_function, req_args)

      if not is_nil(opts[:async_response_handler]) do
        {resp_module, resp_function} = opts[:async_response_handler]
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

  defp schedule_timer(queue_poll_rate) do
    Process.send_after(self(), :pop_from_request_queue, queue_poll_rate)
  end
end
