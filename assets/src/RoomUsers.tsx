import { useEffect, useMemo, useRef, useState } from "react";
import { RoomChannel, UserInfo } from "./channel/RoomChannel";
import { atomWithObservable } from "jotai/utils";
import { useAtomValue } from "jotai";

import { Card, CardContent } from "@/components/ui/card";
import {
	Carousel,
	CarouselContent,
	CarouselItem,
	CarouselNext,
	CarouselPrevious,
} from "@/components/ui/carousel";

export function RoomUsers({ roomChannel }: { roomChannel: RoomChannel }) {
	const [users, setUsers] = useState<UserInfo[]>([]);
	const [selectedUserId, setSelectedUserId] = useState<string>();
	useEffect(() => {
		const sub = roomChannel.users.subscribe((user) => {
			setUsers(user);
		});

		return () => sub.unsubscribe();
	}, [roomChannel]);

	const userInfoAtom = useMemo(
		() => atomWithObservable(() => roomChannel.userInfo),
		[roomChannel],
	);
	const userInfo = useAtomValue(userInfoAtom);

	const pickedUser = users.find((user) => user.id === selectedUserId);
	const otherUsers = users.filter(
		(user) => user.id !== userInfo?.id && user.id !== pickedUser?.id,
	);

	const carouselUsers =
		otherUsers.length > 0 ? (
			<div className="w-full h-full flex justify-center flex-row ">
				<Carousel
					opts={{
						align: "start",
					}}
					className="w-10/12"
				>
					<CarouselContent>
						{otherUsers.map((user) => (
							<CarouselItem
								key={user.id}
								className="max-h-60 max-w-60"
								onClick={() => setSelectedUserId(user.id)}
							>
								<RoomUser roomChannel={roomChannel} user={user} />
							</CarouselItem>
						))}
					</CarouselContent>
					<CarouselPrevious />
					<CarouselNext />
				</Carousel>
			</div>
		) : null;

	return (
		<div className="w-full h-full flex justify-center flex-col ">
			{carouselUsers}
			{pickedUser && <RoomUser roomChannel={roomChannel} user={pickedUser} />}
		</div>
	);
}
function RoomUser({
	roomChannel,
	user,
}: {
	roomChannel: RoomChannel;
	user: UserInfo;
}) {
	const producers = user.metas.flatMap((meta) => {
		if (meta.kind === "producer") {
			return [meta.producer];
		} else {
			return [];
		}
	});

	const audioConsume = useMemo(
		() => producers.filter((meta) => meta.kind === "audio"),
		[producers],
	);
	const videoConsume = useMemo(
		() => producers.filter((meta) => meta.kind === "video"),
		[producers],
	);

	return (
		<Card className="w-full h-full">
			<CardContent className="flex items-center justify-center p-6">
				{audioConsume.map((meta) => (
					<AudioConsume
						key={meta.id}
						producerId={meta.id}
						roomChannel={roomChannel}
					/>
				))}
				{videoConsume.map((meta) => (
					<VideoConsume
						key={meta.id}
						producerId={meta.id}
						roomChannel={roomChannel}
					/>
				))}
			</CardContent>
		</Card>
	);
}
const VideoConsume = ({
	producerId,
	roomChannel,
}: {
	producerId: string;
	roomChannel: RoomChannel;
}) => {
	const videoRef = useRef<HTMLVideoElement>(null);
	useEffect(() => {
		const consumerPromise = roomChannel.consume({ id: producerId });

		consumerPromise.then((consumer) => {
			const stream = new MediaStream();
			stream.addTrack(consumer.track);
			if (videoRef.current) {
				videoRef.current.srcObject = stream;
			}
		});

		return () => {
			consumerPromise?.then((c) => roomChannel.closeConsumer(c));
		};
	}, [producerId, roomChannel]);

	return <video ref={videoRef} autoPlay playsInline muted />;
};
const AudioConsume = ({
	producerId,
	roomChannel,
}: {
	producerId: string;
	roomChannel: RoomChannel;
}) => {
	const audioRef = useRef<HTMLAudioElement>(null);
	useEffect(() => {
		const consumer = roomChannel.consume({ id: producerId });

		consumer.then((c) => {
			const stream = new MediaStream();
			stream.addTrack(c.track);
			if (audioRef.current) {
				audioRef.current.srcObject = stream;
			}
		});
		return () => {
			consumer?.then((c) => roomChannel.closeConsumer(c));
		};
	}, [producerId, roomChannel]);

	return <audio ref={audioRef} autoPlay playsInline />;
};
