defmodule RateLimiterMan do
  @moduledoc """
  A rate limiter implementation, based heavily on a blog post by [Alex
  Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

  This package handles logic for limiting the rate at which HTTP requests are sent.

  > #### TODO {: .warning}
  >
  > Add more documentation.
  """

  @type response_handler :: tuple() | nil

  @callback make_request(atom(), tuple(), response_handler(), keyword()) :: :ok
  def make_request(otp_app, config_key, request_handler, response_handler, opts \\ []) do
    get_rate_limiter(otp_app, config_key).make_request(request_handler, response_handler, opts)
  end

  def calculate_refresh_rate(otp_app, config_key) do
    max_requests_per_second = get_max_requests_per_second(otp_app, config_key)

    floor(:timer.seconds(1) / max_requests_per_second)
  end

  def get_rate_limiter(otp_app, config_key),
    do: get_rate_limiter_config(otp_app, config_key, :rate_limiter)

  def get_max_requests_per_second(otp_app, config_key),
    do: get_rate_limiter_config(otp_app, config_key, :rate_limiter_max_requests_per_second)

  def receive_response(unique_request_id, timeout \\ 15_000) do
    receive do
      {:ok, %{request_id: request_id, response: response}} when request_id == unique_request_id ->
        response
    after
      timeout -> {:error, :timeout}
    end
  end

  def skip_response_handler(response), do: fn -> response end

  @doc "Get the process name for a rate limiter instance by its `config_key`."
  def get_instance_name(config_key),
    do: String.to_atom("#{Macro.underscore(config_key)}_leaky_bucket_rate_limiter")

  def start_rate_limiter(otp_app, config_key),
    do: {get_rate_limiter(otp_app, config_key), %{otp_app: otp_app, config_key: config_key}}

  def start_task_supervisor, do: {Task.Supervisor, name: RateLimiterMan.TaskSupervisor}

  defp get_rate_limiter_config(otp_app, config_key, subkey),
    do: Application.fetch_env!(otp_app, config_key) |> Keyword.fetch!(subkey)
end
