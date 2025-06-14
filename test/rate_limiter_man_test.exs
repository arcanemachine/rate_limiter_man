defmodule RateLimiterManTest do
  use RateLimiterMan.Case

  describe "add_task_supervisor/0" do
    test "returns the expected spec" do
      assert RateLimiterMan.add_task_supervisor() ==
               {Task.Supervisor, name: RateLimiterMan.TaskSupervisor}
    end

    test "can start a task supervisor" do
      TestHelpers.start_task_supervisor()
      |> TestHelpers.assert_task_supervisor_started()
      |> TestHelpers.assert_task_supervisor_has_children(_no_children = [])
    end
  end

  describe "add_rate_limiter/0" do
    setup {TestHelpers, :setup_rate_limiter_config}

    test "starts a rate limiter", %{config_keys: [config_key | _]} do
      start_supervised!(RateLimiterMan.add_rate_limiter(TC.otp_app(), config_key))
    end
  end

  describe "receive_response/2" do
    setup {TestHelpers, :setup_task_supervisor_and_rate_limiter}

    test "receives a response from the rate limiter", %{config_keys: [config_key | _]} do
      request_id = System.unique_integer()

      RateLimiterMan.make_request(TC.otp_app(), config_key, TC.request_handler_example(),
        send_response_to_pid: self(),
        request_id: request_id
      )

      response = RateLimiterMan.receive_response(request_id, :timer.seconds(1))

      assert response == TC.request_handler_example_response()
    end
  end
end
