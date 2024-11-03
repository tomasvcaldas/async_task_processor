defmodule AsyncTaskProcessor.Worker do
  @moduledoc """
  Worker module responsible for polling events from the queue and processing them.
  Worker polling is scheduled at a fixed interval and will terminate if no events are polled within a certain time frame.
  Event processing is simulated by sleeping for a random duration in a configurable range.
  """
  use GenServer, restart: :temporary

  require Logger

  alias AsyncTaskProcessor.QueueManager

  @poll_interval Application.compile_env(:async_task_processor, :poll_interval, 1000)
  @inactive_interval Application.compile_env(:async_task_processor, :inactive_interval, 5000)
  @max_retries Application.compile_env(:async_task_processor, :max_retries, 3)
  @duration_to_complete_random Application.compile_env(
                                 :async_task_processor,
                                 :duration_to_complete_random,
                                 3
                               )

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(_) do
    Logger.info("Starting worker #{inspect(self())}")
    schedule_polling()

    {:ok,
     %{
       processing: false,
       last_polling_at: System.monotonic_time(:millisecond)
     }}
  end

  @doc """
  Handles the polling of events from the queue. If the worker is inactive, it will terminate itself.
  After polling an event, it will process it and schedule the next polling.
  Some events may fail and be retried a configurable number of times before being added to the dead letter queue.
  For testing purposes we retry events based on a key value pair that can be given in the event details.
  """
  @impl true
  def handle_info(:poll, state) do
    case is_worker_inactive?(state) do
      true ->
        Logger.info("Terminating worker #{inspect(self())} normally.")
        {:stop, :normal, state}

      false ->
        poll_event(state)
    end
  end

  defp poll_event(state) do
    case QueueManager.poll_event() do
      nil ->
        schedule_polling()
        {:noreply, state}

      %{"id" => id} = event ->
        Logger.info("Worker #{inspect(self())} polled event #{inspect(id)} from queue.")
        process_event(event)
        schedule_polling()

        {:noreply,
         %{state | processing: false, last_polling_at: System.monotonic_time(:millisecond)}}
    end
  end

  defp process_event(event) do
    duration_to_complete = compute_duration_to_complete()
    Logger.info("Completing after #{inspect(event["id"])} in #{duration_to_complete}ms.")

    :timer.sleep(duration_to_complete)
    maybe_retry_event(event)
  end

  defp schedule_polling do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp is_worker_inactive?(%{processing: false, last_polling_at: last_polling_at}) do
    System.monotonic_time(:millisecond) - last_polling_at >= @inactive_interval
  end

  defp is_worker_inactive?(%{processing: true}), do: false

  defp compute_duration_to_complete do
    :rand.uniform(@duration_to_complete_random) * 1000
  end

  defp maybe_retry_event(%{"should_retry?" => true, "id" => id} = event) do
    retry = Map.get(event, "retry", 0)

    case retry >= @max_retries do
      true ->
        Logger.error(
          "Event #{inspect(id)} failed and reached max allowed retries. Removing from queue and adding to dead letter queue."
        )

        QueueManager.remove_event_from_queue(event)
        QueueManager.add_to_dead_letter_queue(event)
        {:ok, :noop}

      false ->
        Logger.error("Event failed #{inspect(id)}, retrying... Retry count: #{retry}.")
        # We could add some sort of exponential backoff here

        event
        |> Map.put("retry", retry + 1)
        |> process_event()

        {:ok, :noop}
    end
  end

  defp maybe_retry_event(event) do
    Logger.info("Event #{inspect(event["id"])} processed successfully. Removing from queue.")
    QueueManager.remove_event_from_queue(event)
    {:ok, :noop}
  end
end
