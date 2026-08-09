import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return response({ ok: true });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return response({ error: "Missing authorization" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const mapboxToken = Deno.env.get("MAPBOX_PUBLIC_ACCESS_TOKEN");
  if (!url || !anonKey || !serviceRoleKey || !mapboxToken) return response({ error: "Function is not configured" }, 500);

  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return response({ error: "Invalid session" }, 401);

  const body = await request.json().catch(() => null) as { tile_id?: string; latitude?: number; longitude?: number; is_vault?: boolean; day_key?: string } | null;
  if (!body || typeof body.tile_id !== "string" || typeof body.latitude !== "number" || typeof body.longitude !== "number") return response({ error: "Invalid coordinates" }, 400);
  if (Math.abs(body.latitude) > 90 || Math.abs(body.longitude) > 180) return response({ error: "Invalid coordinates" }, 400);

  const now = new Date();
  const utcDay = now.toISOString().slice(0, 10);
  const isoDay = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const weekday = isoDay.getUTCDay() || 7;
  isoDay.setUTCDate(isoDay.getUTCDate() + 4 - weekday);
  const isoYear = isoDay.getUTCFullYear();
  const week = Math.ceil((((isoDay.getTime() - Date.UTC(isoYear, 0, 1)) / 86_400_000) + 1) / 7);
  const eventScope = body.is_vault === true
    ? `vault:${isoYear}-W${String(week).padStart(2, "0")}`
    : `trail:${utcDay}`;

  const adminClient = createClient(url, serviceRoleKey);
  const { data: existing, error: existingError } = await adminClient
    .from("shared_treasure_events")
    .select("*")
    .eq("created_by", user.id)
    .eq("event_scope", eventScope)
    .maybeSingle();
  if (existingError) return response({ error: existingError.message }, 500);
  if (existing?.claimed_at !== null && existing?.claimed_at !== undefined) {
    return response(existing);
  }
  if (existing && new Date(existing.expires_at) > now) {
    return response(existing);
  }

  const { count: activeCount, error: quotaError } = await adminClient
    .from("shared_treasure_events")
    .select("id", { count: "exact", head: true })
    .eq("created_by", user.id)
    .is("claimed_at", null)
    .gt("expires_at", now.toISOString());
  if (quotaError) return response({ error: quotaError.message }, 500);
  if ((activeCount ?? 0) >= 3) return response({ error: "Active treasure event limit reached" }, 429);

  const searchURL = new URL("https://api.mapbox.com/search/searchbox/v1/category/park");
  searchURL.searchParams.set("proximity", `${body.longitude},${body.latitude}`);
  searchURL.searchParams.set("limit", "10");
  searchURL.searchParams.set("access_token", mapboxToken);
  const mapbox = await fetch(searchURL);
  if (!mapbox.ok) return response({ error: "Map provider unavailable" }, 502);
  const payload = await mapbox.json();
  const feature = payload.features?.[0];
  const coordinates = feature?.geometry?.coordinates;
  const name = feature?.properties?.name ?? feature?.properties?.full_address;
  if (!Array.isArray(coordinates) || coordinates.length < 2 || typeof name !== "string") {
    return response({ error: "No nearby landmark found" }, 404);
  }

  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const row = {
    event_scope: eventScope,
    tile_id: body.tile_id,
    latitude: coordinates[1],
    longitude: coordinates[0],
    name,
    category: "Park",
    clue: `A hidden atlas mark waits near ${name}.`,
    distance_meters: 0,
    is_vault: body.is_vault === true,
    created_by: user.id,
    expires_at: expiresAt,
    claimed_by: null,
    claimed_at: null,
  };
  const { data, error } = await adminClient
    .from("shared_treasure_events")
    .upsert(row, { onConflict: "created_by,event_scope" })
    .select()
    .single();
  if (error) return response({ error: error.message }, 500);
  return response(data);
});
