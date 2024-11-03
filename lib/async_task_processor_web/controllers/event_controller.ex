defmodule AsyncTaskProcessorWeb.EventsController do
  use AsyncTaskProcessorWeb, :controller
  alias AsyncTaskProcessor.QueueManager

  require Logger

  def queue(conn, %{"events" => events}) do
    Logger.info("#{length(events)} events received, adding into the respective queues.")

    Enum.each(events, fn event ->
      event
      |> normalize_priority()
      |> QueueManager.queue_event()
    end)

    send_resp(conn, :ok, "Events queued successfully")
  end

  def queue(conn, _) do
    send_resp(conn, :bad_request, "Invalid request")
  end

  defp normalize_priority(%{"priority" => priority} = event) when priority in ["high", "low"] do
    event
  end

  defp normalize_priority(event), do: Map.put(event, "priority", "low")
end
