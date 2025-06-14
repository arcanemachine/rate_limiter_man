defmodule RateLimiterMan.TestConstants do
  @moduledoc "Constants used in testing."

  def otp_app, do: :rate_limiter_man

  def rate_limiter_config_example do
    [
      rate_limiter_algorithm: RateLimiterMan.LeakyBucket,
      rate_limiter_max_requests_per_second: 100
    ]
  end

  def request_handler_example, do: {Enum, :join, [["Hello", "world!"], " "]}

  def request_handler_example_response do
    request_handler_example()
    |> then(fn {module, function_name, args} -> apply(module, function_name, args) end)
  end
end
