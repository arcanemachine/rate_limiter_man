defmodule RateLimiterMan.TestHelpers do
  import ExUnit.Callbacks

  @constants %{
    otp_app: :rate_limiter_man,
    rate_limiter_config_example: [
      rate_limiter_algorithm: RateLimiterMan.LeakyBucket,
      rate_limiter_max_requests_per_second: 1000
    ],
    request_handler: {Enum, :join, [["Hello", "world!"], " "]},
    request_handler_response: "Hello world!"
  }

  @doc "Keys: #{inspect(Map.keys(@constants))}"
  def constants(), do: @constants

  def setup_rate_limiter_config(context) do
    config_keys = context[:config_keys] || []
    config_key = add_rate_limiter_config()

    RateLimiterMan.TestHelpers.constants()

    %{config_keys: config_keys ++ [config_key]}
  end

  def add_rate_limiter_config do
    config_key = String.to_atom("rate_limiter_#{System.unique_integer()}")

    Application.put_env(@constants.otp_app, config_key, @constants.rate_limiter_config_example)

    on_exit(fn -> Application.delete_env(@constants.otp_app, config_key) end)

    config_key
  end
end
