# Post Practical Cookbook & Engineering Recipes

A collection of step-by-step, visual recipes for testing APIs, managing Keychain and 1Password secrets, chaining authentication tokens, chaos-testing webhooks, and auditing Model Context Protocol (MCP) servers using **Post** on macOS.

---

## Table of Recipes

1. [Recipe 1: Multi-Environment Setup with macOS Keychain & 1Password (`op://`) Secrets](#recipe-1-multi-environment-setup-with-macos-keychain--1password-op-secrets)
2. [Recipe 2: Zero-Copy Auth Chaining (`POST /auth/login` → `{{jwt_token}}`)](#recipe-2-zero-copy-auth-chaining-post-authlogin--jwt_token)
3. [Recipe 3: Local Microservice & Webhook Chaos Testing (Mock Rules, Latency & Live Replay)](#recipe-3-local-microservice--webhook-chaos-testing-mock-rules-latency--live-replay)
4. [Recipe 4: Auditing & Testing `stdio` and HTTP Model Context Protocol (MCP) Servers](#recipe-4-auditing--testing-stdio-and-http-model-context-protocol-mcp-servers)
5. [Recipe 5: Slicing Large Payloads with JSONPath & Auditing Regressions with Response Diff](#recipe-5-slicing-large-payloads-with-jsonpath--auditing-regressions-with-response-diff)
6. [Recipe 6: Generating Production-Ready Go, Swift, and Python Clients](#recipe-6-generating-production-ready-go-swift-and-python-clients)
7. [Recipe 7: Keyboard-First Power Workflows (Stash-Model Token Filtering & Hotkeys)](#recipe-7-keyboard-first-power-workflows-stash-model-token-filtering--hotkeys)

---

## Recipe 1: Multi-Environment Setup with macOS Keychain & 1Password (`op://`) Secrets

### Scenario
You are developing against a local backend on `http://localhost:8080`, managing a Home Assistant / HomeLab stack on `http://homeassistant.local:8123`, and querying production APIs. You want to switch environments in one click while keeping tokens encrypted in **macOS Keychain** or referenced directly from **1Password** via `op://` URIs.

![Environments, Keychain & 1Password Manager](assets/environments_keychain_1p.png)

### Step-by-Step Instructions

#### 1. Open the Environments & Secrets Manager (`⌘E`)
Press `⌘E` (or click the gear icon in the top-right of the HTTP Workbench).

#### 2. Configure Isolated Environment Profiles (Callout ①)
1. Select or create profiles in the left sidebar (`Local Dev`, `Production`, `HomeLab & Home Assistant`, `HTTPBin Sandbox`).
2. Add plain-text variables for non-sensitive configuration such as:
   * `ha_url`: `http://homeassistant.local:8123`
   * `router_url`: `http://192.168.1.1:8000`
   * `entity_id`: `light.office_desk`

#### 3. Store Secrets in macOS Keychain (`🔒`, Callout ②)
1. Add a variable named `ha_token`.
2. Click the **Lock (`🔒`)** button on the right side of the row so it turns yellow.
3. Paste your token value. Post encrypts and persists the secret inside the native macOS Keychain (`kSecClassGenericPassword`, service `com.msjurset.post-mac.env`) and strips the plaintext value from `workspace.json`.

#### 4. Reference Secrets Directly from 1Password (`op://`, Callout ③ & ④)
If you already keep API keys in 1Password, you don't need to copy the raw secret into Post at all:
1. In 1Password, open the item, click the dropdown next to the field, and choose **Copy Secret Reference** (e.g., `op://HomeLab/Cloudflare/api_token`).
2. Paste the `op://...` URI directly into the variable's value field in Post (or use it inline in any header/URL as `{{op://HomeLab/Cloudflare/api_token}}`).
3. Post displays a blue **`1P op://`** badge (**Callout ③**).
4. When you execute a request, Post invokes `/opt/homebrew/bin/op read --no-newline`, authenticates via macOS Touch ID, and caches the resolved secret in memory for the current session.
5. To evict cached 1Password secrets at any time, click **Clear 1P Cache** (**Callout ④**).

---

## Recipe 2: Zero-Copy Auth Chaining (`POST /auth/login` → `{{jwt_token}}`)

### Scenario
Your API requires posting credentials to `/auth/login` to obtain a short-lived JWT `access_token` and `user.id`. Instead of manually copying tokens from the response body and pasting them into other requests, you can chain them automatically.

### Part A: Extract the Token from the Login Response

![Zero-Copy Auth Chaining](assets/auth_chaining.png)

1. Select `1. Auth Login (Extract JWT & User ID)` in the sidebar.
2. Switch to the **Chaining** tab (**Callout ①**).
3. Add two extraction rules (**Callout ② & ③**):
   * **Rule 1**: JSONPath `$.json.access_token` → Target Variable `jwt_token`
   * **Rule 2**: JSONPath `$.json.user.id` → Target Variable `user_id`
4. Press `⌘Return` to execute the login request. As soon as the `200 OK` response arrives, Post evaluates both JSONPath expressions and updates `{{jwt_token}}` and `{{user_id}}` in the active environment.

### Part B: Inject the Chained Token via Auth Presets

![Dedicated Auth Presets](assets/auth_presets.png)

1. Select `2. Verify Chained Bearer Token` (`GET https://httpbin.org/bearer`).
2. Open the **Auth** tab (**Callout ①**).
3. Choose **Bearer Token** from the Auth Type menu and set the token field to `{{jwt_token}}` (**Callout ②**).
4. Press `⌘Return`. Post interpolates the freshly extracted JWT into `Authorization: Bearer <token>` and `httpbin.org/bearer` confirms `"authenticated": true` (**Callout ③**).

---

## Recipe 3: Local Microservice & Webhook Chaos Testing (Mock Rules, Latency & Live Replay)

### Scenario
You are building a local webhook consumer on `http://localhost:8080/webhook` and need to capture sample Stripe/GitHub/Alertmanager payloads, replay them on demand, and test how your caller handles `429 Too Many Requests` rate limits and `503` slow-network outages.

### Part A: Capture & Replay Webhooks (`Captured Payloads`)

![Local Webhook Listener](assets/webhook_listener.png)

1. Switch to the **Webhooks** tab in the sidebar.
2. Verify the embedded `NWListener` is running on port `9090` (**Callout ①**).
3. Fire any webhook request at `http://localhost:9090/webhook/stripe` or select one of the pre-loaded requests in the **Webhook Sandbox (:9090)** collection.
4. Select a captured event in the stream (**Callout ②**) to inspect its client IP, status badge (`429`, `202`, `200`), headers, and JSON body.
5. In the **Webhook Actions** bar (**Callout ③**):
   * Enter your local service URL (`http://localhost:8080/webhook`) and click **Replay Now** to re-send the exact payload.
   * Or click **Open in Workbench** to turn the captured webhook into a saved HTTP request for further editing.

### Part B: Simulate Rate Limits, Latency & Auto-Forwarding (`Mock & Forwarding Rules`)

![Webhook Mock & Forwarding Rules](assets/webhook_mock_rules.png)

1. Switch the mode bar to **Mock & Forwarding Rules** (**Callout ①**).
2. Select or create a rule in the left list (**Callout ②**), such as:
   * `GitHub Push Queued (202)` on `/webhook/github` → returns `202 Accepted` with `40 ms` latency.
   * `Simulated Rate Limit (429)` on `/webhook/rate-limit` → returns `429 Too Many Requests` with `350 ms` latency.
   * `Chaos / Slow Upstream (503)` on `/webhook/chaos` → returns `503 Service Unavailable` with `1200 ms` latency.
3. Configure **Artificial Delay (`ms`)** and **Auto-Forward Target URL** (**Callout ③**) to test client retry logic and mirror incoming traffic to your local backend.

---

## Recipe 4: Auditing & Testing `stdio` and HTTP Model Context Protocol (MCP) Servers

### Scenario
You are building or configuring Model Context Protocol (MCP) servers for AI agents (over HTTP/SSE or local `stdio` CLI commands) and want to inspect their schemas, test tool calls interactively, and read server resources.

![MCP Inspector](assets/mcp_inspector.png)

### Step-by-Step Instructions

1. Switch to the **MCP Server** tab in the sidebar.
2. In the top bar (**Callout ①**):
   * Choose **HTTP / SSE** (e.g., `http://localhost:8000/sse`) or **Stdio Command** (e.g., `npx -y @modelcontextprotocol/server-filesystem /Users/msjurseth/workspace`).
   * Or click **Import Local Configs** to auto-import all MCP servers configured in `~/.gemini/antigravity-cli/mcp/`, `~/.cursor/mcp.json`, and Claude Desktop.
3. Browse **Tools**, **Resources**, and **Prompts** in the left pane (**Callout ②**).
4. Select a tool (e.g., `get_system_health`) and use the **Auto-Generated Schema Form** (**Callout ③**) to fill in typed parameters (`interface`, `verbose`) or switch to **Raw JSON**.
5. Click the green **Play** button to send the JSON-RPC 2.0 `tools/call` request and inspect the formatted result and latency in the **Execution Result** pane (**Callout ④**).

---

## Recipe 5: Slicing Large Payloads with JSONPath & Auditing Regressions with Response Diff

### Scenario
You want to isolate nested objects inside a large JSON payload without scrolling through hundreds of lines, and then verify exactly which fields changed between two executions of the same endpoint.

### Part A: Live JSONPath Slicing

![HTTP Workbench - JSONPath Slicing](assets/http_workbench.png)

1. Execute any JSON request (such as `Get User Profile` or `List User Posts`).
2. In the **Response Body** tab, type a JSONPath expression into the filter bar (**Callout ④**), such as:
   * `$.company`
   * `$.address.geo`
   * `$[0].title`
3. Post immediately renders the sliced JSON result and provides a 1-click **Copy Result** button.

### Part B: Line-by-Line Response Diffing

![Response Diff Engine](assets/jsonpath_and_diff.png)

1. Select `Get User Profile` and switch the response pane to the **Diff** tab (**Callout ①**).
2. Pick a historical run from the **Baseline** dropdown (**Callout ②**) and note the `+4 -3` line change summary.
3. Review the **LCS Line-by-Line Highlighting** (**Callout ③**), which clearly flags the changed `"email"`, the newly added `"tier": "enterprise"` field, and the role elevation from `"member"` to `"platform_admin"`.

---

## Recipe 6: Generating Production-Ready Go, Swift, and Python Clients

### Scenario
Once a request works in the HTTP Workbench (including resolved `{{variables}}`, query parameters, custom headers, and Auth presets), you want clean, idiomatic client code ready to paste into your application.

### Step-by-Step Instructions

1. Select any request in the HTTP Workbench.
2. Click the chevron on the **Copy cURL** split button in the top-right toolbar (**Callout ②** in the HTTP Workbench screenshot).
3. Choose your target language:
   * **Copy cURL**: Multi-line shell command with `-X`, `-H`, and escaped `--data-raw`.
   * **Copy Go (`net/http`)**: Complete `http.NewRequestWithContext` snippet with headers, body buffer, and `defer resp.Body.Close()`.
   * **Copy Swift (`URLSession`)**: Modern `async throws` snippet using `URLSession.shared.data(for:)`.
   * **Copy Python (`httpx`)**: Clean `httpx.request(...)` snippet.

---

## Recipe 7: Keyboard-First Power Workflows (Stash-Model Token Filtering & Hotkeys)

### Scenario
You want to filter dozens of requests and historical runs by HTTP method, status code, protocol type, or hostname without lifting your hands from the keyboard.

### Step-by-Step Instructions

1. Press `⌘K` (or `⌘F`) to focus the search bar (**Callout ①** in the HTTP Workbench screenshot).
2. Press `Tab` to open the Stash-model token dropdown (`method:`, `status:`, `type:`, `host:`, `collection:`).
3. Use `Tab` / `Down Arrow` (or `Shift+Tab` / `Up Arrow`) to move the highlight without mutating your typed text.
4. Press `Enter` on a key like `method:` — Post inserts `method:` with no trailing space and immediately chains into the value dropdown (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`).
5. Press `Enter` on `POST` — Post inserts `method:POST ` with a trailing space and closes the dropdown so you can continue typing free-text search terms or press `Tab` for another filter token (e.g., `status:429` or `collection:Home`).
