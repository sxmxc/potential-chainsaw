import { handleRequest } from "./index.ts";
import { compatibility } from "./validation.ts";

async function withConfiguration(run: () => Promise<void>) {
  const names = [
    "SUPABASE_URL",
    "SUPABASE_PUBLISHABLE_KEYS",
    "SUPABASE_SECRET_KEYS",
    "STEAM_APP_ID",
    "STEAM_WEB_API_KEY",
  ];
  const previous = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://example.supabase.co");
  Deno.env.set(names[1], '{"default":"sb_publishable_test"}');
  Deno.env.set(names[2], '{"default":"sb_secret_test"}');
  Deno.env.set(names[3], "123456");
  Deno.env.set(names[4], "test-server-key");
  try {
    await run();
  } finally {
    names.forEach((name, i) =>
      previous[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, previous[i]!)
    );
  }
}
async function expect(req: Request, status: number, code: string) {
  const result = await handleRequest(req), body = await result.json();
  if (
    result.status !== status || body.api_version !== 1 || body.ok !== false ||
    body.error.code !== code
  ) throw new Error("Incorrect API error contract");
}
Deno.test("versioned routes and public malformed browse requests", async () => {
  await withConfiguration(async () => {
    await expect(
      new Request("https://example.test/community/v2/puzzles"),
      404,
      "not_found",
    );
    await expect(
      new Request("https://example.test/community/v1/puzzles?offset=-1"),
      400,
      "invalid_request",
    );
    await expect(
      new Request(
        "https://example.test/community/v1/puzzles/10000000-0000-0000-0000-000000000001?revision=0",
      ),
      400,
      "invalid_request",
    );
  });
});
Deno.test("publication, unpublication and owned listings require a user session", async () => {
  await withConfiguration(async () => {
    for (
      const [path, method] of [["puzzles", "POST"], ["mine", "GET"], [
        "puzzles/10000000-0000-0000-0000-000000000001",
        "DELETE",
      ]]
    ) {
      await expect(
        new Request(`https://example.test/community/v1/${path}`, {
          method,
          headers: { apikey: "sb_publishable_test" },
        }),
        401,
        "sign_in_required",
      );
    }
  });
});
Deno.test("a publishable key cannot impersonate a user's bearer token", async () => {
  await withConfiguration(async () => {
    const previous = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(
        Response.json({ msg: "Invalid JWT", code: "bad_jwt" }, { status: 401 }),
      );
    try {
      await expect(
        new Request("https://example.test/community/v1/puzzles", {
          method: "POST",
          headers: { Authorization: "Bearer sb_publishable_test" },
        }),
        401,
        "sign_in_required",
      );
    } finally {
      globalThis.fetch = previous;
    }
  });
});

Deno.test("catalog additions preserve browsing and downloads of existing publications", async () => {
  await withConfiguration(async () => {
    const previous = globalThis.fetch;
    const id = "10000000-0000-0000-0000-000000000001";
    const oldCatalog = "a".repeat(64);
    const fixture = JSON.parse(await Deno.readTextFile(
      "../../../resources/campaign/01-first-connection.json",
    ));
    for (const key of ["chapter", "order", "prerequisites", "campaign"]) {
      delete fixture[key];
    }
    let reads = 0;
    globalThis.fetch = (input) => {
      const url = new URL(String(input));
      if (url.pathname.endsWith("/community_puzzles")) {
        if (url.searchParams.has("compatibility") ||
          url.searchParams.get("published") !== "eq.true") {
          throw new Error("Public browse must retain published visibility without catalog filtering");
        }
        reads++;
        return Promise.resolve(Response.json([
          { id, revision: 1, schema_version: 2, compatibility: oldCatalog },
        ]));
      }
      if (url.pathname.endsWith("/community_revisions")) {
        if (url.searchParams.get("puzzle_id") !== `eq.${id}` ||
          url.searchParams.get("revision") !== "eq.1") {
          throw new Error("Download must retain exact puzzle and revision selection");
        }
        reads++;
        return Promise.resolve(Response.json({ definition: fixture }));
      }
      throw new Error("Unexpected network request");
    };
    try {
      // Existing clients still send their old digest; newer clients may omit it.
      for (const digest of [compatibility, oldCatalog, ""]) {
        const suffix = digest ? `&compatibility=${digest}` : "";
        const browse = await handleRequest(new Request(
          `https://example.test/community/v1/puzzles?offset=0${suffix}`,
        ));
        const listed = await browse.json();
        if (browse.status !== 200 ||
          listed.data.puzzles[0].compatibility !== oldCatalog) {
          throw new Error("An existing publication disappeared after a catalog update");
        }
        const download = await handleRequest(new Request(
          `https://example.test/community/v1/puzzles/${id}?revision=1${suffix}`,
        ));
        const fetched = await download.json();
        if (download.status !== 200 ||
          fetched.data.puzzle.id !== `community-${id}-r1` ||
          fetched.data.puzzle.pieces[0].piece !== fixture.pieces[0].piece) {
          throw new Error("An existing revision could not be downloaded unchanged");
        }
      }
      if (reads !== 6) throw new Error("Browse or download skipped the normal data path");
    } finally {
      globalThis.fetch = previous;
    }
  });
});

Deno.test("Steam publication and management use only the Valve-verified owner", async () => {
  await withConfiguration(async () => {
    const previous = globalThis.fetch;
    const owner = "76561198000000001";
    let verification = 0, writes = 0, reads = 0;
    const id = "10000000-0000-0000-0000-000000000001";
    globalThis.fetch = async (input, init) => {
      const url = new URL(String(input));
      if (url.hostname === "api.steampowered.com") {
        verification++;
        return Response.json({
          response: { params: { result: "OK", steamid: owner } },
        });
      }
      if (url.pathname.endsWith("/rpc/community_publish")) {
        const body = JSON.parse(String(init?.body));
        if (body.p_owner !== null || body.p_steam_owner !== owner ||
          body.p_compatibility !== compatibility) {
          throw new Error("Unverified owner used");
        }
        writes++;
        return Response.json(id);
      }
      if (url.pathname.endsWith("/community_puzzles")) {
        if (
          url.searchParams.get("steam_owner_id") !== `eq.${owner}` ||
          url.searchParams.has("owner_id")
        ) {
          throw new Error("Missing verified ownership filter");
        }
        reads++;
        // No matching owner: DELETE must fail, not report successful unpublication.
        return Response.json([]);
      }
      throw new Error("Unexpected network request");
    };
    try {
      const fixture = JSON.parse(
        await Deno.readTextFile(
          "../../../resources/campaign/01-first-connection.json",
        ),
      );
      for (const key of ["chapter", "order", "prerequisites", "campaign"]) {
        delete fixture[key];
      }
      const result = await handleRequest(
        new Request("https://example.test/community/v1/puzzles", {
          method: "POST",
          headers: {
            "x-steam-ticket": "bb11",
            "content-type": "application/json",
            "x-steam-id": "76561198000000002",
          },
          body: JSON.stringify({ puzzle: fixture, compatibility: "a".repeat(64) }),
        }),
      );
      if (result.status !== 200 || writes !== 1) {
        throw new Error("Verified publish failed");
      }
      await result.json();
      const mine = await handleRequest(
        new Request("https://example.test/community/v1/mine", {
          headers: { "x-steam-ticket": "bb12" },
        }),
      );
      if (mine.status !== 200) throw new Error("Owned listing failed");
      await mine.json();
      await expect(
        new Request(`https://example.test/community/v1/puzzles/${id}`, {
          method: "DELETE",
          headers: { "x-steam-ticket": "bb13" },
        }),
        404,
        "not_found",
      );
      if (reads !== 2 || verification !== 3) {
        throw new Error("Every protected operation needs fresh verification");
      }
      await expect(
        new Request("https://example.test/community/v1/mine", {
          headers: { "x-steam-ticket": "invalid" },
        }),
        401,
        "authentication_failed",
      );
      if (verification !== 3) throw new Error("Malformed ticket reached Valve");
      await expect(
        new Request("https://example.test/community/v1/puzzles", {
          method: "POST",
          headers: { "x-steam-ticket": "bb14", "content-length": "5000001" },
        }),
        413,
        "too_large",
      );
      if (verification !== 3) {
        throw new Error("Oversized request reached Valve");
      }
    } finally {
      globalThis.fetch = previous;
    }
  });
});
