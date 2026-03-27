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

  const { lobby_id, ready } = await req.json().catch(() => ({}));
  if (!lobby_id) return Response.json({ error: "lobby_id required" }, { status: 400, headers: corsHeaders });

  const { data: account } = await supabase
    .from("accounts").select("id").eq("user_id", user.id).single();
  if (!account) return Response.json({ error: "Account not found" }, { status: 404, headers: corsHeaders });

  const { error } = await supabase.from("lobby_players")
    .update({ ready: ready ?? true })
    .eq("lobby_id", lobby_id)
    .eq("account_id", account.id);

  if (error) return Response.json({ error: error.message }, { status: 500, headers: corsHeaders });

  return Response.json({ ok: true }, { headers: corsHeaders });
});
