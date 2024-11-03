defmodule AsyncTaskProcessorWeb.EventsControllerTest do
  use AsyncTaskProcessorWeb.ConnCase, async: false
  alias AsyncTaskProcessor.QueueManager

  describe "POST /events/queue" do
    test "successfully queues multiple events with different priorities defaulting to low priority on no priority",
         %{conn: conn} do
      events = [
        %{"name" => "event_name", "priority" => "high"},
        %{"name" => "event_name", "priority" => "low"},
        %{"name" => "event_name"}
      ]

      response =
        conn
        |> post("/events/queue", %{"events" => events})
        |> response(200)

      assert response == "Events queued successfully"

      %{high: high_count, low: low_count} = QueueManager.queues_size()
      assert high_count == 1
      assert low_count == 2
      QueueManager.reset_state()
    end
  end
end
