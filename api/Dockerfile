FROM elixir:1.16-slim
RUN apt-get update && apt-get install -y ca-certificates build-essential && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
RUN mix deps.get && mix deps.compile
COPY . .
RUN mix compile
CMD ["mix", "run", "--no-halt"]
