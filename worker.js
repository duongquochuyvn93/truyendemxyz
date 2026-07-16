const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/views/export") {
      if (request.method !== "POST") return methodNotAllowed();
      if (!isAuthorized(request, env)) return unauthorized();
      return viewStore(env, "/export");
    }

    if (url.pathname === "/api/views/ack") {
      if (request.method !== "POST") return methodNotAllowed();
      if (!isAuthorized(request, env)) return unauthorized();
      return viewStore(env, "/ack", request);
    }

    const match = url.pathname.match(/^\/api\/views\/(\d+)$/);
    if (match) {
      if (request.method !== "POST") return methodNotAllowed();
      return viewStore(env, `/increment/${match[1]}`);
    }

    const response = await env.ASSETS.fetch(request);
    return withSecurityHeaders(response);
  },
};

// A single Durable Object serializes increments and owns the current sync batch.
// This avoids Cloudflare KV read-modify-write races and makes view exports safe.
export class ViewStore {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname.startsWith("/increment/")) {
      const id = url.pathname.slice("/increment/".length);
      if (!/^\d+$/.test(id)) return jsonResponse({ error: "Invalid story id" }, 400);

      await this.state.storage.transaction(async (storage) => {
        const key = `view:${id}`;
        const current = Number((await storage.get(key)) || 0);
        await storage.put(key, current + 1);
      });
      return jsonResponse({ ok: true });
    }

    if (url.pathname === "/export") {
      const batch = await this.state.storage.transaction(async (storage) => {
        const pending = await storage.get("pending-batch");
        if (pending) return pending;

        const values = {};
        const entries = await storage.list({ prefix: "view:" });
        for (const [key, value] of entries) {
          const count = Number(value);
          if (Number.isSafeInteger(count) && count > 0) {
            values[key.slice("view:".length)] = count;
          }
          await storage.delete(key);
        }

        if (Object.keys(values).length === 0) return { id: null, values };
        const created = { id: crypto.randomUUID(), values };
        await storage.put("pending-batch", created);
        return created;
      });
      return jsonResponse(batch);
    }

    if (url.pathname === "/ack") {
      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400);
      }

      if (typeof body?.batchId !== "string" || !body.batchId) {
        return jsonResponse({ error: "Missing batchId" }, 400);
      }

      const acknowledged = await this.state.storage.transaction(async (storage) => {
        const pending = await storage.get("pending-batch");
        if (!pending || pending.id !== body.batchId) return false;
        await storage.delete("pending-batch");
        return true;
      });

      return jsonResponse({ acknowledged });
    }

    return jsonResponse({ error: "Not found" }, 404);
  }
}

function viewStore(env, path, originalRequest) {
  const id = env.VIEW_STORE.idFromName("global");
  const init = { method: "POST" };
  if (originalRequest) {
    init.headers = { "content-type": "application/json" };
    init.body = originalRequest.body;
  }
  return env.VIEW_STORE.get(id).fetch(new Request(`https://view-store.internal${path}`, init));
}

function isAuthorized(request, env) {
  const expected = env.SYNC_SECRET;
  const provided = request.headers.get("authorization");
  return Boolean(expected && provided === `Bearer ${expected}`);
}

function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), { status, headers: JSON_HEADERS });
}

function unauthorized() {
  return new Response("Unauthorized", { status: 401, headers: { "cache-control": "no-store" } });
}

function methodNotAllowed() {
  return new Response("Method Not Allowed", { status: 405, headers: { allow: "POST" } });
}

function withSecurityHeaders(response) {
  const headers = new Headers(response.headers);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("Permissions-Policy", "camera=(), geolocation=(), microphone=()");
  headers.set("X-Frame-Options", "SAMEORIGIN");
  headers.set("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}
