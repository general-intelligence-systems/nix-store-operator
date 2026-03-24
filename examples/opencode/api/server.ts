import { createOpencodeClient } from "@opencode-ai/sdk"

const OPENCODE_URL = process.env.OPENCODE_URL || "http://localhost:4096"
const PORT = parseInt(process.env.PORT || "3000")

const client = createOpencodeClient({ baseUrl: OPENCODE_URL })

// Preset prompts that can be triggered via the API
const presets: Record<string, { prompt: string; description: string }> = {
  hello: {
    description: "Basic greeting",
    prompt: "Say hello and introduce yourself briefly.",
  },
  analyze: {
    description: "Analyze the current project",
    prompt: "List the files in the current directory and give a brief summary of the project structure.",
  },
  version: {
    description: "Report versions",
    prompt: "What version of opencode are you running? Report any system info you can determine.",
  },
}

const server = Bun.serve({
  port: PORT,
  hostname: "0.0.0.0",

  async fetch(req) {
    const url = new URL(req.url)

    // GET /health
    if (url.pathname === "/health") {
      try {
        const health = await client.global.health()
        return Response.json({ status: "ok", opencode: health.data })
      } catch (e) {
        return Response.json({ status: "error", error: String(e) }, { status: 503 })
      }
    }

    // GET /presets - list available preset prompts
    if (url.pathname === "/presets") {
      return Response.json(
        Object.fromEntries(
          Object.entries(presets).map(([k, v]) => [k, v.description])
        )
      )
    }

    // POST /prompt/:preset - run a preset prompt
    if (req.method === "POST" && url.pathname.startsWith("/prompt/")) {
      const preset = url.pathname.split("/")[2]
      const p = presets[preset]
      if (!p) {
        return Response.json(
          { error: `unknown preset: ${preset}`, available: Object.keys(presets) },
          { status: 404 }
        )
      }

      try {
        // Create a fresh session
        const session = await client.session.create({
          body: { title: `preset-${preset}` },
        })

        // Send the preset prompt
        const result = await client.session.prompt({
          path: { id: session.data!.id },
          body: {
            parts: [{ type: "text", text: p.prompt }],
          },
        })

        return Response.json({
          preset,
          session_id: session.data!.id,
          response: result.data,
        })
      } catch (e) {
        return Response.json({ error: String(e) }, { status: 500 })
      }
    }

    // POST /prompt - send a custom prompt
    if (req.method === "POST" && url.pathname === "/prompt") {
      try {
        const body = await req.json() as { text?: string; model?: { providerID: string; modelID: string } }
        if (!body.text) {
          return Response.json({ error: "missing 'text' in body" }, { status: 400 })
        }

        const session = await client.session.create({
          body: { title: "custom-prompt" },
        })

        const promptBody: any = {
          parts: [{ type: "text", text: body.text }],
        }
        if (body.model) {
          promptBody.model = body.model
        }

        const result = await client.session.prompt({
          path: { id: session.data!.id },
          body: promptBody,
        })

        return Response.json({
          session_id: session.data!.id,
          response: result.data,
        })
      } catch (e) {
        return Response.json({ error: String(e) }, { status: 500 })
      }
    }

    return Response.json({
      endpoints: {
        "GET /health": "Check server health",
        "GET /presets": "List preset prompts",
        "POST /prompt/:preset": "Run a preset prompt",
        "POST /prompt": "Send a custom prompt { text, model? }",
      },
    })
  },
})

console.log(`opencode-api listening on http://0.0.0.0:${PORT}`)
console.log(`opencode server: ${OPENCODE_URL}`)
