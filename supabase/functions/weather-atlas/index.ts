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
    const supabaseURL = Deno.env.get("SUPABASE_URL")
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    if (!supabaseURL || !serviceRoleKey) {
      return new Response(JSON.stringify({ error: "function_not_configured" }), { status: 500, headers })
    }

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
      hourly: "temperature_2m,apparent_temperature,precipitation,precipitation_probability,snowfall,weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m,cloud_cover,visibility",
      forecast_days: "2",
      timezone: "GMT",
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
    const weatherCondition = (temperature: number, precipitation: number, wind: number, code: number) =>
      [95, 96, 99].includes(code) || precipitation >= 8 ? "storm"
        : [45, 48].includes(code) ? "fog"
        : [71, 73, 75, 77, 85, 86].includes(code) ? "snow"
        : temperature <= 0 && precipitation > 0 ? "frost"
        : temperature >= 32 ? "heat"
        : wind >= 35 ? "wind"
        : precipitation > 0.2 ? "rain"
        : cloud >= 55 ? "cloudy" : "clear"
    const condition = weatherCondition(temperature, precipitation, wind, code)
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
        hourly: (data.hourly?.time ?? []).slice(0, 24).map((time: string, index: number) => ({
          date: new Date(`${time}Z`).toISOString(),
          condition: weatherCondition(Number(data.hourly.temperature_2m?.[index] ?? temperature), Number(data.hourly.precipitation?.[index] ?? 0), Number(data.hourly.wind_speed_10m?.[index] ?? 0), Number(data.hourly.weather_code?.[index] ?? 0)),
          temperatureC: Number(data.hourly.temperature_2m?.[index] ?? temperature),
          apparentTemperatureC: Number(data.hourly.apparent_temperature?.[index] ?? temperature),
          precipitationMM: Number(data.hourly.precipitation?.[index] ?? 0),
          precipitationProbability: Number(data.hourly.precipitation_probability?.[index] ?? 0),
          snowfallCM: Number(data.hourly.snowfall?.[index] ?? 0),
          windKPH: Number(data.hourly.wind_speed_10m?.[index] ?? 0),
          windGustKPH: Number(data.hourly.wind_gusts_10m?.[index] ?? 0),
          windDirection: Number(data.hourly.wind_direction_10m?.[index] ?? 0),
          cloudCover: Number(data.hourly.cloud_cover?.[index] ?? 0),
          visibilityMeters: Number(data.hourly.visibility?.[index] ?? 0),
        })),
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
