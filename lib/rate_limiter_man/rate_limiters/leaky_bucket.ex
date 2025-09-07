defmodule RateLimiterMan.RateLimiters.LeakyBucket do
  @moduledoc """
  A leaky-bucket rate limiter that processes requests at a fixed rate (e.g. 1 request per second).
  """

  @behaviour RateLimiterMan

  use GenServer
  alias RateLimiterMan
  require Logger

  def child_spec(arg) do
    %{
      id: RateLimiterMan.get_instance_name(arg[:config_key]),
      start: {RateLimiterMan.RateLimiters.LeakyBucket, :start_link, [arg]}
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts,
      name: RateLimiterMan.get_instance_name(opts[:config_key])
    )
  end

  ## Client API

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
  def init(%{otp_app: otp_app, config_key: config_key} = _init_arg) do
    state = %{
      request_queue: :queue.new(),
      request_queue_size: 0,
      request_queue_poll_rate: RateLimiterMan.calculate_refresh_rate(otp_app, config_key),
      send_after_ref: nil
    }

    {:ok, state, {:continue, :initial_timer}}
  end

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
