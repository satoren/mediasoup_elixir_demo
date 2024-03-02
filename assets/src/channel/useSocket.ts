import { atom, useAtomValue } from "jotai";
import { Channel, Socket } from "phoenix";
import { useEffect, useState } from "react";

export const socketAtom = atom<Socket | null>(null);

socketAtom.onMount = (setSocket) => {
	const socket = new Socket("/socket");
	socket.connect();
	setSocket(socket);
	return () => {
		socket.disconnect();
	};
};

export const useSocket = () => useAtomValue(socketAtom);

export const useChannel = (roomId: string) => {
	const [channel, setChannel] = useState<Channel | null>(null);
	const socket = useSocket();

	useEffect(() => {
		if (!socket) {
			return;
		}
		const channel = socket.channel(`room:${roomId}`);
		setChannel(channel);
		return () => {
			channel.leave();
		};
	}, [roomId, socket]);

	return channel;
};
