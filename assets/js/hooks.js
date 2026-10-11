import { RoomClient } from "./room_client";

let resolveClient;
const clientReady = new Promise((resolve) => {
	resolveClient = resolve;
});

// Mounted on the room container. Owns the mediasoup client and the local
// microphone/camera, which the server turns on and off with "media" events.
const Room = {
	mounted() {
		const push = (event, payload) =>
			new Promise((resolve) => this.pushEvent(event, payload, resolve));
		this.client = new RoomClient(push);
		this.client.ready.catch((e) => console.error(e));
		resolveClient(this.client);

		this.media = {};
		this.queues = {};
		this.handleEvent("media", ({ audio, video }) => {
			this.setMedia("audio", audio);
			this.setMedia("video", video);
		});
	},

	// The server side state (transports, producers, ...) is gone after a
	// reconnect, so start over.
	reconnected() {
		window.location.reload();
	},

	setMedia(kind, enabled) {
		const previous = this.queues[kind] || Promise.resolve();
		this.queues[kind] = previous
			.then(() => this.applyMedia(kind, enabled))
			.catch((e) => {
				console.error(e);
				this.pushEvent("media_error", { kind });
			});
	},

	async applyMedia(kind, enabled) {
		const current = this.media[kind];
		if (enabled && !current) {
			const stream = await navigator.mediaDevices.getUserMedia({
				[kind]: true,
			});
			const track = stream.getTracks()[0];
			try {
				const producer = await this.client.produce(track);
				this.media[kind] = { track, producer };
			} catch (e) {
				track.stop();
				throw e;
			}
		} else if (!enabled && current) {
			delete this.media[kind];
			current.track.stop();
			await this.client.closeProducer(current.producer);
		}
	},
};

// Mounted on each <audio>/<video> element of a remote producer.
const Consumer = {
	mounted() {
		this.consumer = clientReady
			.then((client) => client.consume(this.el.dataset.producerId))
			.then((consumer) => {
				this.el.srcObject = new MediaStream([consumer.track]);
				// Exposed for the end-to-end tests.
				this.el.consumer = consumer;
				return consumer;
			});
		this.consumer.catch((e) => console.error(e));
	},

	destroyed() {
		Promise.all([clientReady, this.consumer])
			.then(([client, consumer]) => client.closeConsumer(consumer))
			.catch(() => {});
	},
};

export const Hooks = { Room, Consumer };
