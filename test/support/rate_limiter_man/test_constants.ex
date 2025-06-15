defmodule RateLimiterMan.TestConstants do
  @moduledoc "Constants used in testing."

  def otp_app, do: :rate_limiter_man

  def request_handler_example, do: {Enum, :join, [["Hello", "world!"], " "]}

  def request_handler_example_response do
    request_handler_example()
    |> then(fn {module, function_name, args} -> apply(module, function_name, args) end)
  end
end
