import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

type EnvironmentRequest = { cell_id: string; latitude: number; longitude: number }

const headers = {
  "content-type": "application/json",
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
}

const hasLayer = (features: Array<{ layer?: { id?: string }; properties?: Record<string, unknown> }>, layer: string) =>
  features.some((feature) => feature.layer?.id === layer)

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers })
  if (request.method !== "POST") return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers })
  try {
    const body = await request.json() as EnvironmentRequest
    if (!/^biome:[0-9]+:-?[0-9]+:-?[0-9]+$/.test(body.cell_id) || !Number.isFinite(body.latitude) || !Number.isFinite(body.longitude) || Math.abs(body.latitude) > 90 || Math.abs(body.longitude) > 180) {
      return new Response(JSON.stringify({ error: "invalid_request" }), { status: 400, headers })
    }
    const url = Deno.env.get("SUPABASE_URL")
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!url || !serviceRole) return new Response(JSON.stringify({ error: "function_not_configured" }), { status: 500, headers })
    const admin = createClient(url, serviceRole)
    const now = new Date()
    const { data: cached, error: cacheError } = await admin.from("biome_cache").select("payload, expires_at").eq("cell_id", body.cell_id).maybeSingle()
    if (cacheError) return new Response(JSON.stringify({ error: cacheError.message }), { status: 500, headers })
    if (cached && new Date(cached.expires_at) > now) return new Response(JSON.stringify(cached.payload), { headers })

    const token = Deno.env.get("MAPBOX_ACCESS_TOKEN")
    if (!token) return new Response(JSON.stringify({ error: "environment_provider_not_configured" }), { status: 500, headers })
    const query = new URLSearchParams({
      access_token: token, radius: "120", limit: "50", layers: "water,waterway,landuse,landcover,road,poi_label",
    })
    const endpoint = `https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/${body.longitude},${body.latitude}.json?${query}`
    const response = await fetch(endpoint)
    if (!response.ok) return new Response(JSON.stringify({ error: "environment_upstream_unavailable" }), { status: 502, headers })
    const data = await response.json()
    const features = Array.isArray(data.features) ? data.features : []
    const properties = features.map((feature: { properties?: Record<string, unknown> }) => feature.properties ?? {})
    const propertyText = properties.map((value) => JSON.stringify(value).toLowerCase()).join(" ")
    const signals = {
      isWater: hasLayer(features, "water"), isRiver: hasLayer(features, "waterway") && /river|stream|canal/.test(propertyText),
      isLake: hasLayer(features, "water") && /lake|reservoir/.test(propertyText), isCoast: /coast|ocean|sea/.test(propertyText),
      isGreen: /park|grass|garden|recreation/.test(propertyText), isForest: /forest|wood/.test(propertyText),
      isPark: /park|garden/.test(propertyText), isUrban: /residential|commercial|building/.test(propertyText),
      isIndustrial: /industrial|factory|warehouse/.test(propertyText), isTrail: /path|track|trail/.test(propertyText),
      isLandmark: /museum|monument|historic|heritage/.test(propertyText), elevationMeters: 0, slopePercent: 0,
    }
    const primary = signals.isLandmark ? "heritage" : (signals.isWater || signals.isRiver || signals.isLake || signals.isCoast) ? "waterside" : signals.isIndustrial ? "industrial" : (signals.isGreen || signals.isForest || signals.isPark) ? "green" : signals.isUrban ? "urban" : "open"
    const traits = [signals.isTrail && "trail", signals.isPark && "park", signals.isForest && "forest", signals.isRiver && "river", signals.isLake && "lake", signals.isCoast && "coast", signals.isUrban && "dense", signals.isLandmark && "landmark"].filter(Boolean)
    const expiresAt = new Date(Date.now() + 12 * 60 * 60 * 1000).toISOString()
    const payload = { snapshot: { cellID: body.cell_id, primary, traits, resolvedAt: now.toISOString(), expiresAt } }
    const { error: saveError } = await admin.from("biome_cache").upsert({ cell_id: body.cell_id, payload, fetched_at: now.toISOString(), expires_at: expiresAt }, { onConflict: "cell_id" })
    if (saveError) return new Response(JSON.stringify({ error: saveError.message }), { status: 500, headers })
    return new Response(JSON.stringify(payload), { headers })
  } catch {
    return new Response(JSON.stringify({ error: "invalid_request" }), { status: 400, headers })
  }
})
