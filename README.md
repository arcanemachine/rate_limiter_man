# RateLimiterMan

> #### Warning {: .warning}
>
> This is a very early release. It works but has some rough edges, and shouldn't be considered production-ready for most use cases. It is probably not the most performant implementation out there, but it solves the need for which it was created.

A simple rate limiter implementation, adapted from [a blog post by Alex Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

> #### Warning {: .warning}
>
> Currently, only the leaky bucket rate limiter algorithm is implemented by this package.

This package supports multiple rate limiter instances in your application. Just follow the instructions, using a different config key for each rate limiter you want to add.

## Getting started

### Install the package

Add this package to your list of dependencies in `mix.exs`, then run `mix deps.get`:

```elixir
{:rate_limiter_man, "0.2.0"}
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

> #### Warning {: .warning}
>
> The log statements may contain sensitive data (e.g. API keys). There is currently no way of
> modifying the contents of the Logger statement.

### Add the rate limiter to your application's supervision tree

`lib/your_project/application.ex`
```elixir

defmodule YourProject.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Add a task supervisor. This only needs to be added once:
        RateLimiterMan.start_task_supervisor(),
        # Add one of these lines for each rate limiter instance. The OTP app name
        # (`:your_project`) and config key (`YourProject.SomeApi`) must match the keys used in
        # your config file
        RateLimiterMan.start_rate_limiter(:your_project, YourProject.SomeApi)
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
