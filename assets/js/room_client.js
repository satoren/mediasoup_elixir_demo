import { Device } from "mediasoup-client";

// mediasoup-client wrapper. `push(event, payload)` sends a signaling event to
// the RoomLive process and resolves with its reply.
export class RoomClient {
	constructor(push) {
		this.push = push;
		this.ready = this.init();
	}

	async request(event, payload = {}) {
		const reply = await this.push(event, payload);
		if (reply?.error) {
			throw new Error(`${event}: ${reply.error}`);
		}
		return reply;
	}

	async init() {
		const routerRtpCapabilities = await this.request(
			"getRouterRtpCapabilities",
		);
		this.device = new Device();
		await this.device.load({ routerRtpCapabilities });
		this.sendTransport = await this.createTransport("send");
		this.recvTransport = await this.createTransport("recv");
	}

	async createTransport(direction) {
		const params = await this.request("createWebRtcTransport");
		const transport =
			direction === "send"
				? this.device.createSendTransport(params)
				: this.device.createRecvTransport(params);

		transport.on("connect", ({ dtlsParameters }, callback, errback) => {
			this.request("connectWebRtcTransport", {
				transportId: transport.id,
				dtlsParameters,
			}).then(() => callback(), errback);
		});

		if (direction === "send") {
			transport.on("produce", ({ kind, rtpParameters }, callback, errback) => {
				this.request("produce", {
					transportId: transport.id,
					kind,
					rtpParameters,
				}).then(({ id }) => callback({ id }), errback);
			});
		}

		return transport;
	}

	async produce(track) {
		await this.ready;
		return this.sendTransport.produce({ track, stopTracks: false });
	}

	async closeProducer(producer) {
		producer.close();
		await this.request("closeProducer", { producerId: producer.id });
	}

	async consume(producerId) {
		await this.ready;
		const params = await this.request("consume", {
			transportId: this.recvTransport.id,
			producerId,
			rtpCapabilities: this.device.rtpCapabilities,
			paused: true,
		});
		const consumer = await this.recvTransport.consume(params);
		await this.request("resumeConsumer", { consumerId: consumer.id });
		return consumer;
	}

	async closeConsumer(consumer) {
		consumer.close();
		await this.request("closeConsumer", { consumerId: consumer.id });
	}
}
