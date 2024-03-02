defmodule MediasoupElixirDemoWeb.SFURouter do
  use GenServer

  alias MediasoupElixirDemoWeb.RouterGroup

  alias Mediasoup.{
    PipeTransport,
    WebRtcServer,
    WebRtcTransport,
    Transport,
    Worker,
    Router,
    Consumer,
    Producer
  }

  @router_option %{
    mediaCodecs: [
      %{
        kind: "audio",
        mimeType: "audio/opus",
        clockRate: 48000,
        channels: 2,
        parameters: %{"foo" => "bar"},
        rtcpFeedback: []
      },
      %{
        kind: "video",
        mimeType: "video/VP8",
        clockRate: 90000,
        parameters: %{},
        rtcpFeedback: []
      },
      %{
        kind: "video",
        mimeType: "video/H264",
        clockRate: 90000,
        parameters: %{
          "level-asymmetry-allowed" => 1,
          "packetization-mode" => 1,
          "profile-level-id" => "4d0032",
          "foo" => "bar"
        },
        rtcpFeedback: []
      }
    ]
  }

  @timeout 60_000

  def get_or_start(room_id) do
    with [pid | _] <- RouterGroup.get_local_members(room_id),
         :ok <- GenServer.call(pid, {:put_user, self()}) do
      {:ok, pid}
    else
      _ ->
        start(room_id)
    end
  end

  def start(room_id) do
    GenServer.start(__MODULE__, room_id: room_id, user_process: self())
  end

  def create_webrtc_transport(router) do
    GenServer.call(router, {:create_webrtc_transport, self()})
  end

  def try_pipe_consume(router, producer_id) do
    GenServer.call(router, {:try_pipe_consume, producer_id})
  end

  def produce(router, transport_id, producer_option = %Producer.Options{}) do
    GenServer.call(router, {:produce, transport_id, producer_option})
  end

  def get_router_rtp_capabilities(router) do
    GenServer.call(router, :get_router_rtp_capabilities)
  end

  def router_dump(router) do
    GenServer.call(router, :router_dump)
  end

  @impl true
  def init(init_arg) do
    conf = Application.get_env(:mediasoup_elixir_demo, __MODULE__)

    room_id = Keyword.fetch!(init_arg, :room_id)
    {:ok, worker} = Worker.start_link(settings: conf[:worker])
    {:ok, router} = Worker.create_router(worker, @router_option)

    {:ok, webrtc_server} =
      Worker.create_webrtc_server(worker, %WebRtcServer.Options{
        listen_infos: conf[:webrtc_server][:listen_infos]
      })

    RouterGroup.join(room_id, self())
    {ref, pids} = RouterGroup.monitor(room_id)

    pipe_transports =
      Enum.reduce(pids, %{}, fn pid, acc ->
        Map.put(acc, pid, create_pipe_transport(router, pid))
      end)

    {:ok,
     %{
       room_id: room_id,
       worker: worker,
       router: router,
       webrtc_server: webrtc_server,
       webrtc_transport_owner_monitor_refs: %{},
       pipe_transports: pipe_transports,
       group_monitor_ref: ref,
       user_process_refs: [Process.monitor(Keyword.fetch!(init_arg, :user_process))]
     }, @timeout}
  end

  @impl true
  def handle_call(
        {:create_webrtc_transport, owner},
        _from,
        %{router: router, webrtc_server: webrtc_server} = state
      ) do
    case Router.create_webrtc_transport(router, %WebRtcTransport.Options{
           webrtc_server: webrtc_server,
           initial_available_outgoing_bitrate: 1_000_000
         }) do
      {:ok, transport} ->
        monitor_ref = Process.monitor(owner)

        webrtc_transport_owner_monitor_refs =
          Map.put(state.webrtc_transport_owner_monitor_refs, monitor_ref, transport)

        {:reply, {:ok, transport},
         %{state | webrtc_transport_owner_monitor_refs: webrtc_transport_owner_monitor_refs},
         @timeout}

      {:error, reason} ->
        {:reply, {:error, reason}, state, @timeout}
    end
  end

  def handle_call(
        :get_router_rtp_capabilities,
        _from,
        state
      ) do
    {:reply, {:ok, Router.rtp_capabilities(state.router)}, state, @timeout}
  end

  def handle_call(
        {:try_pipe_consume, producer_id},
        _from,
        state
      ) do
    case try_consume_with_pipe(state, producer_id) do
      {:ok, state} ->
        {:reply, :ok, state, @timeout}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state, @timeout}
    end
  end

  def handle_call(
        {:start_consume_to_pipe, consumer_option, pid},
        _from,
        state
      ) do
    with {:ok, transport} <- Map.fetch(state.pipe_transports, pid),
         {:ok, consumer} <- Transport.consume(transport, consumer_option) do
      pipe_produce_option = %Producer.Options{
        id: consumer_option.producer_id,
        kind: Consumer.kind(consumer),
        rtp_parameters: Consumer.rtp_parameters(consumer),
        paused: Consumer.producer_paused?(consumer)
      }

      {:reply, {:ok, {consumer, pipe_produce_option, self()}}, state, @timeout}
    else
      :error ->
        {:reply, {:error, "PipeTransport with pid \"#{pid}\" not found"}, state, @timeout}

      error ->
        {:reply, error, state, @timeout}
    end
  end

  def handle_call(
        :router_dump,
        _from,
        %{router: router} = state
      ) do
    {:reply, Router.dump(router), state, @timeout}
  end

  def handle_call(
        {:put_user, pid},
        _from,
        state
      ) do
    {:reply, :ok, %{state | user_process_refs: [Process.monitor(pid) | state.user_process_refs]},
     @timeout}
  end

  @impl true
  def handle_cast(
        {:create_pipe_transport,
         %{
           port: port,
           ip: ip
         }, other_router_pid},
        state
      ) do
    case Map.fetch(state.pipe_transports, other_router_pid) do
      {:ok, pipe_transport} ->
        PipeTransport.connect(pipe_transport, %{
          ip: ip,
          port: port
        })

        {:noreply, state, @timeout}

      :error ->
        pipe_transport = create_pipe_transport(state.router, other_router_pid)

        PipeTransport.connect(pipe_transport, %{
          ip: ip,
          port: port
        })

        state = update_in(state.pipe_transports, &Map.put(&1, other_router_pid, pipe_transport))
        {:noreply, state, @timeout}
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    if state.user_process_refs == [] do
      {:stop, :shutdown, state}
    else
      {:noreply, state, @timeout}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _}, state) do
    state = %{state | user_process_refs: state.user_process_refs -- [ref]}

    case Map.fetch(state.webrtc_transport_owner_monitor_refs, ref) do
      {:ok, transport} ->
        WebRtcTransport.close(transport)
        state = update_in(state.webrtc_transport_owner_monitor_refs, &Map.delete(&1, ref))
        {:noreply, state, @timeout}

      :error ->
        {:noreply, state, @timeout}
    end
  end

  def handle_info(
        {ref, :join, _group, pids},
        %{group_monitor_ref: group_monitor_ref, router: router} = state
      )
      when group_monitor_ref === ref do
    pipe_transports =
      Enum.reduce(pids, %{}, fn pid, acc ->
        Map.put(acc, pid, create_pipe_transport(router, pid))
      end)

    state = update_in(state.pipe_transports, &Map.merge(&1, pipe_transports))
    {:noreply, state, @timeout}
  end

  def handle_info(
        {ref, :leave, _group, pids},
        %{group_monitor_ref: group_monitor_ref} = state
      )
      when group_monitor_ref === ref do
    state.pipe_transports
    |> Map.take(pids)
    |> Enum.each(fn {_pid, transport} -> PipeTransport.close(transport) end)

    state = update_in(state.pipe_transports, &Map.drop(&1, pids))
    {:noreply, state, @timeout}
  end

  defp create_pipe_transport(router, other_router_pid) do
    {:ok, pipe_transport} =
      Router.create_pipe_transport(router, %PipeTransport.Options{
        listen_info: %{ip: get_listen_ip(other_router_pid), protocol: :udp}
      })

    %{"localPort" => port, "localIp" => _ip} = PipeTransport.tuple(pipe_transport)

    GenServer.cast(
      other_router_pid,
      {:create_pipe_transport,
       %{
         port: port,
         ip: get_local_ip(other_router_pid)
       }, self()}
    )

    pipe_transport
  end

  defp try_consume_with_pipe(state, producer_id) do
    case start_pipe_produce(state, producer_id) do
      {:ok, {_producer, _consumer}} ->
        # TODO:　Pipe Producer & Consumer should be closed when consumer is gone.
        {:ok, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def take_pipe_consumer(pids, option) do
    from = self()

    pids
    |> Enum.reject(fn pid -> pid === from end)
    |> Task.async_stream(fn pid ->
      GenServer.call(pid, {:start_consume_to_pipe, option, from})
    end)
    |> Stream.map(fn
      {:ok, success} -> success
      error -> error
    end)
    |> Stream.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Stream.take(1)
    |> Enum.to_list()
    |> List.first()
  end

  defp start_pipe_produce(state, producer_id) do
    option = %Consumer.Options{
      producer_id: producer_id,
      rtp_capabilities: Router.rtp_capabilities(state.router)
    }

    # TODO: Pipe request to all group processes. This is inefficient because it may result in a multi-stage pipe.

    local_members = RouterGroup.get_local_members(state.room_id)

    pipe_consume_result =
      local_members
      |> take_pipe_consumer(option) ||
        (RouterGroup.get_members(state.room_id) -- local_members) |> take_pipe_consumer(option)

    with {:ok, {consumer, pipe_produce_option, pipe_source_pid}} <- pipe_consume_result,
         {:ok, transport} <- Map.fetch(state.pipe_transports, pipe_source_pid),
         {:ok, producer} <- Transport.produce(transport, pipe_produce_option) do
      # Pipe events from the pipe Consumer to the pipe Producer.
      Consumer.event(consumer, producer.pid, [:on_close, :on_pause, :on_resume])
      # Pipe events from the pipe Producer to the pipe Consumer.
      Producer.event(producer, consumer.pid, [:on_close])
      {:ok, {producer, consumer}}
    else
      _ -> {:error, "Pipe consume failed"}
    end
  end

  defp get_listen_ip(other_router_pid) when node(other_router_pid) === node() do
    "127.0.0.1"
  end

  defp get_listen_ip(_other_router_pid) do
    "0.0.0.0"
  end

  defp get_local_ip(other_router_pid) when node(other_router_pid) === node() do
    "127.0.0.1"
  end

  defp get_local_ip(_other_router_pid) do
    conf = Application.get_env(:mediasoup_elixir_demo, __MODULE__)
    conf[:pipe_transports][:announced_ip]
  end
end
