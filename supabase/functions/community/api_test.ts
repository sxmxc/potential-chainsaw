import { handleRequest } from "./index.ts";

async function withConfiguration(run: () => Promise<void>) {
  const names = ["SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEYS"];
  const previous = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "https://example.supabase.co");
  Deno.env.set(names[1], '{"default":"sb_publishable_test"}');
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
