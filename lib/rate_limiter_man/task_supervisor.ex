defmodule RateLimiterMan.TaskSupervisor do
  @moduledoc """
  Add a TaskSupervisor to your application's supervision tree.

  > #### Tip {: .tip}
  >
  > The TaskSupervisor must be added to your supervision tree before adding any rate limiters.

  ## Examples

  `lib/your_project/application.ex`
  ```elixir
  defmodule YourProject.Application do
    use Application

    @impl true
    def start(_type, _args) do
      children =
        [
          # Add the task supervisor before adding any rate limiters. The task supervisor must
          # only be declared once
          RateLimiterMan.TaskSupervisor,
          # Add the desired rate limiter(s). The OTP app name and config key must match the app
          # name and key used in your config file
          RateLimiterMan.new_rate_limiter(:your_project, YourProject.SomeApi)
        ]

      opts = [strategy: :one_for_one, name: YourProject.Supervisor]

      Supervisor.start_link(children, opts)
    end
  end
  ```
  """

  def child_spec(_opts \\ []) do
    %{
      id: __MODULE__,
      start: {Task.Supervisor, :start_link, [[name: __MODULE__]]}
    }
  end
end
