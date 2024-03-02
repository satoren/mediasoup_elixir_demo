import { cameraMediaStreamAtom, micMediaStreamAtom } from "./mediastreamAtom";
import { useAtom } from "jotai";

import { Button } from "@/components/ui/button";
import {
	VideoCameraSlashIcon,
	VideoCameraIcon,
	MicrophoneIcon,
} from "@heroicons/react/24/solid";

const DeviceControl = () => {
	const [mic, setMic] = useAtom(micMediaStreamAtom);
	const [camera, setCamera] = useAtom(cameraMediaStreamAtom);

	return (
		<div>
			<Button
				onClick={() => {
					if (mic.constraints) {
						setMic(false);
					} else {
						setMic(true);
					}
				}}
			>
				{mic.constraints ? (
					<MicrophoneIcon className="h-6 w-6 text-blue-500" />
				) : (
					<MicrophoneIcon className="h-6 w-6 text-red-500" />
				)}
			</Button>
			<Button
				onClick={() => {
					if (camera.constraints) {
						setCamera(false);
					} else {
						setCamera(true);
					}
				}}
			>
				{camera.constraints ? (
					<VideoCameraIcon className="h-6 w-6 text-blue-500" />
				) : (
					<VideoCameraSlashIcon className="h-6 w-6 text-red-500" />
				)}
			</Button>
		</div>
	);
};

export function Footer() {
	return (
		<footer className="fixed bottom-0 left-0 z-20 w-full p-4 bg-white border-t border-gray-200 shadow md:flex md:items-center md:justify-between md:p-6 dark:bg-gray-800 dark:border-gray-600">
			<DeviceControl />
		</footer>
	);
}
