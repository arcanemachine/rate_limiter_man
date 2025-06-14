defmodule RateLimiterMan.Case do
  use ExUnit.CaseTemplate

  using do
    quote do
      import RateLimiterMan.TestHelpers, only: [constants: 0]
      alias RateLimiterMan.TestHelpers
    end
  end
end
