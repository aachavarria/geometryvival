import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

async function generateUniqueCode(supabase: ReturnType<typeof createClient>): Promise<string> {
  for (let i = 0; i < 20; i++) {
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const { data } = await supabase.from("lobbies").select("id").eq("code", code).maybeSingle();
    if (!data) return code;
  }
  throw new Error("Could not generate a unique lobby code after 20 attempts");
}

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

  const body = await req.json().catch(() => ({}));
  const is_private: boolean = body.is_private ?? false;

  const { data: account } = await supabase
    .from("accounts").select("*").eq("user_id", user.id).single();
  if (!account) return Response.json({ error: "Account not found" }, { status: 404, headers: corsHeaders });

  const code = await generateUniqueCode(supabase);

  const { data: lobby, error: lobbyError } = await supabase
    .from("lobbies")
    .insert({ code, is_private, owner_id: account.id })
    .select()
    .single();

  if (lobbyError) return Response.json({ error: lobbyError.message }, { status: 500, headers: corsHeaders });

  // Add the owner as the first player. Roll back the lobby if this fails.
  const { error: playerError } = await supabase.from("lobby_players").insert({
    lobby_id: lobby.id,
    account_id: account.id,
    username: account.username,
    team: "A",
    ready: false,
  });

  if (playerError) {
    await supabase.from("lobbies").delete().eq("id", lobby.id);
    return Response.json({ error: playerError.message }, { status: 500, headers: corsHeaders });
  }

  return Response.json({ lobby }, { headers: corsHeaders });
});
