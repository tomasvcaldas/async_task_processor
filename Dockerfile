# Use an official Elixir image as the base
FROM elixir:1.17.3-alpine

# Install Hex and Rebar (Elixir build tools)
RUN mix local.hex --force && \
    mix local.rebar --force

# Set environment variables
ENV MIX_ENV=dev
ENV PORT=4000

# Create and set the working directory
WORKDIR /app

# Copy the application code into the Docker image
COPY . .

# Install dependencies
RUN mix deps.get

# Expose the port that Phoenix will run on
EXPOSE 4000

# Run the Phoenix server in development mode
CMD ["mix", "phx.server"]