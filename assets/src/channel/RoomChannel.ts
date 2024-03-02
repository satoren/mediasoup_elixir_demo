import {
	Producer,
	Consumer,
	ProducerOptions,
	TransportOptions,
	ConsumerOptions,
} from "mediasoup-client/lib/types";
import { Device } from "mediasoup-client";
import { Channel, Presence, Socket } from "phoenix";
import { BehaviorSubject } from "rxjs";
import { pushToPromise } from "./pushToPromise";

type UserMeta =
	| {
			kind: "user";
			online_at: string;
	  }
	| {
			kind: "producer";
			producer: {
				id: string;
				kind: string;
				start_at: string;
			};
	  };

type SelfUserInfo = { id: string };
export type UserInfo = { id: string; metas: UserMeta[] };
export interface RoomChannel {
	produce: (option: ProducerOptions) => Promise<Producer>;
	closeProducer: (producer: Producer) => Promise<void>;

	consume: (p: { id: string }) => Promise<Consumer>;
	closeConsumer: (c: Consumer) => Promise<void>;

	leave: () => void;

	users: BehaviorSubject<UserInfo[]>;
	userInfo: BehaviorSubject<SelfUserInfo | undefined>;
}

const loadDevice = async (channel: Channel) => {
	try {
		const device = new Device();
		device.load({
			routerRtpCapabilities: await pushToPromise(
				channel.push("getRouterRtpCapabilities", {}),
			),
		});
		return device;
	} catch (e) {
		console.error(e);
		throw e;
	}
};

async function createProducerTransport(
	devicePromise: Promise<Device>,
	channel: Channel,
) {
	const device = await devicePromise;

	const param = await pushToPromise<TransportOptions>(
		channel.push("createWebRtcTransport", {}),
	);
	const transport = device.createSendTransport(param);

	transport.on("connect", async (params, callback, errback) => {
		const { dtlsParameters } = params;
		try {
			await pushToPromise<TransportOptions>(
				channel.push("connectWebRtcTransport", {
					transportId: transport.id,
					dtlsParameters,
				}),
			);
			callback();
		} catch (e) {
			if (e instanceof Error) {
				errback(e);
			} else {
				errback(new Error(`${e}`));
			}
		}
	});

	transport.on("produce", async (param, callback, errback) => {
		try {
			const { kind, rtpParameters } = param;

			const { id } = await pushToPromise<{ id: string }>(
				channel.push("produce", {
					transportId: transport.id,
					kind,
					rtpParameters,
				}),
			);
			callback({ id });
		} catch (e) {
			if (e instanceof Error) {
				errback(e);
			} else {
				errback(new Error(`${e}`));
			}
		}
	});

	return transport;
}

async function createConsumerTransport(
	devicePromise: Promise<Device>,
	channel: Channel,
) {
	const device = await devicePromise;

	const param = await pushToPromise<TransportOptions>(
		channel.push("createWebRtcTransport", {}),
	);

	const transport = device.createRecvTransport(param);

	transport.on("connect", async (params, callback, errback) => {
		const { dtlsParameters } = params;
		try {
			await pushToPromise<TransportOptions>(
				channel.push("connectWebRtcTransport", {
					transportId: transport.id,
					dtlsParameters,
				}),
			);

			callback();
		} catch (e) {
			if (e instanceof Error) {
				errback(e);
			} else {
				errback(new Error(`${e}`));
			}
		}
	});

	return transport;
}

export const createRoomChannel = (
	socket: Socket,
	roomId: string,
): RoomChannel => {
	const channel = socket.channel(`room:${roomId}`, {});

	const presence = new Presence(channel);

	const users = new BehaviorSubject<{ id: string; metas: UserMeta[] }[]>([]);
	presence.onSync(() => {
		const list = presence.list(
			(
				id,
				{
					metas,
				}: {
					metas: UserMeta[];
				},
			) => {
				return { id, metas };
			},
		);

		users.next(list);
	});
	channel.onClose(() => {
		users.next([]);
	});
	channel.onError(() => {
		users.next([]);
	});
	channel.join();

	const userInfo = new BehaviorSubject<SelfUserInfo | undefined>(undefined);
	channel.on("user_info", (msg) => {
		userInfo.next(msg);
	});
	const devicePromise = loadDevice(channel);
	let producerTransport = createProducerTransport(devicePromise, channel);
	let consumerTransport = createConsumerTransport(devicePromise, channel);

	channel.onClose(() => {
		producerTransport = createProducerTransport(devicePromise, channel);
		consumerTransport = createConsumerTransport(devicePromise, channel);
	});
	channel.onError(() => {
		producerTransport = createProducerTransport(devicePromise, channel);
		consumerTransport = createConsumerTransport(devicePromise, channel);
	});

	const produce = async (option: ProducerOptions) => {
		const transport = await producerTransport;
		return transport.produce(option);
	};

	const closeProducer = async (producer: Producer) => {
		await channel.push("closeProducer", { producerId: producer.id });
		producer.close();
	};

	const consume = async (p: { id: string }) => {
		const transport = await consumerTransport;
		const device = await devicePromise;

		const param = await pushToPromise<ConsumerOptions>(
			channel.push("consume", {
				transportId: transport.id,
				producerId: p.id,
				rtpCapabilities: device.rtpCapabilities,
				paused: true,
			}),
		);

		const consumer = await transport.consume(param);
		await pushToPromise<void>(
			channel.push("resumeConsumer", {
				consumerId: consumer.id,
			}),
		);
		return consumer;
	};

	const closeConsumer = async (consumer: Consumer) => {
		await channel.push("closeConsumer", { consumerId: consumer.id });
		consumer.close();
	};

	const leave = () => {
		channel.leave();
	};

	return {
		produce,
		closeProducer,
		consume,
		closeConsumer,
		leave,
		users,
		userInfo,
	};
};
