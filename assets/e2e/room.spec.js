const { test, expect } = require("@playwright/test");

// Bytes received by the consumer attached to a remote <audio>/<video> element.
const bytesReceived = (locator) =>
	locator.evaluate(async (el) => {
		if (!el.consumer) {
			return 0;
		}
		let bytes = 0;
		for (const stat of (await el.consumer.getStats()).values()) {
			if (stat.type === "inbound-rtp") {
				bytes += stat.bytesReceived;
			}
		}
		return bytes;
	});

const join = async (browser, room) => {
	const page = await (await browser.newContext()).newPage();
	page.on("console", (msg) => {
		if (msg.type() === "error") {
			console.log(`[browser] ${msg.text()}`);
		}
	});
	await page.goto(`/?roomId=${room}`);
	await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached();
	return page;
};

test("microphone and camera are delivered to other users", async ({
	browser,
}) => {
	const room = `e2e-${Date.now()}`;
	const alice = await join(browser, room);
	const bob = await join(browser, room);

	await expect(alice.locator("#users > div")).toHaveCount(1);
	await expect(bob.locator("#users > div")).toHaveCount(1);

	await alice.click("#toggle-audio");
	await alice.click("#toggle-video");

	const audio = bob.locator("audio[data-producer-id]");
	const video = bob.locator("video[data-producer-id]");
	await expect(audio).toHaveCount(1);
	await expect(video).toHaveCount(1);

	await expect
		.poll(() => bytesReceived(audio), { timeout: 15_000 })
		.toBeGreaterThan(0);
	await expect
		.poll(() => bytesReceived(video), { timeout: 15_000 })
		.toBeGreaterThan(0);

	await alice.click("#toggle-audio");
	await expect(audio).toHaveCount(0);
	await expect(video).toHaveCount(1);
});
