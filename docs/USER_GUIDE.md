# Post User Guide

A visual walkthrough and user manual for **Post**, a lightweight native macOS application for HTTP API testing, local webhook debugging, and Model Context Protocol (MCP) tool inspection.

---

## Table of Contents

1. [HTTP Workbench](#1-http-workbench)
2. [cURL Import & Export](#2-curl-import--export)
3. [Local Webhook Listener](#3-local-webhook-listener)
4. [MCP Tool Inspector](#4-mcp-tool-inspector)
5. [Tokenized Search & Activity History](#5-tokenized-search--activity-history)
6. [Keyboard Shortcuts & Tips](#6-keyboard-shortcuts--tips)

---

## 1. HTTP Workbench

The HTTP Workbench is your primary interface for constructing, editing, and executing HTTP API requests.

![HTTP Workbench](assets/http_workbench.png)

### Key Workflows:
* **Create Request**: Click **+ New Request** in the sidebar footer.
* **Configure Request Details**:
  * **Name**: Edit the request title directly in the header text input.
  * **Method**: Pick `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, or `OPTIONS` from the method dropdown.
  * **URL**: Enter your full HTTP or HTTPS endpoint URL. Pressing `Enter` while inside the URL field automatically triggers execution.
* **Request Sections**:
  * **Params**: Add key-value pairs for query parameters. Toggle individual rows on or off using the checkboxes.
  * **Headers**: Add custom request headers (e.g. `Authorization`, `Content-Type`).
  * **Body**: Select payload type (`None`, `JSON`, `Form Data`, or `Raw Text`) and enter formatted JSON or raw text.
* **Execute & Inspect Response**:
  * Click **Send** to fire the request.
  * Inspect status code badges (e.g., `200 OK` in green, `500` in red), execution latency in milliseconds, and total response payload size.
  * View pretty-printed JSON response bodies or raw headers in the response tab bar.

---

## 2. cURL Import & Export

Post seamlessly bridges GUI request building with terminal cURL workflows.

### Importing cURL:
1. Click **cURL** in the sidebar footer.
2. Paste any raw `curl` command line (e.g., `curl -X POST https://api.example.com -H 'Content-Type: application/json' -d '{"key":"val"}'`).
3. Click **Import**. Post will parse the method, URL, headers, and body into a structured request.

### Exporting cURL:
1. Open any request in the HTTP Workbench.
2. Click **Copy cURL** in the top right header.
3. The exact runnable `curl` command is copied to your macOS Clipboard.

---

## 3. Local Webhook Listener

Test and debug webhooks sent by local microservices, Home Assistant, Stripe, or third-party integrations.

![Webhook Listener](assets/webhook_listener.png)

### Getting Started:
1. Switch to the **Webhooks** tab in the sidebar.
2. Set your preferred local listening port (default: `9090`).
3. Click **Start Listener**.
4. Send incoming webhooks to `http://localhost:9090/webhook`.
5. Incoming payloads populate in real time with client IP, timestamp, raw HTTP headers, and formatted JSON body inspection.

---

## 4. MCP Tool Inspector

Directly connect to and inspect Model Context Protocol (MCP) servers.

![MCP Inspector](assets/mcp_inspector.png)

### Tool Testing Workflow:
1. Switch to the **MCP Server** tab in the sidebar.
2. Enter your local MCP endpoint (e.g. `http://localhost:8000/sse`) and click **Connect / Fetch Tools**.
3. Browse all discovered tools returned by `tools/list`.
4. Select a tool, fill in tool arguments in the JSON editor, and click **Execute Tool** to fire JSON-RPC `tools/call` requests.
5. Inspect the execution time and JSON output.

---

## 5. Tokenized Search & Activity History

Search across all your saved requests and execution history.

### Structured Filter Tokens:
You can filter by exact attributes in the search bar:
* `method:POST`: Show only POST requests or history items.
* `status:200`: Filter history items returning HTTP 200.
* `type:Webhook`: Show captured webhooks in activity history.

---

## 6. Keyboard Shortcuts & Tips

* **`Enter` inside URL field**: Fire HTTP Request.
* **`⌘ + C` / `⌘ + V`**: Supported inside all text fields without OS predictive popup interference.
* **Single-click Tab Switching**: Switch instantly between Requests, Webhooks, MCP Server, and History in the sidebar header.
