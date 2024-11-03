defmodule AsyncTaskProcessor.WorkerTest do
  use ExUnit.Case, async: false
  require Logger

  alias AsyncTaskProcessor.Worker
  alias AsyncTaskProcessor.QueueManager

  describe "Event processing" do
    test "is successfully done and removed from the queue after completion" do
      test_event = %{"name" => "test_event", "priority" => "high"}
      QueueManager.queue_event(test_event)

      assert %{high: 1, low: 0} = QueueManager.queues_size()

      Worker.start_link([])

      Process.sleep(3000)

      assert %{high: 0, low: 0} = QueueManager.queues_size()
      QueueManager.reset_state()
    end

    test "is successfully done by priority and removed from the queue after completion" do
      events = [
        %{"name" => "test_event", "priority" => "low"},
        %{"name" => "test_event", "priority" => "high"},
        %{"name" => "test_event", "priority" => "low"}
      ]

      Enum.each(events, &QueueManager.queue_event/1)

      assert %{high: 1, low: 2} = QueueManager.queues_size()
      Worker.start_link([])
      Process.sleep(3500)

      assert %{high: 0, low: 2} = QueueManager.queues_size()

      Process.sleep(4000)

      assert %{high: 0, low: 0} = QueueManager.queues_size()
      QueueManager.reset_state()
    end

    test "fails and is added to the dead letter queue after max retries" do
      test_event = %{"name" => "test_event", "priority" => "low", "should_retry?" => true}
      QueueManager.queue_event(test_event)

      assert %{high: 0, low: 1} = QueueManager.queues_size()

      Worker.start_link([])

      Process.sleep(6000)

      assert %{high: 0, low: 0, dlq: 1} = QueueManager.queues_size()
      QueueManager.reset_state()
    end
  end
end
