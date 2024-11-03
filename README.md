# AsyncTaskProcessor

AsyncTaskProcessor is an Elixir/Phoenix application that implements a scalable event processing system with priority queues and dynamic worker management.

## Features

- Priority-based event processing (high and low priority queues)
- Dynamic worker pool that scales based on queue size
- At-least-once delivery guarantee
- Dead letter queue (DLQ) for failed events
- Automatic worker cleanup for inactive processors
- Configurable retry mechanism for failed events

### Pool Adjustment Algorithm

The system implements an adaptive worker pool scaling algorithm that optimizes resource utilization based on queue load:

#### Scaling Formula
```
total_required_workers = ceil(total_messages / events_per_worker)
```
where:
- `total_messages` = high_priority_queue_size + low_priority_queue_size
- `events_per_worker` = configurable threshold 

### Scaling Rules
1. If total_required_workers > current_workers:
   - Scale up to handle increased load until a max workers limit
   - Always launch a minimum configurable worker number
2. If total_required_workers <= current_workers:
   - Maintain current pool size
   - Let inactive workers self-terminate


## Architecture

The system consists of the following components:

### QueueManager
- Maintains three queues: high priority, low priority, and dead letter queue (DLQ)
- Ensures atomic operations for event management
- Implements at-least-once delivery by only removing events after successful processing and by tracking worker-event mappings to handle worker crashes

### WorkerPool
- Uses DynamicSupervisor for flexible worker management
- Scales workers based on queue size
- Configurable min/max worker counts
- Automatic cleanup of inactive workers

### Worker
- Polls events at configurable intervals
- Implements retry mechanism with configurable max attempts
- Self-terminates when inactive to conserve resources

## Key Design Decisions

### DynamicSupervisor vs Supervisor
The system uses a DynamicSupervisor instead of a Supervisor for the worker pool because:
- Need to scale workers up/down based on queue size
- Temporary worker processes that self-terminate when inactive
- Better resource utilization by maintaining only necessary workers
- More closely related to a real-life scenario

### At-least-once Delivery
The system ensures at-least-once delivery through several mechanisms:
1. Events are only removed from queue after successful processing
2. Worker crashes are monitored and events are requeued
3. Failed events can be retried with configurable max attempts

### Event Processing Duplication Safety
To prevent duplicate processing while maintaining at-least-once delivery:
- Events are marked as "processing" when assigned to a worker
- Worker processes are monitored using Process.monitor
- Worker crashes trigger event reprocessing
- Event IDs are unique (using make_ref())
- Worker-event mappings are maintained in the QueueManager state

## Setup and Running

### Docker
```bash
docker compose up
```

## Configuration

The system is highly configurable through environment variables:

```elixir
config :async_task_processor,
  poll_interval: 1000, # Time to wait for worker to try to poll a new event 
  inactive_interval: 3000, # Time without polling for a worker to be considered inactive and shutdown
  max_retries: 3, # Max event retries before an event is added to the DLQ
  duration_to_complete_random: 3, # Random interval to simulate event processing and marked as complete
  min_workers: 3, # Min active worker - used for pool adjustment algorithm
  max_workers: 10, # Max active workers - used for pool adjustment algorithm
  event_per_worker: 3, # Number of events per worker - used for pool adjustment algorithm
  pool_adjustment_interval: 5000 # Interval between next pool adjustment execution
```

## API

### Queue Events
Curl example to add 1 high priority event and 2 low priority ones.
```bash
curl --location 'http://localhost:4000/events/queue' \
--header 'Content-Type: application/json' \
--data '{ "events": [ { "priority": "high", "details": "event1" }, {   "priority": "low", "details": "event2" }, { "details": "event3" } ]}'
```
