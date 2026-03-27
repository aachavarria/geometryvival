import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

const GAMEFLOW_API_URL = "https://dev.api.gameflow.gg/v1";

async function allocateGameServer(players: string[]): Promise<{ address: string; port: number }> {
  const gameId = Deno.env.get("GAMEFLOW_GAME_ID");
  const apiKey = Deno.env.get("GAMEFLOW_API_KEY");

  if (!gameId || !apiKey) throw new Error("GAMEFLOW_GAME_ID and GAMEFLOW_API_KEY must be set");

  const res = await fetch(`${GAMEFLOW_API_URL}/fleets/${encodeURIComponent(gameId)}/allocate`, {
    method: "POST",
    headers: { "X-Api-Key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({ region: "us-east", payload: JSON.stringify({ players }) }),
  });

  if (!res.ok) throw new Error(`GameFlow error (${res.status}): ${await res.text()}`);

  const data = await res.json();
  console.log("[GameFlow] allocate response:", JSON.stringify(data));
  // GameFlow returns the game server directly at the root level
  const alloc = data.allocation ?? data;
  const addr = alloc.address;
  const port = alloc.port;
  if (!addr || !port) throw new Error(`Unexpected GameFlow response: ${JSON.stringify(data)}`);
  return { address: addr, port };
}

Deno.serve(async (req) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  try {
    const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
    if (!jwt) return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${jwt}` } } }
    );

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });

    const { lobby_id } = await req.json();

    const { data: account } = await supabase
      .from("accounts").select("id").eq("user_id", user.id).single();
    if (!account) return Response.json({ error: "Account not found" }, { status: 404, headers: corsHeaders });

    // Verify requester is the lobby owner
    const { data: lobby } = await supabase
      .from("lobbies").select("*").eq("id", lobby_id).single();
    if (!lobby) return Response.json({ error: "Lobby not found" }, { status: 404, headers: corsHeaders });
    if (lobby.owner_id !== account.id) return Response.json({ error: "Only owner can start" }, { status: 403, headers: corsHeaders });

    // Check all players are ready
    const { data: players } = await supabase
      .from("lobby_players").select("*").eq("lobby_id", lobby_id);
    if (!players || players.length === 0) return Response.json({ error: "No players" }, { status: 400, headers: corsHeaders });

    const allReady = players.every(p => p.ready);
    if (!allReady) return Response.json({ error: "Not all players are ready" }, { status: 400, headers: corsHeaders });

    // Allocate game server
    const playerIds = players.map(p => p.account_id);
    const server = await allocateGameServer(playerIds);

    // Mark lobby as started and store server info (triggers Realtime for all clients)
    await supabase.from("lobbies").update({
      status: "started",
      server_address: server.address,
      server_port: server.port,
    }).eq("id", lobby_id);

    return Response.json({
      server: { address: server.address, port: server.port },
      players,
    }, { headers: corsHeaders });
  } catch (err) {
    console.error("[lobbies-start] unhandled error:", err);
    return Response.json({ error: String(err) }, { status: 500, headers: corsHeaders });
  }
});
