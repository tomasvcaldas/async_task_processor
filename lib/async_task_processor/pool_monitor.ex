defmodule AsyncTaskProcessor.PoolMonitor do
  @moduledoc """
  Module responsible for scheduling worker pool adjustments at regular intervals.
  """
  use GenServer
  require Logger

  alias AsyncTaskProcessor.WorkerPool

  @pool_adjustment_interval Application.compile_env(
                              :async_task_processor,
                              :pool_adjustment_interval,
                              5000
                            )

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_) do
    schedule_worker_pool_adjustment()
    {:ok, :no_state}
  end

  def handle_info(:adjust_pool, state) do
    WorkerPool.adjust_pool_size()
    schedule_worker_pool_adjustment()

    {:noreply, state}
  end

  defp schedule_worker_pool_adjustment do
    Process.send_after(self(), :adjust_pool, @pool_adjustment_interval)
  end
end
