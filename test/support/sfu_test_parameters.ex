defmodule MediasoupElixirDemoWeb.SFUTestParameters do
  def audio_producer_options() do
    %Mediasoup.Producer.Options{
      kind: "audio",
      rtp_parameters: %{
        mid: "AUDIO",
        codecs: [
          %{
            mimeType: "audio/opus",
            payloadType: 111,
            clockRate: 48000,
            channels: 2,
            parameters: %{
              "useinbandfec" => 1,
              "usedtx" => 1,
              "foo" => "222.222",
              "bar" => "333"
            },
            rtcpFeedback: []
          }
        ],
        headerExtensions: [
          %{
            uri: "urn:ietf:params:rtp-hdrext:sdes:mid",
            id: 10,
            encrypt: false
          },
          %{
            uri: "urn:ietf:params:rtp-hdrext:ssrc-audio-level",
            id: 12,
            encrypt: false
          }
        ],
        encodings: [
          %{
            ssrc: 11_111_111,
            codecPayloadType: 111
          }
        ],
        rtcp: %{
          cname: "FOOBAR",
          reducedSize: true
        }
      }
    }
  end

  def consumer_device_capabilities() do
    %{
      codecs: [
        %{
          kind: "audio",
          mimeType: "audio/opus",
          preferredPayloadType: 100,
          clockRate: 48000,
          channels: 2,
          parameters: %{},
          rtcpFeedback: []
        },
        %{
          kind: "video",
          mimeType: "video/H264",
          preferredPayloadType: 101,
          clockRate: 90000,
          parameters: %{
            "level-asymmetry-allowed" => 1,
            "packetization-mode" => 1,
            "profile-level-id" => "4d0032"
          },
          rtcpFeedback: [
            %{type: "nack"},
            %{type: "nack", parameter: "pli"},
            %{type: "ccm", parameter: "fir"},
            %{type: "goog-remb"}
          ]
        },
        %{
          kind: "video",
          mimeType: "video/rtx",
          payloadType: 102,
          clockRate: 90000,
          parameters: %{
            "apt" => 112
          },
          rtcpFeedback: []
        }
      ],
      headerExtensions: [
        %{
          kind: "audio",
          uri: "urn:ietf:params:rtp-hdrext:sdes:mid",
          preferredId: 1,
          preferredEncrypt: false,
          direction: "sendrecv"
        },
        %{
          kind: "video",
          uri: "urn:ietf:params:rtp-hdrext:sdes:mid",
          preferredId: 1,
          preferredEncrypt: false,
          direction: "sendrecv"
        },
        %{
          kind: "video",
          uri: "urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id",
          preferredId: 2,
          preferredEncrypt: false,
          direction: "sendrecv"
        },
        %{
          kind: "audio",
          uri: "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",
          preferredId: 4,
          preferredEncrypt: false,
          direction: "sendrecv"
        },
        %{
          kind: "video",
          uri: "http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time",
          preferredId: 4,
          preferredEncrypt: false,
          direction: "sendrecv"
        },
        %{
          kind: "audio",
          uri: "urn:ietf:params:rtp-hdrext:ssrc-audio-level",
          preferredId: 10,
          preferredEncrypt: false,
          direction: "sendrecv"
        },
        %{
          kind: "video",
          uri: "urn:3gpp:video-orientation",
          preferredId: 11,
          preferredEncrypt: false,
          direction: "sendrecv"
        },
        %{
          kind: "video",
          uri: "urn:ietf:params:rtp-hdrext:toffset",
          preferredId: 12,
          preferredEncrypt: false,
          direction: "sendrecv"
        }
      ],
      fecMechanisms: []
    }
  end
end
