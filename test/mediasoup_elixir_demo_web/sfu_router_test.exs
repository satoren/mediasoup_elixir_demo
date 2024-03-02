defmodule MediasoupElixirDemoWeb.SFURouterTest do
  use ExUnit.Case
  alias Mediasoup.WebRtcTransport
  alias MediasoupElixirDemoWeb.SFURouter

  import MediasoupElixirDemoWeb.SFUTestParameters

  test "start" do
    {:ok, router_group1} = SFURouter.start("room_id")
    Process.link(router_group1)
    {:ok, router_group2} = SFURouter.start("room_id")
    Process.link(router_group2)
  end

  test "join & leave" do
    {:ok, router_group1} = SFURouter.start("room_id")
    Process.link(router_group1)
    {:ok, router_group2} = SFURouter.start("room_id")
    Process.sleep(1)
    Process.exit(router_group2, :shutdown)
    Process.sleep(1)
  end

  test "get_router_rtp_capabilities" do
    {:ok, router_group1} = SFURouter.start("room_id")
    {:ok, %{"codecs" => _}} = SFURouter.get_router_rtp_capabilities(router_group1)
  end

  test "produce & consume" do
    {:ok, router_group1} = SFURouter.start("room_id")
    Process.link(router_group1)

    {:ok, transport} = SFURouter.create_webrtc_transport(router_group1)
    {:ok, transport2} = SFURouter.create_webrtc_transport(router_group1)

    {:ok, producer} = WebRtcTransport.produce(transport, audio_producer_options())

    {:ok, _consumer} =
      WebRtcTransport.consume(transport2, %Mediasoup.Consumer.Options{
        producer_id: producer.id,
        rtp_capabilities: consumer_device_capabilities()
      })
  end

  test "produce & consume with pipe" do
    group_id = "produce & consume with pipe"
    {:ok, router_group1} = SFURouter.start(group_id)
    Process.link(router_group1)
    {:ok, router_group2} = SFURouter.start(group_id)
    Process.link(router_group2)
    {:ok, router_group3} = SFURouter.start(group_id)
    Process.link(router_group3)

    {:ok, transport} = SFURouter.create_webrtc_transport(router_group1)
    {:ok, producer} = WebRtcTransport.produce(transport, audio_producer_options())

    {:ok, transport2} = SFURouter.create_webrtc_transport(router_group2)

    :ok = SFURouter.try_pipe_consume(router_group2, producer.id)

    {:ok, _consumer} =
      WebRtcTransport.consume(transport2, %Mediasoup.Consumer.Options{
        producer_id: producer.id,
        rtp_capabilities: consumer_device_capabilities()
      })
  end

  test "close pipe producer/consumer when source producer closed" do
    group_id = "room_id2"
    {:ok, router_group1} = SFURouter.start(group_id)
    Process.link(router_group1)
    {:ok, router_group2} = SFURouter.start(group_id)
    Process.link(router_group2)
    {:ok, transport} = SFURouter.create_webrtc_transport(router_group1)
    {:ok, producer} = WebRtcTransport.produce(transport, audio_producer_options())

    {:ok, transport2} = SFURouter.create_webrtc_transport(router_group2)

    :ok = SFURouter.try_pipe_consume(router_group2, producer.id)

    {:ok, consumer} =
      WebRtcTransport.consume(transport2, %Mediasoup.Consumer.Options{
        producer_id: producer.id,
        rtp_capabilities: consumer_device_capabilities()
      })

    # TODO: Should it be done in a library?
    Mediasoup.Consumer.event(consumer, consumer.pid, [:on_close])

    ref = Process.monitor(consumer.pid)

    Mediasoup.Producer.close(producer)

    assert_receive {:DOWN, ^ref, :process, _object, :normal}
  end

  test "produce & 2 consume with pipe" do
    group_id = "room_id3"
    {:ok, router_group1} = SFURouter.start(group_id)
    Process.link(router_group1)
    {:ok, router_group2} = SFURouter.start(group_id)
    Process.link(router_group2)
    {:ok, router_group3} = SFURouter.start(group_id)
    Process.link(router_group3)

    {:ok, transport} = SFURouter.create_webrtc_transport(router_group3)
    {:ok, producer} = WebRtcTransport.produce(transport, audio_producer_options())

    {:ok, transport2} = SFURouter.create_webrtc_transport(router_group2)

    {:ok, transport3} = SFURouter.create_webrtc_transport(router_group1)

    :ok = SFURouter.try_pipe_consume(router_group2, producer.id)

    {:ok, _consumer} =
      WebRtcTransport.consume(transport2, %Mediasoup.Consumer.Options{
        producer_id: producer.id,
        rtp_capabilities: consumer_device_capabilities()
      })

    :ok = SFURouter.try_pipe_consume(router_group1, producer.id)

    {:ok, _consumer} =
      WebRtcTransport.consume(transport3, %Mediasoup.Consumer.Options{
        producer_id: producer.id,
        rtp_capabilities: consumer_device_capabilities()
      })

    {:ok, router_group4} = SFURouter.start(group_id)
    Process.link(router_group4)
    {:ok, transport4} = SFURouter.create_webrtc_transport(router_group4)

    :ok = SFURouter.try_pipe_consume(router_group4, producer.id)

    {:ok, _consumer} =
      WebRtcTransport.consume(transport4, %Mediasoup.Consumer.Options{
        producer_id: producer.id,
        rtp_capabilities: consumer_device_capabilities()
      })
  end
end
