import { serve } from "https://deno.land/std@0.224.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

type WeatherResponse = {
  cell_id: string
  latitude: number
  longitude: number
}

const headers = {
  "content-type": "application/json",
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers })
  if (request.method !== "POST") return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers })

  try {
    const authorization = request.headers.get("Authorization")
    if (!authorization?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "missing_authorization" }), { status: 401, headers })
    }
    const supabaseURL = Deno.env.get("SUPABASE_URL")
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseURL || !anonKey || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: "function_not_configured" }), { status: 500, headers })
    }
    const userClient = createClient(supabaseURL, anonKey, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) return new Response(JSON.stringify({ error: "invalid_session" }), { status: 401, headers })

    const body = await request.json() as WeatherResponse
    if (!/^weather:[0-9]+:-?[0-9]+:-?[0-9]+$/.test(body.cell_id) || !Number.isFinite(body.latitude) || !Number.isFinite(body.longitude)) {
      return new Response(JSON.stringify({ error: "invalid_request" }), { status: 400, headers })
    }
    if (Math.abs(body.latitude) > 90 || Math.abs(body.longitude) > 180) {
      return new Response(JSON.stringify({ error: "invalid_coordinates" }), { status: 400, headers })
    }

    const adminClient = createClient(supabaseURL, serviceRoleKey)
    const now = new Date()
    const { data: cached, error: cacheError } = await adminClient
      .from("weather_cache")
      .select("payload, expires_at")
      .eq("cell_id", body.cell_id)
      .maybeSingle()
    if (cacheError) return new Response(JSON.stringify({ error: cacheError.message }), { status: 500, headers })
    if (cached && new Date(cached.expires_at) > now) return new Response(JSON.stringify(cached.payload), { headers })

    const params = new URLSearchParams({
      latitude: String(body.latitude),
      longitude: String(body.longitude),
      current: "temperature_2m,precipitation,wind_speed_10m,cloud_cover,weather_code",
      forecast_days: "1",
      timezone: "auto",
    })
    const upstreamURL = Deno.env.get("OPEN_METEO_API_URL") ?? "https://api.open-meteo.com/v1/forecast"
    const apiKey = Deno.env.get("OPEN_METEO_API_KEY")
    if (apiKey) params.set("apikey", apiKey)
    const upstream = await fetch(`${upstreamURL}?${params}`)
    if (!upstream.ok) return new Response(JSON.stringify({ error: "weather_upstream_unavailable" }), { status: 502, headers })
    const data = await upstream.json()
    const current = data.current ?? {}
    const temperature = Number(current.temperature_2m ?? 15)
    const precipitation = Number(current.precipitation ?? 0)
    const wind = Number(current.wind_speed_10m ?? 0)
    const cloud = Number(current.cloud_cover ?? 0)
    const code = Number(current.weather_code ?? 0)
    const condition = code >= 95 || precipitation >= 8 ? "storm"
      : temperature <= 0 && precipitation > 0 ? "frost"
      : temperature >= 32 ? "heat"
      : wind >= 35 ? "wind"
      : precipitation > 0.2 ? "rain" : "clear"
    const observedAt = now.toISOString()
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString()
    const payload = {
      snapshot: {
        cellID: body.cell_id,
        condition,
        temperatureC: temperature,
        precipitationMM: precipitation,
        windKPH: wind,
        cloudCover: cloud,
        observedAt,
        expiresAt,
      },
    }
    const { error: saveError } = await adminClient
      .from("weather_cache")
      .upsert({
        cell_id: body.cell_id,
        payload,
        fetched_at: observedAt,
        expires_at: expiresAt,
      }, { onConflict: "cell_id" })
    if (saveError) return new Response(JSON.stringify({ error: saveError.message }), { status: 500, headers })
    return new Response(JSON.stringify(payload), { headers })
  } catch {
    return new Response(JSON.stringify({ error: "invalid_request" }), { status: 400, headers })
  }
})
