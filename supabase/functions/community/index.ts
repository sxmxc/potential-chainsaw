import { createClient } from "@supabase/supabase-js";
import { compatibility, MAX_BYTES, validatePuzzle } from "./validation.ts";
import { SteamAuthError, verifySteamTicket } from "./steam_auth.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-steam-ticket",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
};
function response(status: number, data: unknown = {}, code = "", message = "") {
  return Response.json({
    api_version: 1,
    ok: status < 400,
    data: status < 400 ? data : {},
    error: status < 400 ? {} : { code, message },
  }, { status, headers: cors });
}
const uuid = (id: string) =>
  /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id);
const metadataColumns =
  "id,title,description,difficulty,revision,schema_version,compatibility,published,created_at,published_at";
async function readBody(req: Request): Promise<unknown> {
  if (!req.headers.get("content-type")?.startsWith("application/json")) {
    throw new Error("Use JSON for publication");
  }
  if (Number(req.headers.get("content-length") ?? 0) > MAX_BYTES) {
    throw new Error("Request is too large");
  }
  const reader = req.body?.getReader();
  if (!reader) throw new Error("Missing request body");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BYTES) {
        await reader.cancel();
        throw new Error("Request is too large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const buffer = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    buffer.set(chunk, offset);
    offset += chunk.length;
  }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer));
}

export async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  try {
    const url = new URL(req.url), route = url.pathname.split("/community/")[1];
    if (!route?.startsWith("v1/")) {
      return response(404, {}, "not_found", "This API route does not exist.");
    }
    const path = route.slice(3),
      id = path.startsWith("puzzles/") ? path.slice(8) : "";
    const publicRead = req.method === "GET" && (path === "puzzles" || uuid(id));
    const protectedRoute = (req.method === "GET" && path === "mine") ||
      (req.method === "POST" && path === "puzzles") ||
      (req.method === "DELETE" && uuid(id));
    if (!publicRead && !protectedRoute) {
      return response(404, {}, "not_found", "This API route does not exist.");
    }
    if (Number(req.headers.get("content-length") ?? 0) > MAX_BYTES) {
      return response(413, {}, "too_large", "Request is too large.");
    }
    const authHeader = req.headers.get("authorization") ?? "";
    const keys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
    const secrets = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    const base = Deno.env.get("SUPABASE_URL")!;
    const publicKey = keys.default ?? Deno.env.get("SUPABASE_ANON_KEY")!;
    const client = createClient(base, publicKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
    });
    let owner = "", steamOwner = "";
    if (!publicRead) {
      const ticket = req.headers.get("x-steam-ticket");
      if (ticket !== null) {
        steamOwner = await verifySteamTicket(ticket);
      } else {
        if (!authHeader.startsWith("Bearer ")) {
          return response(
            401,
            {},
            "sign_in_required",
            "Sign in to publish or manage puzzles.",
          );
        }
        const { data, error } = await client.auth.getUser(authHeader.slice(7));
        if (error || !data.user || data.user.is_anonymous) {
          return response(
            401,
            {},
            "sign_in_required",
            "Sign in again to continue.",
          );
        }
        owner = data.user.id;
      }
    }
    const admin = () =>
      createClient(
        base,
        secrets.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        {
          auth: { persistSession: false, autoRefreshToken: false },
        },
      );
    if (req.method === "GET" && (path === "puzzles" || path === "mine")) {
      const offset = Number(url.searchParams.get("offset") ?? 0),
        search = url.searchParams.get("search") ?? "";
      if (
        !Number.isInteger(offset) || offset < 0 || offset > 10000 ||
        search.length > 100
      ) return response(400, {}, "invalid_request", "Invalid browse filters.");
      let query = (path === "mine" && steamOwner ? admin() : client).from(
        "community_puzzles",
      ).select(metadataColumns)
        .order("published_at", { ascending: false }).order("id").range(
          offset,
          offset + 20,
        );
      if (path === "mine") {
        query = query.eq(
          steamOwner ? "steam_owner_id" : "owner_id",
          steamOwner || owner,
        );
      } else {
        // Catalog additions must not hide existing publications. Clients check
        // the puzzle's schema and registered dependencies when installing it.
        query = query.eq("published", true);
      }
      if (search) {
        query = query.ilike(
          "title",
          "%" + search.replace(/[\\%_]/g, "\\$&") + "%",
        );
      }
      const { data, error } = await query;
      if (error) {
        return response(
          503,
          {},
          "unavailable",
          "Could not load online puzzles.",
        );
      }
      return response(200, {
        puzzles: data.slice(0, 20),
        next_offset: data.length > 20 ? offset + 20 : null,
      });
    }
    if (req.method === "GET" && uuid(id)) {
      const revision = Number(url.searchParams.get("revision"));
      if (!Number.isInteger(revision) || revision < 1 || revision > 100000) {
        return response(
          400,
          {},
          "invalid_request",
          "Choose a puzzle revision.",
        );
      }
      const { data, error } = await client.from("community_revisions").select(
        "definition",
      ).eq("puzzle_id", id).eq("revision", revision).maybeSingle();
      if (error) {
        return response(
          503,
          {},
          "unavailable",
          "Could not download this puzzle.",
        );
      }
      if (!data) {
        return response(
          404,
          {},
          "not_found",
          "This puzzle is no longer available.",
        );
      }
      const puzzle = { ...data.definition, id: `community-${id}-r${revision}` };
      return response(200, { puzzle });
    }
    if (req.method === "POST" && path === "puzzles") {
      let puzzle: Record<string, unknown>;
      try {
        const body = await readBody(req) as Record<string, unknown>;
        puzzle = validatePuzzle(body?.puzzle, body?.compatibility);
      } catch (error) {
        return response(
          400,
          {},
          "invalid_puzzle",
          error instanceof SyntaxError
            ? "Invalid puzzle JSON."
            : (error as Error).message,
        );
      }
      // Only server-verified Steam/Auth identities can reach privileged writes.
      const { data, error } = await admin().rpc("community_publish", {
        p_owner: owner || null,
        p_steam_owner: steamOwner || null,
        p_definition: puzzle,
        p_compatibility: compatibility,
      });
      if (error) {
        if (error.message.includes("revision_conflict")) {
          return response(
            409,
            {},
            "revision_conflict",
            "This revision already contains different content. Revise and test the puzzle again.",
          );
        }
        if (error.message.includes("publication_")) {
          return response(
            429,
            {},
            "publication_limit",
            "The publication limit was reached. Wait before publishing again; each account can store 50 puzzles and 100 revisions per puzzle.",
          );
        }
        return response(
          503,
          {},
          "unavailable",
          "Could not publish this puzzle.",
        );
      }
      return response(200, {
        id: data,
        revision: puzzle.revision,
        share_code: `${data}@${puzzle.revision}`,
      });
    }
    if (req.method === "DELETE" && uuid(id)) {
      const { data, error } = await admin().from("community_puzzles").update({
        published: false,
      }).eq("id", id).eq(
        steamOwner ? "steam_owner_id" : "owner_id",
        steamOwner || owner,
      ).select("id");
      if (error) {
        return response(
          503,
          {},
          "unavailable",
          "Could not unpublish this puzzle.",
        );
      }
      if (!data.length) {
        return response(
          404,
          {},
          "not_found",
          "This puzzle is not owned by your account.",
        );
      }
      return response(200, { id });
    }
    return response(404, {}, "not_found", "This API route does not exist.");
  } catch (error) {
    if (error instanceof SteamAuthError) {
      return response(error.status, {}, error.code, error.message);
    }
    return response(
      503,
      {},
      "unavailable",
      "The community service is temporarily unavailable.",
    );
  }
}
if (import.meta.main) Deno.serve(handleRequest);
