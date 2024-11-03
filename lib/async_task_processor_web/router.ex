defmodule AsyncTaskProcessorWeb.Router do
  use AsyncTaskProcessorWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/events", AsyncTaskProcessorWeb do
    pipe_through :api

    post "/queue", EventsController, :queue
  end
end
