import { useEffect, useState } from "react";
import { useSocket } from "./channel/useSocket";
import { cameraMediaStreamAtom, micMediaStreamAtom } from "./mediastreamAtom";
import { atom, useAtomValue } from "jotai";
import { RoomChannel, createRoomChannel } from "./channel/RoomChannel";
import { RoomUsers } from "./RoomUsers";
import { ThemeProvider } from "@/components/theme-provider";
import { Footer } from "./Footer";
import { atomWithLocation } from "jotai-location";

const locationAtom = atomWithLocation();
const roomIdAtom = atom(
	(get) => get(locationAtom).searchParams?.get("roomId") || "lobby",
);

function Producer({ roomChannel }: { roomChannel: RoomChannel }) {
	const mic = useAtomValue(micMediaStreamAtom).stream;
	const camera = useAtomValue(cameraMediaStreamAtom).stream;

	useEffect(() => {
		if (!mic) {
			return;
		}
		const producer = roomChannel.produce({
			stopTracks: false,
			track: mic.getAudioTracks()[0],
		});

		return () => {
			producer.then((p) => {
				roomChannel.closeProducer(p);
			});
		};
	}, [mic, roomChannel]);
	useEffect(() => {
		if (!camera) {
			return;
		}
		const producer = roomChannel.produce({
			stopTracks: false,
			track: camera.getVideoTracks()[0],
		});

		return () => {
			producer.then((p) => {
				roomChannel.closeProducer(p);
			});
		};
	}, [camera, roomChannel]);

	return null;
}

function App() {
	const socket = useSocket();

	const [room, setRoom] = useState<RoomChannel | undefined>(undefined);
	const roomId = useAtomValue(roomIdAtom);

	useEffect(() => {
		if (!socket) {
			return;
		}

		const room = createRoomChannel(socket, roomId);
		setRoom(room);
		return () => {
			room.leave();
		};
	}, [roomId, socket]);

	return (
		<ThemeProvider defaultTheme="dark" storageKey="ui-theme">
			{room && <Producer roomChannel={room} />}
			{room && <RoomUsers roomChannel={room} />}
			<Footer />
		</ThemeProvider>
	);
}

export default App;
