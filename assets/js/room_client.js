import { Device } from "mediasoup-client";

// Raised for requests that were cut off because the client was closed, e.g.
// when the LiveView socket disconnected. These are retried after reconnecting.
export class ClientClosedError extends Error {
	constructor() {
		super("RoomClient closed");
		this.name = "ClientClosedError";
	}
}

// mediasoup-client wrapper. `push(event, payload)` sends a signaling event to
// the RoomLive process and resolves with its reply.
export class RoomClient {
	constructor(push) {
		this.push = push;
		this.closed = false;
		this.pending = new Set();
		this.transports = [];
		this.ready = this.init();
	}

	request(event, payload = {}) {
		if (this.closed) {
			return Promise.reject(new ClientClosedError());
		}
		return new Promise((resolve, reject) => {
			const pending = { reject };
			this.pending.add(pending);
			this.push(event, payload).then((reply) => {
				if (!this.pending.delete(pending)) {
					return;
				}
				if (reply?.error) {
					reject(new Error(`${event}: ${reply.error}`));
				} else {
					resolve(reply);
				}
			});
		});
	}

	// Closes the transports, and with them all producers and consumers, and
	// rejects the requests still waiting for a reply.
	close() {
		this.closed = true;
		for (const { reject } of this.pending) {
			reject(new ClientClosedError());
		}
		this.pending.clear();
		for (const transport of this.transports) {
			transport.close();
		}
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
		this.transports.push(transport);
		if (this.closed) {
			transport.close();
			throw new ClientClosedError();
		}

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
