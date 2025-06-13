defmodule RateLimiterMan do
  @moduledoc """
  A rate limiter implementation, based heavily on a blog post by [Alex
  Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

  This package handles logic for limiting the rate at which HTTP requests are sent.
  """

  @callback make_request(atom(), atom(), tuple(), keyword()) :: :ok

  def make_request(otp_app, config_key, request_handler, opts \\ []) do
    rate_limiter = get_rate_limiter(otp_app, config_key)

    rate_limiter.make_request(otp_app, config_key, request_handler, opts)
  end

  def calculate_refresh_rate(otp_app, config_key) do
    max_requests_per_second = get_max_requests_per_second(otp_app, config_key)

    floor(:timer.seconds(1) / max_requests_per_second)
  end

  def get_rate_limiter(otp_app, config_key),
    do: get_config(otp_app, config_key, :rate_limiter_algorithm)

  def get_max_requests_per_second(otp_app, config_key),
    do: fetch_config!(otp_app, config_key, :rate_limiter_max_requests_per_second)

  @doc "Receive a response from a rate limiter."
  def receive_response(unique_request_id, timeout \\ :timer.seconds(15)) do
    receive do
      {:ok, %{request_id: request_id, response: response}} when request_id == unique_request_id ->
        response
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc "Get the process name for a rate limiter instance by its `config_key`."
  def get_instance_name(config_key),
    do: String.to_atom("#{Macro.underscore(config_key)}_leaky_bucket_rate_limiter")

  def start_rate_limiter(otp_app, config_key),
    do: {get_rate_limiter(otp_app, config_key), %{otp_app: otp_app, config_key: config_key}}

  def start_task_supervisor, do: {Task.Supervisor, name: RateLimiterMan.TaskSupervisor}

  def get_config(otp_app, config_key, subkey, default \\ nil),
    do: Application.fetch_env!(otp_app, config_key) |> Keyword.get(subkey, default)

  def fetch_config!(otp_app, config_key, subkey),
    do: Application.fetch_env!(otp_app, config_key) |> Keyword.fetch!(subkey)
end
