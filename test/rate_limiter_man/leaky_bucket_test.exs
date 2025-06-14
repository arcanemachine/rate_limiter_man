defmodule RateLimiterMan.LeakyBucketTest do
  use AssertEventually
  use RateLimiterMan.Case

  describe "make_request/4" do
    @tag :fixme
    test "calls a function via the rate limiter and sends the result back via message passing",
         %{config_keys: [config_key | _]} do
      assert task_supervisor =
               {Task.Supervisor, name: task_supervisor_name} =
               RateLimiterMan.add_task_supervisor()

      # The process has been started
      assert {:ok, _task_supervisor_pid} = start_supervised(task_supervisor)

      # Call a function via the rate limiter
      start_time = DateTime.utc_now()
      request_id = System.unique_integer()

      RateLimiterMan.make_request(@otp_app, config_key, @some_request_handler,
        send_response_to_pid: self(),
        request_id: request_id
      )

      eventually(assert_received {:ok, %{response: @expected_response}})

      # The rate limiter throttled the requests as expected
      finish_time = DateTime.utc_now()
    end
  end
end
