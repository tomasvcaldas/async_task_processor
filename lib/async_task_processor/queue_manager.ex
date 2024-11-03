defmodule AsyncTaskProcessor.QueueManager do
  @moduledoc """
  Module responsible for handling the queues and the mapping between which worker is processing which event.
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def queue_event(event) do
    GenServer.cast(__MODULE__, {:add_to_queue, event})
  end

  def add_to_dead_letter_queue(event) do
    GenServer.cast(__MODULE__, {:add_to_dead_letter_queue, event})
  end

  def poll_event do
    GenServer.call(__MODULE__, :poll_event)
  end

  def queues_size do
    GenServer.call(__MODULE__, :queues_size)
  end

  def remove_event_from_queue(event) do
    GenServer.cast(__MODULE__, {:remove_event_from_queue, event})
  end

  def reset_state do
    GenServer.cast(__MODULE__, :reset_state)
  end

  @impl true
  def init(_) do
    {:ok,
     %{
       high_priority_queue: [],
       low_priority_queue: [],
       dead_letter_queue: [],
       worker_events: %{}
     }}
  end

  @impl true
  def handle_cast(:reset_state, state) do
    {:noreply,
     %{
       state
       | high_priority_queue: [],
         low_priority_queue: [],
         dead_letter_queue: [],
         worker_events: %{}
     }}
  end

  @impl true
  def handle_cast({:add_to_queue, %{"priority" => "high"} = event}, state) do
    event =
      event
      |> Map.put("id", make_ref())
      |> Map.put("processing", false)

    Logger.info("Adding event #{inspect(event["id"])} to high priority queue")
    {:noreply, %{state | high_priority_queue: state.high_priority_queue ++ [event]}}
  end

  @impl true
  def handle_cast({:add_to_queue, event}, state) do
    event =
      event
      |> Map.put("id", make_ref())
      |> Map.put("processing", false)

    Logger.info("Adding event #{inspect(event["id"])} to low priority queue")
    {:noreply, %{state | low_priority_queue: state.low_priority_queue ++ [event]}}
  end

  @impl true
  def handle_cast({:add_to_dead_letter_queue, event}, state) do
    Logger.info("Adding event #{inspect(event["id"])} to dead letter queue")
    {:noreply, %{state | dead_letter_queue: state.dead_letter_queue ++ [event]}}
  end

  @impl true
  def handle_cast(
        {:remove_event_from_queue, %{"priority" => "high", "id" => id}},
        state
      ) do
    {:noreply,
     %{
       state
       | high_priority_queue: remove_from_queue(state.high_priority_queue, id),
         worker_events: remove_from_worker_events(state.worker_events, id)
     }}
  end

  @impl true
  def handle_cast(
        {:remove_event_from_queue, %{"id" => id}},
        state
      ) do
    {:noreply,
     %{
       state
       | low_priority_queue: remove_from_queue(state.low_priority_queue, id),
         worker_events: remove_from_worker_events(state.worker_events, id)
     }}
  end

  @impl true
  def handle_call(:queues_size, _from, state) do
    {:reply,
     %{
       high: length(state.high_priority_queue),
       low: length(state.low_priority_queue),
       dlq: length(state.dead_letter_queue)
     }, state}
  end

  @doc """
  Polls the next event from the queues and assigns it to the worker that requested it.
  First, it checks the high priority queue for any event that needs processing. If none is found, it checks the low priority queue.
  Returns nil if no event is found in either queue.
  """
  @impl true
  def handle_call(
        :poll_event,
        {worker_pid, _from},
        %{high_priority_queue: high_priority_queue, low_priority_queue: low_priority_queue} =
          state
      ) do
    case find_first_unprocessed_event_from_queue(high_priority_queue) do
      nil ->
        case find_first_unprocessed_event_from_queue(low_priority_queue) do
          nil ->
            {:reply, nil, state}

          event ->
            {updated_event, updated_queue} =
              set_event_processing_state(event, low_priority_queue, true)

            updated_worker_events = Map.put(state.worker_events, worker_pid, event)
            Process.monitor(worker_pid)

            {:reply, updated_event,
             %{state | low_priority_queue: updated_queue, worker_events: updated_worker_events}}
        end

      event ->
        {updated_event, updated_queue} =
          set_event_processing_state(event, high_priority_queue, true)

        updated_worker_events = Map.put(state.worker_events, worker_pid, event)
        Process.monitor(worker_pid)

        {:reply, updated_event,
         %{state | high_priority_queue: updated_queue, worker_events: updated_worker_events}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, worker_pid, :normal}, state) do
    {:noreply, %{state | worker_events: Map.delete(state.worker_events, worker_pid)}}
  end

  @doc """
  Handles the crash of a worker process.
  If the worker was processing an event, it marks the event as unprocessed so that other workers can pick it up
  and we ensure at least once processing of the event.
  """
  @impl true
  def handle_info({:DOWN, _ref, :process, worker_pid, reason}, state) do
    Logger.error("Worker #{inspect(worker_pid)} shutdown with reason #{inspect(reason)}")

    case Map.get(state.worker_events, worker_pid) do
      %{"priority" => "high"} = event ->
        {_updated_event, updated_queue} =
          set_event_processing_state(event, state.high_priority_queue, false)

        Logger.info("Marking event #{inspect(event["id"])} as unprocessed")

        {:noreply,
         %{
           state
           | worker_events: remove_from_worker_events(state.worker_events, worker_pid),
             high_priority_queue: updated_queue
         }}

      %{"priority" => "low"} = event ->
        {_updated_event, updated_queue} =
          set_event_processing_state(event, state.low_priority_queue, false)

        Logger.info("Marking event #{inspect(event["id"])} as unprocessed")

        {:noreply,
         %{
           state
           | worker_events: remove_from_worker_events(state.worker_events, worker_pid),
             low_priority_queue: updated_queue
         }}

      _ ->
        Logger.info("Worker #{inspect(worker_pid)} wasn't processing any event.")
        {:noreply, state}
    end
  end

  defp find_first_unprocessed_event_from_queue(queue) do
    Enum.find(queue, fn event -> event["processing"] == false end)
  end

  defp set_event_processing_state(%{"id" => id} = event, queue, in_processing_state?) do
    updated_event = Map.put(event, "processing", in_processing_state?)

    updated_queue =
      Enum.map(queue, fn current_event ->
        if current_event["id"] == id do
          updated_event
        else
          current_event
        end
      end)

    {updated_event, updated_queue}
  end

  defp remove_from_queue(queue, id) do
    Enum.filter(queue, fn event -> event["id"] != id end)
  end

  defp remove_from_worker_events(worker_events, worker_pid) do
    Map.delete(worker_events, worker_pid)
  end
end
