defmodule MediasoupElixirDemoWeb.RoomChannel do
  use MediasoupElixirDemoWeb, :channel

  alias Mediasoup.{WebRtcTransport, Producer, Consumer}
  alias MediasoupElixirDemoWeb.{SFURouter, UserPresence}

  @impl true
  def join("room:" <> room_id, _payload, socket) do
    send(self(), :after_join)

    {:ok,
     socket
     |> assign(
       room_id: room_id,
       webrtc_transports: %{},
       producers: %{},
       consumers: %{}
     )}
  end

  @impl true
  @spec handle_info(
          :after_join | {:DOWN, any(), :process, any(), any()},
          atom() | %{:assigns => atom() | map(), optional(any()) => any()}
        ) :: {:noreply, atom() | %{:assigns => atom() | map(), optional(any()) => any()}}
  def handle_info(:after_join, socket) do
    push(socket, "user_info", %{id: socket.assigns.user_id})

    UserPresence.track(socket, socket.assigns.user_id, %{
      kind: "user",
      online_at: inspect(System.system_time(:second))
    })

    push(socket, "presence_state", UserPresence.list(socket))
    {:ok, router} = SFURouter.get_or_start(socket.assigns.room_id)
    {:noreply, socket |> assign(router: router)}
  end

  @impl true
  def handle_in("getRouterRtpCapabilities", _payload, socket) do
    capabilities = SFURouter.get_router_rtp_capabilities(socket.assigns.router)
    {:reply, capabilities, socket}
  end

  def handle_in("createWebRtcTransport", _payload, socket) do
    case SFURouter.create_webrtc_transport(socket.assigns.router) do
      {:ok, transport} ->
        {:reply,
         {:ok,
          %{
            "iceParameters" => WebRtcTransport.ice_parameters(transport),
            "iceCandidates" => WebRtcTransport.ice_candidates(transport),
            "dtlsParameters" => WebRtcTransport.dtls_parameters(transport),
            "id" => transport.id
          }},
         socket
         |> assign(
           webrtc_transports: Map.put(socket.assigns.webrtc_transports, transport.id, transport)
         )}

      _ ->
        {:reply, {:error, "Failed to create WebRTC transport"}, socket}
    end
  end

  def handle_in(
        "connectWebRtcTransport",
        %{"transportId" => transport_id, "dtlsParameters" => dtls_parameters} = _payload,
        socket
      ) do
    with {:ok, transport} <- fetch_transport(socket, transport_id),
         {:ok} <-
           WebRtcTransport.connect(transport, %{
             dtlsParameters: dtls_parameters
           }) do
      {:reply, :ok, socket}
    else
      {:error, error} ->
        {:reply, {:error, error}, socket}
    end
  end

  def handle_in(
        "restartIce",
        %{"transportId" => transport_id} = _payload,
        socket
      ) do
    with {:ok, transport} <- fetch_transport(socket, transport_id),
         {:ok, ice_parameters} <-
           WebRtcTransport.restart_ice(transport) do
      {:reply, {:ok, ice_parameters}, socket}
    else
      {:error, error} ->
        {:reply, {:error, error}, socket}
    end
  end

  def handle_in(
        "produce",
        %{"transportId" => transport_id, "kind" => kind, "rtpParameters" => rtp_parameters} =
          _payload,
        socket
      ) do
    with {:ok, transport} <- fetch_transport(socket, transport_id),
         {:ok, producer} <-
           WebRtcTransport.produce(transport, %Mediasoup.Producer.Options{
             kind: kind,
             rtp_parameters: rtp_parameters
           }) do
      # TODO: Should it be done in a library?
      #      Producer.event(producer, producer.pid, [:on_close])

      UserPresence.track(
        producer.pid,
        socket.topic,
        socket.assigns.user_id,
        %{
          kind: "producer",
          producer: %{
            id: producer.id,
            kind: kind,
            start_at: inspect(System.system_time(:second))
          }
        }
      )

      {:reply, {:ok, %{"id" => producer.id}},
       socket
       |> assign(producers: Map.put(socket.assigns.producers, producer.id, producer))}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "closeProducer",
        %{"producerId" => producer_id} =
          _payload,
        socket
      ) do
    with {:ok, producer} <- fetch_producer(socket, producer_id),
         :ok <- Producer.close(producer) do
      {:reply, :ok,
       socket
       |> assign(producers: Map.delete(socket.assigns.producers, producer_id))}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "pauseProducer",
        %{"producerId" => producer_id} =
          _payload,
        socket
      ) do
    with {:ok, producer} <- fetch_producer(socket, producer_id),
         {:ok} <- Producer.pause(producer) do
      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "resumeProducer",
        %{"producerId" => producer_id} =
          _payload,
        socket
      ) do
    with {:ok, producer} <- fetch_producer(socket, producer_id),
         {:ok} <- Producer.resume(producer) do
      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "consume",
        %{
          "transportId" => transport_id,
          "producerId" => producer_id,
          "rtpCapabilities" => rtp_capabilities
        } =
          payload,
        socket
      ) do
    with {:ok, transport} <- fetch_transport(socket, transport_id),
         {:ok, consumer} <-
           try_consume_with_pipe(socket.assigns.router, transport, %Consumer.Options{
             producer_id: producer_id,
             rtp_capabilities: rtp_capabilities,
             paused: Map.get(payload, "paused", false)
           }) do
      # TODO: Should it be done in a library?
      #      Consumer.event(consumer, consumer.pid, [:on_close])

      {:reply,
       {:ok,
        %{
          "id" => consumer.id,
          "producerId" => producer_id,
          "kind" => consumer.kind,
          "rtpParameters" => consumer.rtp_parameters,
          "type" => consumer.type,
          "producerPaused" => Consumer.producer_paused?(consumer)
        }},
       socket
       |> assign(consumers: Map.put(socket.assigns.consumers, consumer.id, consumer))}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "closeConsumer",
        %{"consumerId" => consumer_id} =
          _payload,
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id),
         :ok <- Consumer.close(consumer) do
      {:reply, :ok,
       socket
       |> assign(consumers: Map.delete(socket.assigns.consumers, consumer_id))}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "pauseConsumer",
        %{"consumerId" => consumer_id} =
          _payload,
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id),
         {:ok} <- Consumer.pause(consumer) do
      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "resumeConsumer",
        %{"consumerId" => consumer_id} =
          _payload,
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id),
         {:ok} <- Consumer.resume(consumer) do
      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "setConsumerPreferredLayers",
        %{"consumerId" => consumer_id, "spatialLayer" => spatial_layer} =
          payload,
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id),
         {:ok} <-
           Consumer.set_preferred_layers(consumer, %{
             spatialLayer: spatial_layer,
             temporalLayer: payload["temporalLayer"]
           }) do
      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "setConsumerPriority",
        %{"consumerId" => consumer_id, "priority" => priority} =
          _payload,
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id),
         {:ok} <- Consumer.set_priority(consumer, priority) do
      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  def handle_in(
        "requestConsumerKeyFrame",
        %{"consumerId" => consumer_id} =
          _payload,
        socket
      ) do
    with {:ok, consumer} <- fetch_consumer(socket, consumer_id),
         {:ok} <- Consumer.request_key_frame(consumer) do
      {:reply, :ok, socket}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, socket}
    end
  end

  defp try_consume_with_pipe(router, transport, consumer_option) do
    case WebRtcTransport.consume(transport, consumer_option) do
      {:ok, consumer} ->
        {:ok, consumer}

      {:error, _reason} ->
        case SFURouter.try_pipe_consume(router, consumer_option) do
          :ok ->
            WebRtcTransport.consume(transport, consumer_option)

          {:error, reason} ->
            {:error, reason}
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
