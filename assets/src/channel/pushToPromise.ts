import { Push } from "phoenix";

export const pushToPromise = <T>(push: Push) => {
	return new Promise<T>((resolve, reject) => {
		push
			.receive("ok", resolve)
			.receive("error", reject)
			.receive("timeout", reject);
	});
};
