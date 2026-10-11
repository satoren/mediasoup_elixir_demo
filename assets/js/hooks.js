import { ClientClosedError, RoomClient } from "./room_client";

// The RoomClient of the current LiveView connection. Replaced on reconnect,
// because the server side state (transports, producers, ...) belongs to the
// RoomLive process of a connection.
let clientPromise;
let resolveClient;
const resetClient = () => {
	clientPromise = new Promise((resolve) => {
		resolveClient = resolve;
	});
};
resetClient();

// Whether the microphone/camera should be on. Sent as connect params so that
// RoomLive restores the toggles after a reconnect.
const desiredMedia = { audio: false, video: false };
export const connectParams = () => ({ media: desiredMedia });

const logError = (e) => {
	if (!(e instanceof ClientClosedError)) {
		console.error(e);
	}
};

// Mounted on the room container. Owns the mediasoup client and the local
// microphone/camera, which the server turns on and off with "media" events.
const Room = {
	mounted() {
		this.media = {};
		this.queues = {};
		this.startClient();

		this.handleEvent("media", ({ audio, video }) => {
			desiredMedia.audio = audio;
			desiredMedia.video = video;
			this.sync("audio");
			this.sync("video");
		});
	},

	disconnected() {
		resetClient();
		this.client.close();
		// The producers were closed with the transports; the tracks are kept.
		for (const media of Object.values(this.media)) {
			media.producer = null;
		}
	},

	reconnected() {
		this.startClient();
		this.sync("audio");
		this.sync("video");
	},

	startClient() {
		const push = (event, payload) =>
			new Promise((resolve) => this.pushEvent(event, payload, resolve));
		this.client = new RoomClient(push);
		this.client.ready.catch(logError);
		resolveClient(this.client);
	},

	// Brings the local `kind` device in line with `desiredMedia`, one change
	// at a time per kind.
	sync(kind) {
		const previous = this.queues[kind] || Promise.resolve();
		this.queues[kind] = previous
			.then(() => this.applyMedia(kind, desiredMedia[kind]))
			.catch((e) => {
				if (e instanceof ClientClosedError) {
					return;
				}
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
			this.media[kind] = { track: stream.getTracks()[0], producer: null };
			await this.produce(kind);
		} else if (enabled && !current.producer) {
			await this.produce(kind);
		} else if (!enabled && current) {
			delete this.media[kind];
			current.track.stop();
			if (current.producer) {
				await this.client.closeProducer(current.producer);
			}
		}
	},

	async produce(kind) {
		const media = this.media[kind];
		try {
			media.producer = await this.client.produce(media.track);
		} catch (e) {
			if (!(e instanceof ClientClosedError)) {
				delete this.media[kind];
				media.track.stop();
			}
			throw e;
		}
	},
};

// Mounted on each <audio>/<video> element of a remote producer.
const Consumer = {
	mounted() {
		this.generation = 0;
		this.consume();
	},

	// The consumer was closed with the transports of the old connection.
	reconnected() {
		this.consume();
	},

	consume() {
		const generation = ++this.generation;
		this.consumer = clientPromise
			.then((client) => client.consume(this.el.dataset.producerId))
			.then((consumer) => {
				if (generation !== this.generation) {
					consumer.close();
					return null;
				}
				this.el.srcObject = new MediaStream([consumer.track]);
				// Exposed for the end-to-end tests.
				this.el.consumer = consumer;
				return consumer;
			});
		this.consumer.catch(logError);
	},

	destroyed() {
		this.generation++;
		Promise.all([clientPromise, this.consumer])
			.then(([client, consumer]) => consumer && client.closeConsumer(consumer))
			.catch(() => {});
	},
};

export const Hooks = { Room, Consumer };
