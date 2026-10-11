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

// Disconnects the LiveView socket and connects it again.
const dropConnection = async (page) => {
	await page.evaluate(async () => {
		await new Promise((resolve) => window.liveSocket.disconnect(resolve));
		window.liveSocket.connect();
	});
	await expect(page.locator("[data-phx-main].phx-connected")).toBeAttached();
};

const consumerId = (locator) => locator.evaluate((el) => el.consumer?.id);

test("calls recover from a reconnect without reloading the page", async ({
	browser,
}) => {
	const room = `e2e-reconnect-${Date.now()}`;
	const alice = await join(browser, room);
	const bob = await join(browser, room);

	await alice.click("#toggle-audio");
	await alice.click("#toggle-video");

	const audio = bob.locator("audio[data-producer-id]");
	const video = bob.locator("video[data-producer-id]");
	await expect
		.poll(() => bytesReceived(audio), { timeout: 15_000 })
		.toBeGreaterThan(0);

	// A page reload would drop this marker.
	await alice.evaluate(() => {
		window.notReloaded = true;
	});
	await bob.evaluate(() => {
		window.notReloaded = true;
	});

	// Alice reconnects: she produces again, Bob consumes her new producers.
	const oldProducerId = await audio.getAttribute("data-producer-id");
	await dropConnection(alice);
	await expect(
		alice.locator('#toggle-audio[aria-pressed="true"]'),
	).toBeVisible();
	await expect(
		alice.locator('#toggle-video[aria-pressed="true"]'),
	).toBeVisible();
	await expect(
		bob.locator(`audio[data-producer-id="${oldProducerId}"]`),
	).toHaveCount(0);
	await expect(audio).toHaveCount(1);
	await expect(video).toHaveCount(1);
	await expect
		.poll(() => bytesReceived(audio), { timeout: 15_000 })
		.toBeGreaterThan(0);
	await expect
		.poll(() => bytesReceived(video), { timeout: 15_000 })
		.toBeGreaterThan(0);

	// Bob reconnects: he consumes Alice's producers again.
	const oldConsumerId = await consumerId(audio);
	await dropConnection(bob);
	await expect
		.poll(() => consumerId(audio), { timeout: 15_000 })
		.not.toBe(oldConsumerId);
	await expect
		.poll(() => bytesReceived(audio), { timeout: 15_000 })
		.toBeGreaterThan(0);
	await expect
		.poll(() => bytesReceived(video), { timeout: 15_000 })
		.toBeGreaterThan(0);

	expect(await alice.evaluate(() => window.notReloaded)).toBe(true);
	expect(await bob.evaluate(() => window.notReloaded)).toBe(true);
});
