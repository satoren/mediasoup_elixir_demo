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
    :ok = SFURouter.register_producer(router_group1, producer)

    {:ok, transport2} = SFURouter.create_webrtc_transport(router_group2)

    :ok = SFURouter.try_pipe_consume(router_group2, producer.id)

    {:ok, _consumer} =
      WebRtcTransport.consume(transport2, %Mediasoup.Consumer.Options{
        producer_id: producer.id,
        rtp_capabilities: consumer_device_capabilities()
      })
  end

  test "producer stops and is unregistered when its transport closes" do
    {:ok, router_group1} = SFURouter.start("producer transport close")
    Process.link(router_group1)

    {:ok, transport} = SFURouter.create_webrtc_transport(router_group1)
    {:ok, producer} = WebRtcTransport.produce(transport, audio_producer_options())
    :ok = SFURouter.register_producer(router_group1, producer)

    ref = Process.monitor(producer.pid)
    WebRtcTransport.close(transport)

    assert_receive {:DOWN, ^ref, :process, _object, _reason}
    assert_eventually(fn -> :syn.lookup(:sfu_producers, producer.id) == :undefined end)
  end

  test "pipe consume fails for unregistered producer" do
    group_id = "unregistered producer"
    {:ok, router_group1} = SFURouter.start(group_id)
    Process.link(router_group1)

    assert {:error, _} = SFURouter.try_pipe_consume(router_group1, "unknown-producer-id")
  end

  test "close pipe producer/consumer when source producer closed" do
    group_id = "room_id2"
    {:ok, router_group1} = SFURouter.start(group_id)
    Process.link(router_group1)
    {:ok, router_group2} = SFURouter.start(group_id)
    Process.link(router_group2)
    {:ok, transport} = SFURouter.create_webrtc_transport(router_group1)
    {:ok, producer} = WebRtcTransport.produce(transport, audio_producer_options())
    :ok = SFURouter.register_producer(router_group1, producer)

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

  test "close pipe producer/consumer when all consumers closed" do
    group_id = "room_id4"
    {:ok, router_group1} = SFURouter.start(group_id)
    Process.link(router_group1)
    {:ok, router_group2} = SFURouter.start(group_id)
    Process.link(router_group2)
    {:ok, transport} = SFURouter.create_webrtc_transport(router_group1)
    {:ok, producer} = WebRtcTransport.produce(transport, audio_producer_options())
    :ok = SFURouter.register_producer(router_group1, producer)

    {:ok, transport2} = SFURouter.create_webrtc_transport(router_group2)

    :ok = SFURouter.try_pipe_consume(router_group2, producer.id)

    consumers =
      for _ <- 1..2 do
        {:ok, consumer} =
          WebRtcTransport.consume(transport2, %Mediasoup.Consumer.Options{
            producer_id: producer.id,
            rtp_capabilities: consumer_device_capabilities()
          })

        SFURouter.track_consumer(router_group2, consumer)
        consumer
      end

    # Already piped producer is reused.
    :ok = SFURouter.try_pipe_consume(router_group2, producer.id)
    assert [_] = consumer_ids(router_group1, producer.id)

    [consumer1, consumer2] = consumers

    Mediasoup.Consumer.close(consumer1)
    # The pipe is still in use by consumer2.
    assert [_] = consumer_ids(router_group1, producer.id)
    assert Map.has_key?(producer_consumer_ids(router_group2), producer.id)

    Mediasoup.Consumer.close(consumer2)
    assert_eventually(fn -> consumer_ids(router_group1, producer.id) == [] end)
    assert_eventually(fn -> producer_consumer_ids(router_group2) == %{} end)
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
    :ok = SFURouter.register_producer(router_group3, producer)

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

    # Every pipe comes directly from the source router (no multi-stage pipe).
    assert length(consumer_ids(router_group3, producer.id)) == 3

    # Other routers only have their own WebRTC consumer, no pipe consumers.
    for router <- [router_group1, router_group2, router_group4] do
      assert [_] = consumer_ids(router, producer.id)
    end
  end

  defp producer_consumer_ids(router) do
    SFURouter.router_dump(router)["mapProducerIdConsumerIds"]
  end

  defp consumer_ids(router, producer_id) do
    producer_consumer_ids(router)[producer_id]
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
end
