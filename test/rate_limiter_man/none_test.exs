defmodule RateLimiterMan.NoneTest do
  use RateLimiterMan.Case
  alias ExUnit.CaptureLog

  test "does not add a rate limiter to the supervision tree" do
    captured_logs =
      CaptureLog.capture_log(fn ->
        %{config_keys: [config_key | _]} =
          TestHelpers.setup_task_supervisor_and_rate_limiter(_context = nil,
            rate_limiter_algorithm: RateLimiterMan.None
          )

        # The rate limiter has not been added to the supervision tree
        assert RateLimiterMan.get_instance_name(config_key) |> Process.whereis() |> is_nil()
      end)

    assert captured_logs =~ "rate limiter has been disabled"
  end

  describe "make_request/4" do
    test "calls a function with no rate limiting and sends the result back via message passing" do
      captured_logs =
        CaptureLog.capture_log(fn ->
          %{config_keys: [config_key | _]} =
            TestHelpers.setup_task_supervisor_and_rate_limiter(_context = nil,
              rate_limiter_algorithm: RateLimiterMan.None,
              rate_limiter_max_requests_per_second: 1
            )

          start_datetime = DateTime.utc_now()

          # Call a function via the inoperative "rate limiter"
          request_count = 10

          responses =
            Enum.map(1..request_count, fn _i ->
              request_id = System.unique_integer()

              RateLimiterMan.make_request(TC.otp_app(), config_key, TC.request_handler_example(),
                send_response_to_pid: self(),
                request_id: request_id
              )

              RateLimiterMan.receive_response(request_id)
            end)

          finish_datetime = DateTime.utc_now()

          # The rate limiter returned the expected responses
          assert Enum.all?(responses, &(&1 == TC.request_handler_example_response()))

          # The rate limiter did not throttle the requests
          min_expected_finish_time =
            (fn ->
               max_requests_per_second =
                 TestHelpers.get_max_requests_per_second_from_rate_limiter_config(
                   TC.otp_app(),
                   config_key
                 )

               minimum_expected_seconds_duration = request_count |> div(max_requests_per_second)

               start_datetime |> DateTime.add(minimum_expected_seconds_duration)
             end).()

          assert DateTime.compare(finish_datetime, min_expected_finish_time) == :lt
        end)

      assert captured_logs =~ "rate limiter has been disabled"
    end
  end
end
