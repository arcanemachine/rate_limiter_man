# RateLimiterMan

A simple rate limiter implementation, adapted from [a blog post by Alex Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

> #### Warning {: .warning}
>
> This is probably not the most performant rate limiter out there, but it solves the need for which it was created: adding rate limiting to an application that receives responses from multiple third-party APIs, each of which has its own rate limiter instance/config.

This package supports multiple rate limiter instances in your application. Just follow the instructions, using a different config key for each rate limiter you want to add.

## Supported rate limiter algorithms

Currently, the only limiter algorithms implemented by this package are `RateLimiterMan.LeakyBucket`, and `RateLimiterMan.None` (a no-op used to temporarily bypass any configured rate limits).

## Getting started

### Install the package

Add this package to your list of dependencies in `mix.exs`, then run `mix deps.get`:

```elixir
{:rate_limiter_man, "0.3.0"}
```

### Configure your application

Add the config for your rate limiter instance:

`config/config.exs`
```elixir
import Config

config :your_project, YourProject.SomeApi,
  # Required items
  rate_limiter_algorithm: RateLimiterMan.LeakyBucket,
  rate_limiter_max_requests_per_second: 1
  # Optional items
  ## rate_limiter_logger_level: :debug # Enable logging when the rate limiter handles a request
```

> #### Tip {: .tip}
>
> Using the example above, the `otp_app` is `:your_project`, and the `config_key` is `YourProject.SomeApi`. These values are used to identify each rate limiter instance by the various functions in this package.

> #### Warning {: .warning}
>
> The log statements may contain sensitive data (e.g. API keys). There is currently no way of
> modifying the contents of the Logger statement.

> #### Tip {: .tip}
>
> To temporarily disable a rate limiter when starting your application, change the config for
> the `:rate_limiter_algorithm` to `RateLimiterMan.None`.

### Add the rate limiter to your application's supervision tree

`lib/your_project/application.ex`
```elixir
defmodule YourProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Add the task supervisor before adding any rate limiters. The task supervisor should only
        # be declared once
        RateLimiterMan.new_task_supervisor(),
        # Add the desired rate limiter(s). The OTP app name and config key must match the app name
        # and key used in your config file
        RateLimiterMan.new_rate_limiter(:your_project, YourProject.SomeApi),
        # RateLimiterMan.new_rate_limiter(:your_project, YourProject.SomeOtherApi),
        # RateLimiterMan.new_rate_limiter(:your_project, YourProject.YetAnotherApi)
      ]

    opts = [strategy: :one_for_one, name: YourProject.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
```

Now, the rate limiter process will start working when you start your application: `iex -S mix`

### Example: Use the rate limiter when making a request

Any function can be passed to the rate limiter. For simplicity, this example will not make any HTTP requests.

`lib/your_project/some_api.ex`
```
defmodule YourProject.SomeApi do
  def hello_world do
    request_id = System.unique_integer()

    # Make the request
    RateLimiterMan.make_request(
      _otp_app = :your_project,
      _config_key = YourProject.SomeApi,
      _request_handler = {Enum, :join, [["Hello", "world!"], " "]},
      send_response_to_pid: self(),
      request_id: request_id
    )

    # Receive the response
    response = RateLimiterMan.receive_response(request_id, _timeout = :timer.seconds(5))

    IO.puts(response)

    response
  end
end
```

Let's try it out. Start an interactive shell with `iex -S mix`:

```
iex> for _ <- 1..3, do: YourProject.SomeApi.hello_world()
Hello world!
Hello world!
Hello world!
["Hello world!", "Hello world!", "Hello world!"]
```

If you set your rate limiter with the config in the instructions, you should see the phrase "Hello world!" printed to the terminal 3 times, and the rate limiter ensured that only one "request" was handled every second.

If everything worked, you can now adapt the rate limiter for use in your application.

## More information

Project documentation: https://hexdocs.pm/rate_limiter_man

Hex package: https://hex.pm/rate_limiter_man
