import {
  SteamAuthError,
  TICKET_IDENTITY,
  verifySteamTicket,
} from "./steam_auth.ts";

function assert(condition: unknown, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("Steam verification binds the configured AppID/identity and preserves SteamID64", async () => {
  const previousFetch = globalThis.fetch;
  const names = ["STEAM_WEB_API_KEY", "STEAM_APP_ID"];
  const previous = names.map((name) => Deno.env.get(name));
  Deno.env.set(names[0], "test-server-key");
  Deno.env.set(names[1], "123456");
  let calls = 0;
  globalThis.fetch = (input) => {
    calls++;
    const url = new URL(String(input));
    assert(
      url.hostname === "api.steampowered.com",
      "Verification must use Valve HTTPS",
    );
    assert(
      url.searchParams.get("appid") === "123456",
      "AppID must come from server config",
    );
    assert(
      url.searchParams.get("identity") === TICKET_IDENTITY,
      "Ticket audience is mandatory",
    );
    assert(
      url.searchParams.get("key") === "test-server-key",
      "Key stays on server",
    );
    return Promise.resolve(
      Response.json({
        response: { params: { result: "OK", steamid: "76561198000000001" } },
      }),
    );
  };
  async function rejects(ticket: string, status: number) {
    try {
      await verifySteamTicket(ticket);
      throw new Error("Expected rejection");
    } catch (error) {
      assert(
        error instanceof SteamAuthError && error.status === status,
        "Incorrect rejection",
      );
    }
  }
  try {
    await rejects("not-hex", 401);
    await rejects("aa".repeat(2561), 401);
    assert(calls === 0, "Malformed tickets cannot trigger Valve requests");
    assert(
      await verifySteamTicket("aa11") === "76561198000000001",
      "Steam ID must stay a string",
    );
    await rejects("aa11", 429);
    assert(calls === 1, "Immediate ticket replay is throttled");
    globalThis.fetch = () =>
      Promise.resolve(
        Response.json({
          response: { params: { result: "OK", steamid: 76561198000000001 } },
        }),
      );
    await rejects("aa12", 401);
    globalThis.fetch = () =>
      Promise.resolve(
        Response.json({ response: { error: { errorcode: 101 } } }),
      );
    await rejects("aa13", 401);
    globalThis.fetch = () => Promise.reject(new Error("PRIVATE_SERVER_DETAIL"));
    await rejects("aa14", 503);
    Deno.env.delete("STEAM_WEB_API_KEY");
    await rejects("aa15", 503);
  } finally {
    globalThis.fetch = previousFetch;
    names.forEach((name, i) =>
      previous[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, previous[i]!)
    );
  }
});
