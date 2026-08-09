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
  const mapboxToken = Deno.env.get("MAPBOX_SEARCH_TOKEN");
  if (!url || !anonKey || !serviceRoleKey || !mapboxToken) return response({ error: "Function is not configured" }, 500);

  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return response({ error: "Invalid session" }, 401);

  const body = await request.json().catch(() => null) as { tile_id?: string; latitude?: number; longitude?: number; is_vault?: boolean; day_key?: string } | null;
  if (!body || typeof body.tile_id !== "string" || typeof body.latitude !== "number" || typeof body.longitude !== "number") return response({ error: "Invalid coordinates" }, 400);
  if (Math.abs(body.latitude) > 90 || Math.abs(body.longitude) > 180) return response({ error: "Invalid coordinates" }, 400);

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

  const adminClient = createClient(url, serviceRoleKey);
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const row = {
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
  };
  const { data, error } = await adminClient.from("shared_treasure_events").insert(row).select().single();
  if (error) return response({ error: error.message }, 500);
  return response(data);
});
