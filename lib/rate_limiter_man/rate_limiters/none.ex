defmodule RateLimiterMan.RateLimiters.None do
  @moduledoc """
  This module acts as a no-op that bypasses any rate limiting.

  > #### Warning {: .warning}
  >
  > This algorithm is only intended for temporary usage, and will emit a `Logger` warning on each
  > request. If you want to permanently disable a rate limiter, it should be removed from your
  > project's supervision tree.
  """

  @behaviour RateLimiterMan

  require Logger

  def child_spec(arg) do
    Logger.warning("The #{inspect(arg[:config_key])} rate limiter has been disabled via config.")

    %{
      id: RateLimiterMan.get_instance_name(arg[:config_key]),
      start: {RateLimiterMan.RateLimiters.None, :start_link, [arg]}
    }
  end

  def start_link(_opts), do: :ignore

  @impl true
  def make_request(_otp_app, _config_key, {req_module, req_function, req_args}, opts \\ []) do
    Logger.warning("Bypassing the rate limiter for this request...")

    # Validate options
    if not Enum.all?([opts[:send_response_to_pid], opts[:request_id]], &(not is_nil(&1))) and
         Enum.any?([opts[:send_response_to_pid], opts[:request_id]], &(not is_nil(&1))) do
      raise """
      if either option `send_response_to_pid` or `request_id` is non-nil, then both options must
      be non-nil
      """
    end

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
  end
end
