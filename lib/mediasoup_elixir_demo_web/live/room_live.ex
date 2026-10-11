defmodule MediasoupElixirDemoWeb.RoomLive do
  @moduledoc """
  A voice/video chat room.

  The page renders the users of the room from Phoenix Presence. The mediasoup
  signaling (transports, produce/consume, ...) is done by the `Room` and
  `Consumer` JS hooks through `pushEvent/3` with replies, handled by
  `handle_event/3` below.
  """
  use MediasoupElixirDemoWeb, :live_view

  alias Mediasoup.{WebRtcTransport, Producer, Consumer}
  alias MediasoupElixirDemoWeb.{SFURouter, UserPresence}

  @impl true
  def mount(params, _session, socket) do
    room_id = params["roomId"] || "lobby"
    topic = "room:" <> room_id
    user_id = Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)

    socket =
      assign(socket,
        page_title: room_id,
        room_id: room_id,
        topic: topic,
        user_id: user_id,
        audio: false,
        video: false,
        users: [],
        router: nil,
        webrtc_transports: %{},
        producers: %{},
        consumers: %{}
      )

    if connected?(socket) do
      Phoenix.PubSub.subscribe(MediasoupElixirDemo.PubSub, topic)

      {:ok, _} =
        UserPresence.track(self(), topic, user_id, %{
          kind: "user",
          online_at: inspect(System.system_time(:second))
        })

      {:ok, router} = SFURouter.get_or_start(room_id)

      {:ok, socket |> assign(router: router) |> assign_users()}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="room" phx-hook="Room" class="flex min-h-screen flex-col">
      <header class="border-b border-zinc-200 px-4 py-3">
        <h1 class="text-lg font-semibold text-zinc-800">Room: {@room_id}</h1>
        <p class="text-sm text-zinc-500">You are {short_id(@user_id)}</p>
      </header>

      <main class="flex-1 p-4">
        <p :if={@users == []} id="no-users" class="text-zinc-500">
          No one else is here yet.
        </p>
        <div id="users" class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div
            :for={user <- @users}
            id={"user-#{user.id}"}
            class="rounded-lg border border-zinc-200 p-3 shadow-sm"
          >
            <p class="mb-2 text-sm font-semibold text-zinc-700">{short_id(user.id)}</p>
            <div :for={producer <- user.producers}>
              <video
                :if={producer.kind == "video"}
                id={"consumer-#{producer.id}"}
                phx-hook="Consumer"
                phx-update="ignore"
                data-producer-id={producer.id}
                class="w-full rounded bg-black"
                autoplay
                playsinline
                muted
              >
              </video>
              <audio
                :if={producer.kind == "audio"}
                id={"consumer-#{producer.id}"}
                phx-hook="Consumer"
                phx-update="ignore"
                data-producer-id={producer.id}
                autoplay
              >
              </audio>
            </div>
          </div>
        </div>
      </main>

      <footer class="sticky bottom-0 flex justify-center gap-4 border-t border-zinc-200 bg-white p-4">
        <.media_toggle id="toggle-audio" event="toggle_audio" on={@audio} label="Microphone">
          <.icon name="hero-microphone-solid" class="h-6 w-6" />
        </.media_toggle>
        <.media_toggle id="toggle-video" event="toggle_video" on={@video} label="Camera">
          <.icon :if={@video} name="hero-video-camera-solid" class="h-6 w-6" />
          <.icon :if={!@video} name="hero-video-camera-slash-solid" class="h-6 w-6" />
        </.media_toggle>
      </footer>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :on, :boolean, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp media_toggle(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={@event}
      aria-pressed={to_string(@on)}
      aria-label={@label}
      class={[
        "rounded-full p-3 text-white",
        if(@on, do: "bg-blue-600 hover:bg-blue-500", else: "bg-red-600 hover:bg-red-500")
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp short_id(user_id), do: "Guest " <> String.slice(user_id, 0, 6)

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_users(socket)}
  end

  defp assign_users(socket) do
    %{topic: topic, user_id: user_id} = socket.assigns

    users =
      UserPresence.list(topic)
      |> Enum.reject(fn {id, _} -> id == user_id end)
      |> Enum.map(fn {id, %{metas: metas}} ->
        %{id: id, producers: for(%{kind: "producer", producer: p} <- metas, do: p)}
      end)
      |> Enum.sort_by(& &1.id)

    assign(socket, users: users)
  end

  # UI events

  @impl true
  def handle_event("toggle_audio", _params, socket) do
    {:noreply, socket |> update(:audio, &(!&1)) |> push_media()}
  end

  def handle_event("toggle_video", _params, socket) do
    {:noreply, socket |> update(:video, &(!&1)) |> push_media()}
  end

  def handle_event("media_error", %{"kind" => kind}, socket) when kind in ["audio", "video"] do
    {:noreply,
     socket
     |> assign(String.to_existing_atom(kind), false)
     |> put_flash(:error, "Could not start the #{kind} device.")
     |> push_media()}
  end

  # mediasoup signaling events, called by the JS hooks with a reply callback

  def handle_event("getRouterRtpCapabilities", _params, socket) do
    socket.assigns.router
    |> SFURouter.get_router_rtp_capabilities()
    |> reply(socket)
  end

  def handle_event("createWebRtcTransport", _params, socket) do
    case SFURouter.create_webrtc_transport(socket.assigns.router) do
      {:ok, transport} ->
        reply(
          {:ok,
           %{
             "iceParameters" => WebRtcTransport.ice_parameters(transport),
             "iceCandidates" => WebRtcTransport.ice_candidates(transport),
             "dtlsParameters" => WebRtcTransport.dtls_parameters(transport),
             "id" => transport.id
           }},
          update(socket, :webrtc_transports, &Map.put(&1, transport.id, transport))
        )

      _ ->
        reply({:error, "Failed to create WebRTC transport"}, socket)
    end
  end

  def handle_event(
        "connectWebRtcTransport",
        %{"transportId" => transport_id, "dtlsParameters" => dtls_parameters},
        socket
      ) do
    with {:ok, transport} <- fetch_transport(socket, transport_id) do
      WebRtcTransport.connect(transport, %{dtlsParameters: dtls_parameters})
    end
    |> reply(socket)
  end

  def handle_event("restartIce", %{"transportId" => transport_id}, socket) do
    with {:ok, transport} <- fetch_transport(socket, transport_id) do
      WebRtcTransport.restart_ice(transport)
    end
    |> reply(socket)
  end

  def handle_event(
        "produce",
        %{"transportId" => transport_id, "kind" => kind, "rtpParameters" => rtp_parameters},
        socket
      ) do
    with {:ok, transport} <- fetch_transport(socket, transport_id),
         {:ok, producer} <-
           WebRtcTransport.produce(transport, %Producer.Options{
             kind: kind,
             rtp_parameters: rtp_parameters
           }) do
      # Unlike consumers, no on_close listener is needed: the producer process is
      # supervised by its transport and stops when the transport closes.
      SFURouter.register_producer(socket.assigns.router, producer)

      UserPresence.track(producer.pid, socket.assigns.topic, socket.assigns.user_id, %{
        kind: "producer",
        producer: %{
          id: producer.id,
          kind: kind,
          start_at: inspect(System.system_time(:second))
        }
      })

      reply(
        {:ok, %{"id" => producer.id}},
        update(socket, :producers, &Map.put(&1, producer.id, producer))
      )
    else
      error -> reply(error, socket)
    end
  end

  def handle_event("closeProducer", %{"producerId" => producer_id}, socket) do
    with {:ok, producer} <- fetch_producer(socket, producer_id) do
      close_process(fn -> Producer.close(producer) end)

      reply(:ok, update(socket, :producers, &Map.delete(&1, producer_id)))
    else
      error -> reply(error, socket)
    end
  end

  def handle_event("pauseProducer", %{"producerId" => producer_id}, socket) do
    with {:ok, producer} <- fetch_producer(socket, producer_id) do
      Producer.pause(producer)
    end
    |> reply(socket)
  end

  def handle_event("resumeProducer", %{"producerId" => producer_id}, socket) do
    with {:ok, producer} <- fetch_producer(socket, producer_id) do
      Producer.resume(producer)
    end
    |> reply(socket)
  end

  def handle_event(
        "consume",
        %{
          "transportId" => transport_id,
          "producerId" => producer_id,
          "rtpCapabilities" => rtp_capabilities
        } = params,
        socket
      ) do
    with {:ok, transport} <- fetch_transport(socket, transport_id),
         {:ok, consumer} <-
           try_consume_with_pipe(socket.assigns.router, transport, %Consumer.Options{
             producer_id: producer_id,
             rtp_capabilities: rtp_capabilities,
             paused: Map.get(params, "paused", false)
           }) do
      # TODO: Should it be done in a library?
      # Stop the consumer process when it is closed by its producer or transport.
      Consumer.event(consumer, consumer.pid, [:on_close])
      SFURouter.track_consumer(socket.assigns.router, consumer)

      reply(
        {:ok,
         %{
           "id" => consumer.id,
           "producerId" => producer_id,
           "kind" => consumer.kind,
           "rtpParameters" => consumer.rtp_parameters,
           "type" => consumer.type,
           "producerPaused" => Consumer.producer_paused?(consumer)
         }},
        update(socket, :consumers, &Map.put(&1, consumer.id, consumer))
      )
    else
      error -> reply(error, socket)
    end
  end

  def handle_event("closeConsumer", %{"consumerId" => consumer_id}, socket) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id) do
      # The consumer may already be gone, closed together with its producer.
      close_process(fn -> Consumer.close(consumer) end)

      reply(:ok, update(socket, :consumers, &Map.delete(&1, consumer_id)))
    else
      error -> reply(error, socket)
    end
  end

  def handle_event("pauseConsumer", %{"consumerId" => consumer_id}, socket) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id) do
      Consumer.pause(consumer)
    end
    |> reply(socket)
  end

  def handle_event("resumeConsumer", %{"consumerId" => consumer_id}, socket) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id) do
      Consumer.resume(consumer)
    end
    |> reply(socket)
  end

  def handle_event(
        "setConsumerPreferredLayers",
        %{"consumerId" => consumer_id, "spatialLayer" => spatial_layer} = params,
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id) do
      Consumer.set_preferred_layers(consumer, %{
        spatialLayer: spatial_layer,
        temporalLayer: params["temporalLayer"]
      })
    end
    |> reply(socket)
  end

  def handle_event(
        "setConsumerPriority",
        %{"consumerId" => consumer_id, "priority" => priority},
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id) do
      Consumer.set_priority(consumer, priority)
    end
    |> reply(socket)
  end

  def handle_event("requestConsumerKeyFrame", %{"consumerId" => consumer_id}, socket) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id) do
      Consumer.request_key_frame(consumer)
    end
    |> reply(socket)
  end

  defp push_media(socket) do
    push_event(socket, "media", %{audio: socket.assigns.audio, video: socket.assigns.video})
  end

  # LiveView replies must be maps.
  defp reply(:ok, socket), do: {:reply, %{}, socket}
  defp reply({:ok}, socket), do: {:reply, %{}, socket}
  defp reply({:ok, %{} = payload}, socket), do: {:reply, payload, socket}
  defp reply({:error, reason}, socket) when is_binary(reason), do: error_reply(reason, socket)
  defp reply({:error, reason}, socket), do: error_reply(inspect(reason), socket)
  defp reply(other, socket), do: error_reply(inspect(other), socket)

  defp error_reply(reason, socket), do: {:reply, %{"error" => reason}, socket}

  defp close_process(fun) do
    fun.()
  catch
    :exit, _ -> :ok
  end

  defp try_consume_with_pipe(router, transport, consumer_option) do
    case WebRtcTransport.consume(transport, consumer_option) do
      {:ok, consumer} ->
        {:ok, consumer}

      {:error, _reason} ->
        case SFURouter.try_pipe_consume(router, consumer_option.producer_id) do
          :ok -> WebRtcTransport.consume(transport, consumer_option)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp fetch_transport(socket, transport_id) do
    case Map.fetch(socket.assigns.webrtc_transports, transport_id) do
      :error -> {:error, "Transport with id \"#{transport_id}\" not found"}
      {:ok, transport} -> {:ok, transport}
    end
  end

  defp fetch_producer(socket, producer_id) do
    case Map.fetch(socket.assigns.producers, producer_id) do
      :error -> {:error, "Producer with id \"#{producer_id}\" not found"}
      {:ok, producer} -> {:ok, producer}
    end
  end

  defp fetch_consumer(socket, consumer_id) do
    case Map.fetch(socket.assigns.consumers, consumer_id) do
      :error -> {:error, "Consumer with id \"#{consumer_id}\" not found"}
      {:ok, consumer} -> {:ok, consumer}
    end
  end
end
