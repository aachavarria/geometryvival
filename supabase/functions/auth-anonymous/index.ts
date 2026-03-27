// Called after the client signs in anonymously via Supabase Auth.
// Creates the account row with the chosen username.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!jwt) return Response.json({ error: "Unauthorized" }, { status: 401, headers: corsHeaders });

  const { username } = await req.json();
  if (!username?.trim()) {
    return Response.json({ error: "username required" }, { status: 400, headers: corsHeaders });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${jwt}` } } }
  );

  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    return Response.json({ error: "Invalid token" }, { status: 401, headers: corsHeaders });
  }

  // Upsert account — safe to call multiple times
  const { data: account, error } = await supabase
    .from("accounts")
    .upsert({ user_id: user.id, username: username.trim() }, { onConflict: "user_id" })
    .select()
    .single();

  if (error) return Response.json({ error: error.message }, { status: 500, headers: corsHeaders });

  return Response.json({ account }, { headers: corsHeaders });
});
