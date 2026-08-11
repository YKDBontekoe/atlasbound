import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const blockedTerms = ["discord.gg", "t.me/", "telegram.me/"];

function inviteCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, value => alphabet[value % alphabet.length]).join("");
}

Deno.serve(async request => {
  if (request.method === "OPTIONS") return reply({ ok: true });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply({ error: "Missing authorization" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) return reply({ error: "Function is not configured" }, 500);

  const client = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user } } = await client.auth.getUser();
  if (!user) return reply({ error: "Invalid session" }, 401);
  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  if (!body || typeof body.action !== "string") return reply({ error: "Invalid request" }, 400);
  const admin = createClient(url, serviceRoleKey);

  const { data: memberships, error: memberError } = await admin.from("crew_members").select("crew_id").eq("user_id", user.id).limit(1);
  if (memberError) return reply({ error: memberError.message }, 500);

  if (body.action === "create_crew") {
    const name = typeof body.name === "string" ? body.name.trim() : "";
    if (!/^[\p{L}\p{N} _-]{3,24}$/u.test(name)) return reply({ error: "Crew names must be 3–24 letters, numbers, spaces, _ or -." }, 400);
    if ((memberships?.length ?? 0) > 0) return reply({ error: "Leave your current crew before creating another." }, 409);
    let crew: { id: string; invite_code: string; name: string } | null = null;
    for (let attempt = 0; attempt < 3 && !crew; attempt += 1) {
      const { data, error } = await admin.from("crews").insert({ name, invite_code: inviteCode(), created_by: user.id }).select("id,name,invite_code").maybeSingle();
      if (!error) crew = data;
    }
    if (!crew) return reply({ error: "Couldn’t create that crew. Try another name." }, 409);
    const { error } = await admin.from("crew_members").insert({ crew_id: crew.id, user_id: user.id, role: "owner" });
    if (error) return reply({ error: error.message }, 500);
    return reply(crew, 201);
  }

  if (body.action === "join_crew") {
    const code = typeof body.invite_code === "string" ? body.invite_code.trim().toUpperCase() : "";
    if (!/^[A-Z2-9]{8}$/.test(code)) return reply({ error: "Enter an eight-character crew code." }, 400);
    if ((memberships?.length ?? 0) > 0) return reply({ error: "Leave your current crew before joining another." }, 409);
    const { data: crew, error: findError } = await admin.from("crews").select("id,name,invite_code").eq("invite_code", code).maybeSingle();
    if (findError || !crew) return reply({ error: "Crew code not found." }, 404);
    const { count, error: countError } = await admin.from("crew_members").select("user_id", { count: "exact", head: true }).eq("crew_id", crew.id);
    if (countError) return reply({ error: countError.message }, 500);
    if ((count ?? 0) >= 12) return reply({ error: "That crew is full." }, 409);
    const { error } = await admin.from("crew_members").insert({ crew_id: crew.id, user_id: user.id, role: "member" });
    if (error) return reply({ error: error.message }, 409);
    return reply(crew);
  }

  if (body.action === "send_chat") {
    const crewID = typeof body.crew_id === "string" ? body.crew_id : "";
    const message = typeof body.message === "string" ? body.message.trim() : "";
    if (!crewID || message.length < 1 || message.length > 500 || /https?:\/\//i.test(message) || blockedTerms.some(term => message.toLowerCase().includes(term))) return reply({ error: "That message can’t be sent." }, 400);
    const isMember = await admin.from("crew_members").select("user_id").eq("crew_id", crewID).eq("user_id", user.id).maybeSingle();
    if (!isMember.data) return reply({ error: "You are not in that crew." }, 403);
    const since = new Date(Date.now() - 10_000).toISOString();
    const { count } = await admin.from("crew_chat_messages").select("id", { count: "exact", head: true }).eq("author_id", user.id).gte("created_at", since);
    if ((count ?? 0) >= 5) return reply({ error: "Slow down a moment before sending another message." }, 429);
    const { data, error } = await admin.from("crew_chat_messages").insert({ crew_id: crewID, author_id: user.id, body: message }).select().single();
    if (error) return reply({ error: error.message }, 500);
    return reply(data, 201);
  }

  return reply({ error: "Unknown action" }, 400);
});
