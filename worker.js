export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/views/export") {
      return handleExport(request, env);
    }

    const match = url.pathname.match(/^\/api\/views\/(\d+)$/);
    if (match) {
      const id = match[1];
      if (request.method === "POST") return handleIncrement(id, env);
      if (request.method === "GET") return handleGet(id, env);
      return new Response("Method Not Allowed", { status: 405 });
    }

    return env.ASSETS.fetch(request);
  },
};

function keyFor(id) {
  return `truyen:${id}`;
}

function jsonResponse(obj) {
  return new Response(JSON.stringify(obj), {
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function handleIncrement(id, env) {
  const key = keyFor(id);
  const current = parseInt((await env.VIEWS.get(key)) || "0", 10);
  const next = current + 1;
  await env.VIEWS.put(key, String(next));
  return jsonResponse({ id: Number(id), total: next });
}

async function handleGet(id, env) {
  const key = keyFor(id);
  const current = parseInt((await env.VIEWS.get(key)) || "0", 10);
  return jsonResponse({ id: Number(id), total: current });
}

// "Rút cạn" bộ đếm: trả về số view mới tích luỹ từ lần sync trước rồi xoá key.
// WP giữ luot_xem làm tổng số cố định (seed random + toàn bộ view thật cộng dồn
// qua các lần sync); KV chỉ là bộ đệm view MỚI kể từ lần export gần nhất — nhờ vậy
// script sync-views.ps1 không cần biết baseline, chỉ cần cộng dồn số trả về vào
// luot_xem hiện tại trên WP.
async function handleExport(request, env) {
  const url = new URL(request.url);
  const secret = url.searchParams.get("secret");
  if (!env.SYNC_SECRET || secret !== env.SYNC_SECRET) {
    return new Response("Unauthorized", { status: 401 });
  }

  const result = {};
  let cursor;
  do {
    const list = await env.VIEWS.list({ prefix: "truyen:", cursor });
    for (const k of list.keys) {
      const val = parseInt((await env.VIEWS.get(k.name)) || "0", 10);
      if (val > 0) {
        const id = k.name.slice("truyen:".length);
        result[id] = val;
        await env.VIEWS.delete(k.name);
      }
    }
    cursor = list.list_complete ? undefined : list.cursor;
  } while (cursor);

  return jsonResponse(result);
}
