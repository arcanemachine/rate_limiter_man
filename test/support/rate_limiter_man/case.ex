defmodule RateLimiterMan.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias RateLimiterMan.TestConstants, as: TC
      alias RateLimiterMan.TestHelpers
    end
  end
end
