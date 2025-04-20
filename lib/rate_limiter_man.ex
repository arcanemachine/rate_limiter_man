defmodule RateLimiterMan do
  @moduledoc """
  A rate limiter implementation, based heavily on a blog post by [Alex
  Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

  This package handles logic for limiting the rate at which HTTP requests are sent.

  > #### TODO {: .warning}
  >
  > Add more documentation.
  """

  @type response_handler :: tuple() | :no_response_handler

  @callback make_request(atom(), tuple(), response_handler(), keyword()) :: :ok
  def make_request(api_provider, request_handler, response_handler, opts \\ []) do
    get_rate_limiter(api_provider).make_request(request_handler, response_handler, opts)
  end

  def skip_response_handler(res), do: fn -> res end

  def get_rate_limiter(api_provider),
    do: get_rate_limiter_config(api_provider, :rate_limiter)

  def get_max_requests_per_second(api_provider),
    do: get_rate_limiter_config(api_provider, :rate_limiter_max_requests_per_second)

  def calculate_refresh_rate(max_requests_per_second),
    do: floor(:timer.seconds(1) / max_requests_per_second)

  defp get_rate_limiter_config(api_provider, config_key) do
    api_provider_config = Application.fetch_env!(:resort_indexer, api_provider)

    Keyword.fetch!(api_provider_config, config_key)
  end
end
