# Post

A native, lightweight macOS desktop application for HTTP API testing, local webhook debugging, and Model Context Protocol (MCP) tool inspection. Built with Swift 6, AppKit, and SwiftUI.

---

## Key Features

* **HTTP Workbench**: Build and execute HTTP requests (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`) with custom headers, query parameters, and JSON payloads.
* **cURL Support**: Import raw cURL strings (`curl -X POST ...`) directly into structured requests, or export any request back to a runnable cURL command.
* **Local Webhook Server**: Embedded network listener (`NWListener`) running on port `9090` (configurable) to capture, format, and inspect incoming webhook payloads in real time.
* **MCP Tool Inspector**: Connect to local HTTP/SSE Model Context Protocol servers, discover available tools (`tools/list`), and execute JSON-RPC 2.0 tool calls (`tools/call`).
* **Tokenized Search & History**: Search activity logs using tokenized queries like `method:POST status:200`.
* **Native macOS UX**: Suppresses phantom autofill and predictive text popups via layered AppKit field editor interceptors (`FilterField`).

---

## Architecture & Requirements

* **Platform**: macOS 15.0+
* **Toolchain**: Swift 6.0+
* **Dependencies**: Native macOS frameworks (`AppKit`, `SwiftUI`, `Network`, `Foundation`)

```
Sources/Post/
├── App/
│   ├── PostApp.swift
│   └── PostAppDelegate.swift
├── Engine/
│   ├── HTTPClient.swift
│   ├── CURLParser.swift
│   ├── WebhookServer.swift
│   └── MCPClient.swift
├── Models/
│   ├── HTTPRequest.swift
│   ├── HTTPResponse.swift
│   ├── WebhookPayload.swift
│   ├── MCPServer.swift
│   └── HistoryItem.swift
├── Storage/
│   └── PostStore.swift
└── Views/
    ├── MainContentView.swift
    ├── SidebarView.swift
    ├── RequestBuilderView.swift
    ├── ResponseView.swift
    ├── WebhookServerView.swift
    ├── MCPInspectorView.swift
    └── Components/
        ├── FilterField.swift
        ├── NoAutoFillWindowSetup.swift
        └── StatusBadge.swift
```

---

## Getting Started

### Build

```bash
make build
```

### Run Unit Tests

```bash
make test
```

### Bundle & Deploy Locally

To compile the release bundle and install to `/Applications/Post.app`:

```bash
make deploy
```

---

## Usage Guide

### 1. HTTP Workbench
- Click **+ New Request** in the sidebar.
- Select your HTTP method and enter the target URL.
- Configure query params, custom headers, or body JSON in the section tabs.
- Click **Send** (or press Enter in the URL field) to execute.

### 2. Webhook Listener
- Switch to the **Webhooks** tab in the sidebar.
- Click **Start Listener** (default port `9090`).
- Send HTTP POST requests to `http://localhost:9090/webhook` from your local services to inspect incoming headers and payloads.

### 3. MCP Inspector
- Switch to the **MCP Server** tab.
- Enter your local MCP endpoint (e.g. `http://localhost:8000/sse`) and click **Connect / Fetch Tools**.
- Select any discovered tool, edit the arguments JSON, and execute tool calls directly.

---

## License

Distributed under the [MIT License](LICENSE).
