defmodule RateLimiterMan.TaskSupervisorTest do
  use RateLimiterMan.Case

  describe "child_spec/1" do
    test "returns the expected result" do
      assert RateLimiterMan.TaskSupervisor.child_spec() ==
               %{
                 id: RateLimiterMan.TaskSupervisor,
                 start: {Task.Supervisor, :start_link, [[name: RateLimiterMan.TaskSupervisor]]}
               }
    end

    test "can start a task supervisor" do
      TestHelpers.start_task_supervisor()
      |> TestHelpers.assert_task_supervisor_started()
      |> TestHelpers.assert_task_supervisor_has_children(_no_children = [])
    end
  end
end
