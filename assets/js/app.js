import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { Hooks, connectParams } from "./hooks";

const csrfToken = document
	.querySelector("meta[name='csrf-token']")
	.getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
	longPollFallbackMs: 2500,
	params: () => ({ _csrf_token: csrfToken, ...connectParams() }),
	hooks: Hooks,
});

liveSocket.connect();

// Expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket;
