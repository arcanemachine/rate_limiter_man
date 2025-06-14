defmodule RateLimiterManTest do
  use RateLimiterMan.Case

  describe "add_task_supervisor/0" do
    test "starts a task supervisor" do
      assert task_supervisor =
               {Task.Supervisor, name: task_supervisor_name} =
               RateLimiterMan.add_task_supervisor()

      # The process has been started
      assert {:ok, task_supervisor_pid} = start_supervised(task_supervisor)

      # The process is a supervisor with no children
      assert Task.Supervisor.children(task_supervisor_name) == []
      assert Task.Supervisor.children(task_supervisor_pid) == []
    end
  end

  describe "add_rate_limiter/0" do
    setup {TestHelpers, :setup_rate_limiter_config}

    test "uses the correct spec to add a child process", %{config_keys: [config_key | _]} do
      start_supervised!(RateLimiterMan.add_rate_limiter(constants().otp_app, config_key))
    end
  end
end
