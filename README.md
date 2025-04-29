# RateLimiterMan

> #### Warning
>
> This is a very early release. It works but has some rough edges, and shouldn't be considered
> production-ready for most use cases.

A simple rate limiter implementation, adapted from [a blog post by Alex Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

## Getting started

### Installation

Add this package to your list of dependencies in `mix.exs`, then run `mix deps.get`:

```elixir
{:rate_limiter_man, "0.1.1"}
```

### Usage

Basic usage instructions coming soon. For now, see [the blog post by Alex Koutmous](https://akoutmos.com/post/rate-limiting-with-genservers/).

This project also has a mechanism for the rate limiter to pass its responses back to the caller. See `RateLimiterMan.make_request/4` for more information.

For more information, see [the project documentation](https://hexdocs.pm/rate_limiter_man).
