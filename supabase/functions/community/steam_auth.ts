// No community accounts or bearer sessions: verify each protected operation.
export const TICKET_IDENTITY = "marble-engineer-community";
export class SteamAuthError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

// Bounded per-isolate protection, not a distributed quota or a ticket cache.
let windowStart = 0, attempts = 0, active = 0;
const recent = new Map<string, number>();
export async function verifySteamTicket(ticket: string): Promise<string> {
  if (!/^(?:[a-fA-F0-9]{2}){1,2560}$/.test(ticket)) {
    throw new SteamAuthError(
      401,
      "authentication_failed",
      "Steam authentication failed. Try again.",
    );
  }
  const key = Deno.env.get("STEAM_WEB_API_KEY"),
    appId = Deno.env.get("STEAM_APP_ID");
  if (
    !key || !appId || !/^[1-9][0-9]{0,9}$/.test(appId) ||
    Number(appId) > 4294967295
  ) {
    throw new SteamAuthError(
      503,
      "steam_unavailable",
      "Steam community authentication is not configured yet.",
    );
  }
  const digest = Array.from(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(ticket.toLowerCase()),
      ),
    ),
  )
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const now = Date.now();
  if (now - windowStart >= 60000) {
    windowStart = now;
    attempts = 0;
    recent.clear();
  }
  if (active >= 4 || attempts >= 60 || now - (recent.get(digest) ?? 0) < 1000) {
    throw new SteamAuthError(
      429,
      "authentication_busy",
      "Steam authentication is busy. Try again shortly.",
    );
  }
  recent.set(digest, now);
  attempts++;
  active++;
  try {
    const url = new URL(
      "https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/",
    );
    url.search = new URLSearchParams({
      key,
      appid: appId,
      ticket,
      identity: TICKET_IDENTITY,
    }).toString();
    const response = await fetch(url, {
      signal: AbortSignal.timeout(8000),
      redirect: "error",
    });
    if (!response.ok) throw new Error("Steam unavailable");
    // SteamID64 must be supplied by Steam as a string; never coerce a JS number.
    const data = await response.json();
    const params = data?.response?.params;
    if (
      params?.result !== "OK" || typeof params.steamid !== "string" ||
      !/^[1-9][0-9]{16,19}$/.test(params.steamid) ||
      BigInt(params.steamid) > 18446744073709551615n
    ) {
      throw new SteamAuthError(
        401,
        "authentication_failed",
        "Steam authentication failed. Try again.",
      );
    }
    return params.steamid;
  } catch (error) {
    if (error instanceof SteamAuthError) throw error;
    throw new SteamAuthError(
      503,
      "steam_unavailable",
      "Could not verify Steam. Try again shortly.",
    );
  } finally {
    active--;
  }
}
