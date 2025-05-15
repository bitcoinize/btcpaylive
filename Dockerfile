# Base Elixir image for development and for running initial mix tasks
FROM elixir:1.16.3-otp-26

RUN apt-get update && apt-get install -y \
    inotify-tools

# Install Hex package manager and Rebar3 build tool
# --force is used to avoid prompts in non-interactive Docker builds
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix archive.install hex phx_new --force

# Set the working directory in the container
WORKDIR /app

# At this stage (Step 1.1), we don't copy application code or define a CMD,
# as the Phoenix project will be generated in Step 1.2 using 'docker-compose run'.
# The 'app' service in docker-compose.yml will mount the local directory into /app. 