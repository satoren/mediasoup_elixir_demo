const { defineConfig, devices } = require("@playwright/test");

// End-to-end tests against a running server (`mix phx.server`).
module.exports = defineConfig({
	testDir: "./e2e",
	forbidOnly: !!process.env.CI,
	reporter: process.env.CI ? "list" : "html",
	use: {
		baseURL: process.env.BASE_URL || "http://localhost:4000",
		trace: "retain-on-failure",
	},
	projects: [
		{
			name: "chromium",
			use: {
				...devices["Desktop Chrome"],
				permissions: ["microphone", "camera"],
				launchOptions: {
					args: [
						"--use-fake-ui-for-media-stream",
						"--use-fake-device-for-media-stream",
						"--autoplay-policy=no-user-gesture-required",
					],
				},
			},
		},
	],
});
