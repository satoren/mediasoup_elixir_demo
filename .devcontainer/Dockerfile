FROM elixir:latest

RUN mix local.hex --force && \
  mix archive.install hex phx_new 1.6.3 --force && \
  mix local.rebar --force
