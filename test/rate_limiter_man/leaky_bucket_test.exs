defmodule RateLimiterMan.LeakyBucketTest do
  use RateLimiterMan.Case

  describe "make_request/4" do
    setup {TestHelpers, :setup_task_supervisor_and_rate_limiter}

    test "calls a function via the rate limiter and sends the result back via message passing",
         %{config_keys: [config_key | _]} do
      start_datetime = DateTime.utc_now()

      # Call a function via the rate limiter
      request_count = Enum.random(10..100)

      responses =
        Enum.map(1..request_count, fn _i ->
          request_id = System.unique_integer()

          RateLimiterMan.make_request(TC.otp_app(), config_key, TC.request_handler_example(),
            send_response_to_pid: self(),
            request_id: request_id
          )

          RateLimiterMan.receive_response(request_id)
        end)

      # The rate limiter returned the expected responses
      assert Enum.all?(responses, &(&1 == TC.request_handler_example_response()))

      # The rate limiter throttled the requests at the expected rate
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

      assert Date.compare(DateTime.utc_now(), min_expected_finish_time) in [:eq, :gt]
    end
  end
end
