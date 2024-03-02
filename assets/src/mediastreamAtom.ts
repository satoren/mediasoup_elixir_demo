import { atom } from "jotai";
import { atomEffect } from "jotai-effect";
import { unwrap } from "jotai/utils";

type FetchStreamFunction<T> = (
	c: T | undefined,
) => Promise<MediaStream | undefined>;

export const createMediaStreamAtom = <T>(f: FetchStreamFunction<T>) => {
	const constraintsAtom = atom<T | undefined>(undefined);
	const mediaStreamAtom = atom<Promise<MediaStream | undefined>>(
		Promise.resolve(undefined),
	);

	const getMediaStreamAtom = atomEffect((get, set) => {
		const constraints = get(constraintsAtom);

		const stream = f(constraints);
		set(mediaStreamAtom, stream);

		return () => {
			stream.then((stream) => {
				if (stream) {
					stream.getTracks().forEach((track) => {
						track.stop();
					});
				}
			});
		};
	});

	const unwrapedMediaStreamAtom = unwrap(mediaStreamAtom);

	return atom(
		(get) => {
			get(getMediaStreamAtom);
			return {
				constraints: get(constraintsAtom),
				stream: get(unwrapedMediaStreamAtom),
			};
		},
		(_get, set, constraints: T | undefined) => {
			set(constraintsAtom, constraints);
		},
	);
};

export const micMediaStreamAtom = createMediaStreamAtom(
	(p: MediaStreamConstraints["audio"] | undefined) => {
		if (p) {
			return navigator.mediaDevices.getUserMedia({ audio: p });
		} else {
			return Promise.resolve(undefined);
		}
	},
);
export const cameraMediaStreamAtom = createMediaStreamAtom(
	(p: MediaStreamConstraints["video"] | undefined) => {
		if (p) {
			return navigator.mediaDevices.getUserMedia({ video: p });
		} else {
			return Promise.resolve(undefined);
		}
	},
);
