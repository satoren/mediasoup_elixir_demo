defmodule MediasoupElixirDemoWeb.RoomLiveTest do
  use MediasoupElixirDemoWeb.ConnCase
  import Phoenix.LiveViewTest
  import MediasoupElixirDemoWeb.SFUTestParameters

  setup %{conn: conn} do
    room = "room-live-test-#{System.unique_integer([:positive])}"
    {:ok, view, html} = live(conn, "/?roomId=#{room}")
    %{conn: conn, room: room, view: view, html: html}
  end

  # Sends a signaling event like the JS hooks do and returns the reply.
  defp call(view, event, payload \\ %{}) do
    render_hook(view, event, payload)
    assert_reply(view, reply)
    reply
  end

  defp create_transport(view) do
    %{"id" => transport_id, "dtlsParameters" => dtls_parameters} =
      call(view, "createWebRtcTransport")

    assert %{} ==
             call(view, "connectWebRtcTransport", %{
               "transportId" => transport_id,
               "dtlsParameters" => dtls_parameters
             })

    transport_id
  end

  defp create_producer(conn, room) do
    {:ok, view, _html} = live(conn, "/?roomId=#{room}")
    transport_id = create_transport(view)
    producer_option = audio_producer_options()

    %{"id" => producer_id} =
      call(view, "produce", %{
        "transportId" => transport_id,
        "kind" => producer_option.kind,
        "rtpParameters" => producer_option.rtp_parameters
      })

    %{view: view, producer_id: producer_id}
  end

  defp create_consumer(view, conn, room) do
    %{producer_id: producer_id} = create_producer(conn, room)
    transport_id = create_transport(view)

    %{"id" => consumer_id, "producerId" => ^producer_id, "kind" => "audio"} =
      call(view, "consume", %{
        "transportId" => transport_id,
        "producerId" => producer_id,
        "rtpCapabilities" => consumer_device_capabilities()
      })

    consumer_id
  end

  defp assert_eventually(fun, retries \\ 50) do
    cond do
      fun.() ->
        :ok

      retries > 0 ->
        Process.sleep(20)
        assert_eventually(fun, retries - 1)

      true ->
        flunk("condition not met")
    end
  end

  test "renders the room", %{html: html, room: room} do
    assert html =~ "Room: #{room}"
    assert html =~ "No one else is here yet."
  end

  test "toggling the microphone and camera pushes the media state", %{view: view} do
    view |> element("#toggle-audio") |> render_click()
    assert_push_event(view, "media", %{audio: true, video: false})

    view |> element("#toggle-video") |> render_click()
    assert_push_event(view, "media", %{audio: true, video: true})

    view |> element("#toggle-audio") |> render_click()
    assert_push_event(view, "media", %{audio: false, video: true})
  end

  test "media_error turns the device off", %{view: view} do
    view |> element("#toggle-video") |> render_click()
    assert_push_event(view, "media", %{video: true})

    render_hook(view, "media_error", %{"kind" => "video"})
    assert_push_event(view, "media", %{video: false})
    assert render(view) =~ "Could not start the video device."
  end

  test "shows other users and their producers", %{conn: conn, room: room, view: view} do
    %{view: producer_view, producer_id: producer_id} = create_producer(conn, room)

    assert_eventually(fn -> render(view) =~ ~s(data-producer-id="#{producer_id}") end)
    refute render(view) =~ "No one else is here yet."

    assert %{} == call(producer_view, "closeProducer", %{"producerId" => producer_id})
    assert_eventually(fn -> not (render(view) =~ producer_id) end)
  end

  test "getRouterRtpCapabilities", %{view: view} do
    assert %{"codecs" => _} = call(view, "getRouterRtpCapabilities")
  end

  test "createWebRtcTransport", %{view: view} do
    assert %{
             "dtlsParameters" => _,
             "iceParameters" => _,
             "iceCandidates" => _,
             "id" => _
           } = call(view, "createWebRtcTransport")
  end

  test "restartIce", %{view: view} do
    transport_id = create_transport(view)
    assert %{} = call(view, "restartIce", %{"transportId" => transport_id})
  end

  test "unknown transport", %{view: view} do
    assert %{"error" => _} =
             call(view, "connectWebRtcTransport", %{
               "transportId" => "unknown",
               "dtlsParameters" => %{}
             })
  end

  test "produce and closeProducer", %{conn: conn, room: room} do
    %{view: view, producer_id: producer_id} = create_producer(conn, room)
    assert %{} == call(view, "closeProducer", %{"producerId" => producer_id})
    assert %{"error" => _} = call(view, "closeProducer", %{"producerId" => producer_id})
  end

  test "pause/resumeProducer", %{conn: conn, room: room} do
    %{view: view, producer_id: producer_id} = create_producer(conn, room)
    assert %{} == call(view, "pauseProducer", %{"producerId" => producer_id})
    assert %{} == call(view, "resumeProducer", %{"producerId" => producer_id})
  end

  test "consume and closeConsumer", %{conn: conn, room: room, view: view} do
    consumer_id = create_consumer(view, conn, room)
    assert %{} == call(view, "closeConsumer", %{"consumerId" => consumer_id})
  end

  test "closeConsumer after the producer is closed", %{conn: conn, room: room, view: view} do
    %{view: producer_view, producer_id: producer_id} = create_producer(conn, room)
    transport_id = create_transport(view)

    %{"id" => consumer_id} =
      call(view, "consume", %{
        "transportId" => transport_id,
        "producerId" => producer_id,
        "rtpCapabilities" => consumer_device_capabilities()
      })

    assert %{} == call(producer_view, "closeProducer", %{"producerId" => producer_id})
    assert %{} == call(view, "closeConsumer", %{"consumerId" => consumer_id})
  end

  test "pause/resumeConsumer", %{conn: conn, room: room, view: view} do
    consumer_id = create_consumer(view, conn, room)
    assert %{} == call(view, "pauseConsumer", %{"consumerId" => consumer_id})
    assert %{} == call(view, "resumeConsumer", %{"consumerId" => consumer_id})
  end

  test "setConsumerPreferredLayers", %{conn: conn, room: room, view: view} do
    consumer_id = create_consumer(view, conn, room)

    assert %{} ==
             call(view, "setConsumerPreferredLayers", %{
               "consumerId" => consumer_id,
               "spatialLayer" => 1,
               "temporalLayer" => 1
             })
  end

  test "setConsumerPriority", %{conn: conn, room: room, view: view} do
    consumer_id = create_consumer(view, conn, room)

    assert %{} ==
             call(view, "setConsumerPriority", %{"consumerId" => consumer_id, "priority" => 1})
  end

  test "requestConsumerKeyFrame", %{conn: conn, room: room, view: view} do
    consumer_id = create_consumer(view, conn, room)
    assert %{} == call(view, "requestConsumerKeyFrame", %{"consumerId" => consumer_id})
  end
end
