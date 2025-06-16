defmodule RateLimiterManTest do
  use RateLimiterMan.Case

  describe "new_task_supervisor/0" do
    test "returns the expected spec" do
      assert RateLimiterMan.new_task_supervisor() ==
               {Task.Supervisor, name: RateLimiterMan.TaskSupervisor}
    end

    test "can start a task supervisor" do
      TestHelpers.start_task_supervisor()
      |> TestHelpers.assert_task_supervisor_started()
      |> TestHelpers.assert_task_supervisor_has_children(_no_children = [])
    end
  end

  describe "new_rate_limiter/0" do
    setup {TestHelpers, :setup_rate_limiter_config}

    test "starts a rate limiter", %{config_keys: [config_key | _]} do
      start_supervised!(RateLimiterMan.new_rate_limiter(TC.otp_app(), config_key))
    end
  end

  describe "calculate_refresh_rate/2" do
    test "returns the expected value" do
      put_config = fn max_requests_per_second ->
        TestHelpers.put_rate_limiter_config(
          rate_limiter_max_requests_per_second: max_requests_per_second
        )
      end

      assert RateLimiterMan.calculate_refresh_rate(TC.otp_app(), put_config.(0.01)) == 100_000
      assert RateLimiterMan.calculate_refresh_rate(TC.otp_app(), put_config.(0.1)) == 10_000
      assert RateLimiterMan.calculate_refresh_rate(TC.otp_app(), put_config.(1)) == 1000
      assert RateLimiterMan.calculate_refresh_rate(TC.otp_app(), put_config.(10)) == 100
      assert RateLimiterMan.calculate_refresh_rate(TC.otp_app(), put_config.(100)) == 10
      assert RateLimiterMan.calculate_refresh_rate(TC.otp_app(), put_config.(1000)) == 1
    end
  end

  describe "get_rate_limiter/2" do
    setup {TestHelpers, :setup_rate_limiter_config}

    test "gets the configured rate limiter", %{config_keys: [config_key | _]} do
      expected_rate_limiter =
        TestHelpers.get_rate_limiter_algorithm_from_rate_limiter_config(TC.otp_app(), config_key)

      assert RateLimiterMan.get_rate_limiter(TC.otp_app(), config_key) == expected_rate_limiter
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
