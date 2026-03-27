import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${jwt}` } } }
  );

  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });

  const { lobby_id, code } = await req.json().catch(() => ({}));
  if (!lobby_id && !code) {
    return Response.json({ error: "lobby_id or code required" }, { status: 400, headers: corsHeaders });
  }

  const { data: account } = await supabase
    .from("accounts").select("*").eq("user_id", user.id).single();
  if (!account) return Response.json({ error: "Account not found" }, { status: 404, headers: corsHeaders });

  // Find the lobby by ID or invite code.
  let query = supabase.from("lobbies").select("*").eq("status", "waiting");
  if (lobby_id) query = query.eq("id", lobby_id);
  else          query = query.eq("code", code);

  const { data: lobby } = await query.single();
  if (!lobby) return Response.json({ error: "Lobby not found" }, { status: 404, headers: corsHeaders });

  // Balance teams: assign to whichever team has fewer players.
  const { data: players } = await supabase
    .from("lobby_players").select("team").eq("lobby_id", lobby.id);
  const teamA = players?.filter((p) => p.team === "A").length ?? 0;
  const teamB = players?.filter((p) => p.team === "B").length ?? 0;
  const team = teamA <= teamB ? "A" : "B";

  const { error } = await supabase.from("lobby_players").insert({
    lobby_id: lobby.id,
    account_id: account.id,
    username: account.username,
    team,
    ready: false,
  });

  if (error) return Response.json({ error: error.message }, { status: 400, headers: corsHeaders });

  return Response.json({ lobby }, { headers: corsHeaders });
});
