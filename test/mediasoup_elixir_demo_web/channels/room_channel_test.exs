defmodule MediasoupElixirDemoWeb.RoomChannelTest do
  use MediasoupElixirDemoWeb.ChannelCase
  import MediasoupElixirDemoWeb.SFUTestParameters

  setup do
    {:ok, _, socket} =
      MediasoupElixirDemoWeb.UserSocket
      |> socket("user_id", %{user_id: "user_id"})
      |> subscribe_and_join(MediasoupElixirDemoWeb.RoomChannel, "room:lobby")

    %{socket: socket}
  end

  test "getRouterRtpCapabilities", %{socket: socket} do
    ref = push(socket, "getRouterRtpCapabilities")

    assert_reply ref, :ok, %{
      "codecs" => _
    }
  end

  test "createWebRtcTransport", %{socket: socket} do
    ref = push(socket, "createWebRtcTransport")

    assert_reply ref, :ok, %{
      "dtlsParameters" => _,
      "iceParameters" => _,
      "id" => _
    }
  end

  test "connectWebRtcTransport", %{socket: socket} do
    ref = push(socket, "createWebRtcTransport")

    assert_reply ref, :ok, %{
      "dtlsParameters" => dtls_parameters,
      "iceParameters" => _,
      "id" => transport_id
    }

    ref =
      push(socket, "connectWebRtcTransport", %{
        "transportId" => transport_id,
        "dtlsParameters" => dtls_parameters
      })

    assert_reply ref, :ok
  end

  test "restartIce", %{socket: socket} do
    ref = push(socket, "createWebRtcTransport")

    assert_reply ref, :ok, %{
      "dtlsParameters" => dtls_parameters,
      "iceParameters" => _,
      "id" => transport_id
    }

    ref =
      push(socket, "connectWebRtcTransport", %{
        "transportId" => transport_id,
        "dtlsParameters" => dtls_parameters
      })

    assert_reply ref, :ok

    ref =
      push(socket, "restartIce", %{
        "transportId" => transport_id
      })

    assert_reply ref, :ok
  end

  test "produce", %{socket: socket} do
    ref = push(socket, "createWebRtcTransport")

    assert_reply ref, :ok, %{
      "dtlsParameters" => dtls_parameters,
      "iceParameters" => _,
      "id" => transport_id
    }

    ref =
      push(socket, "connectWebRtcTransport", %{
        "transportId" => transport_id,
        "dtlsParameters" => dtls_parameters
      })

    assert_reply ref, :ok

    producer_option = audio_producer_options()

    ref =
      push(socket, "produce", %{
        "transportId" => transport_id,
        "kind" => producer_option.kind,
        "rtpParameters" => producer_option.rtp_parameters
      })

    assert_reply ref, :ok, %{
      "id" => _producer_id
    }
  end

  defp create_producer() do
    {:ok, _, socket} =
      MediasoupElixirDemoWeb.UserSocket
      |> socket("producer_user_id", %{user_id: "producer_user_id"})
      |> subscribe_and_join(MediasoupElixirDemoWeb.RoomChannel, "room:lobby")

    ref = push(socket, "createWebRtcTransport")

    assert_reply ref, :ok, %{
      "dtlsParameters" => dtls_parameters,
      "iceParameters" => _,
      "id" => transport_id
    }

    ref =
      push(socket, "connectWebRtcTransport", %{
        "transportId" => transport_id,
        "dtlsParameters" => dtls_parameters
      })

    assert_reply ref, :ok

    producer_option = audio_producer_options()

    ref =
      push(socket, "produce", %{
        "transportId" => transport_id,
        "kind" => producer_option.kind,
        "rtpParameters" => producer_option.rtp_parameters
      })

    assert_reply ref, :ok, %{
      "id" => producer_id
    }

    %{producer_id: producer_id, socket: socket}
  end

  defp create_consumer(socket) do
    %{producer_id: producer_id, socket: producer_socket} = create_producer()

    ref = push(socket, "createWebRtcTransport")

    assert_reply ref, :ok, %{
      "dtlsParameters" => dtls_parameters,
      "iceParameters" => _,
      "id" => transport_id
    }

    ref =
      push(socket, "connectWebRtcTransport", %{
        "transportId" => transport_id,
        "dtlsParameters" => dtls_parameters
      })

    assert_reply ref, :ok

    ref =
      push(socket, "consume", %{
        "transportId" => transport_id,
        "producerId" => producer_id,
        "rtpCapabilities" => consumer_device_capabilities()
      })

    assert_reply ref, :ok, %{"id" => consumer_id}
    %{producer_id: producer_id, socket: producer_socket, consumer_id: consumer_id}
  end

  test "closeProducer", %{socket: _socket} do
    %{producer_id: producer_id, socket: socket} = create_producer()

    ref = push(socket, "closeProducer", %{"producerId" => producer_id})
    assert_reply ref, :ok
  end

  test "pause/resumeProducer", %{socket: _socket} do
    %{producer_id: producer_id, socket: socket} = create_producer()

    ref =
      push(socket, "pauseProducer", %{
        "producerId" => producer_id
      })

    assert_reply ref, :ok

    ref =
      push(socket, "resumeProducer", %{
        "producerId" => producer_id
      })

    assert_reply ref, :ok
  end

  test "consume", %{socket: socket} do
    %{producer_id: producer_id} = create_producer()

    ref = push(socket, "createWebRtcTransport")

    assert_reply ref, :ok, %{
      "dtlsParameters" => dtls_parameters,
      "iceParameters" => _,
      "id" => transport_id
    }

    ref =
      push(socket, "connectWebRtcTransport", %{
        "transportId" => transport_id,
        "dtlsParameters" => dtls_parameters
      })

    assert_reply ref, :ok

    ref =
      push(socket, "consume", %{
        "transportId" => transport_id,
        "producerId" => producer_id,
        "rtpCapabilities" => consumer_device_capabilities()
      })

    assert_reply ref, :ok, %{"id" => _consumer_id}
  end

  test "closeConsumer", %{socket: socket} do
    %{consumer_id: consumer_id} = create_consumer(socket)

    ref =
      push(socket, "closeConsumer", %{
        "consumerId" => consumer_id
      })

    assert_reply ref, :ok
  end

  test "pause/resumeConsumer", %{socket: socket} do
    %{consumer_id: consumer_id} = create_consumer(socket)

    ref =
      push(socket, "pauseConsumer", %{
        "consumerId" => consumer_id
      })

    assert_reply ref, :ok

    ref =
      push(socket, "resumeConsumer", %{
        "consumerId" => consumer_id
      })

    assert_reply ref, :ok
  end

  test "setConsumerPreferredLayers", %{socket: socket} do
    %{consumer_id: consumer_id} = create_consumer(socket)

    ref =
      push(socket, "setConsumerPreferredLayers", %{
        "consumerId" => consumer_id,
        "spatialLayer" => 1,
        "temporalLayer" => 1
      })

    assert_reply ref, :ok
  end

  test "setConsumerPriority", %{socket: socket} do
    %{consumer_id: consumer_id} = create_consumer(socket)

    ref =
      push(socket, "setConsumerPriority", %{
        "consumerId" => consumer_id,
        "priority" => 1
      })

    assert_reply ref, :ok
  end

  test "requestConsumerKeyFrame", %{socket: socket} do
    %{consumer_id: consumer_id} = create_consumer(socket)

    ref =
      push(socket, "requestConsumerKeyFrame", %{
        "consumerId" => consumer_id
      })

    assert_reply ref, :ok
  end
end
