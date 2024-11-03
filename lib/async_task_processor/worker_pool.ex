defmodule AsyncTaskProcessor.WorkerPool do
  @moduledoc """
  Module responsible for managing the worker pool and scaling the workers based on the number of events in the queue.
  """
  use DynamicSupervisor
  require Logger

  alias AsyncTaskProcessor.QueueManager

  @min_workers Application.compile_env(:async_task_processor, :min_workers, 3)
  @max_workers Application.compile_env(:async_task_processor, :max_workers, 10)
  @event_per_worker Application.compile_env(:async_task_processor, :event_per_worker, 10)

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_worker do
    DynamicSupervisor.start_child(__MODULE__, AsyncTaskProcessor.Worker)
  end

  def get_current_active_workers do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc """
  Adjusts the worker pool size based on the number of events in the queue.
  The algorithm looks at the total number of messages in the queue and calculates the number of workers required to process them,
  considering that each worker can process a fixed number of events.
  If the number of required workers is greater than the current number of workers, it scales up the worker pool by starting additional workers
  between the minimum and maximum number of workers.
  """
  def adjust_pool_size do
    %{high: high_count, low: low_count} = QueueManager.queues_size()
    total_messages = high_count + low_count
    current_workers = get_current_active_workers()
    total_required_workers = ceil(total_messages / @event_per_worker)

    Logger.info(
      "Total messages: #{total_messages}, current workeds: #{current_workers}, total required workers: #{total_required_workers}"
    )

    more_workers_required?(total_required_workers, current_workers)
    |> maybe_scale_workers(total_required_workers, current_workers, total_messages)
  end

  defp more_workers_required?(total_required_workers, current_workers) do
    total_required_workers > current_workers
  end

  defp maybe_scale_workers(true, total_required_workers, current_workers, _total_messages) do
    required_additional_workers =
      calculate_target_number_of_workers(total_required_workers, current_workers)

    Logger.info(
      "Scaling the workers count from #{current_workers} to #{required_additional_workers}"
    )

    Enum.each(1..required_additional_workers, fn _ -> start_worker() end)
  end

  defp maybe_scale_workers(false, _total_required_workers, current_workers, total_messages) do
    Logger.info(
      "Current worker count of #{current_workers} is sufficient for processing #{total_messages} messages"
    )

    :noop
  end

  defp calculate_target_number_of_workers(total_required_workers, current_workers)
       when total_required_workers >= @max_workers do
    @max_workers - current_workers
  end

  defp calculate_target_number_of_workers(total_required_workers, current_workers)
       when total_required_workers <= @min_workers do
    @min_workers - current_workers
  end

  defp calculate_target_number_of_workers(total_required_workers, current_workers) do
    total_required_workers - current_workers
  end
end
