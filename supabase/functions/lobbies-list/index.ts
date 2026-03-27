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

  // Delete stale lobbies older than 2 hours before listing
  const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
  await supabase.from("lobbies").delete().lt("created_at", twoHoursAgo);

  const { data: lobbies, error } = await supabase
    .from("lobbies")
    .select(`
      *,
      lobby_players ( id, username, team, ready )
    `)
    .eq("is_private", false)
    .eq("status", "waiting")
    .order("created_at", { ascending: false });

  if (error) return Response.json({ error: error.message }, { status: 500, headers: corsHeaders });

  return Response.json({ lobbies }, { headers: corsHeaders });
});
