import { serve } from "https://deno.land/std@0.224.0/http/server.ts"

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
    const body = await request.json() as WeatherResponse
    if (!body.cell_id || !Number.isFinite(body.latitude) || !Number.isFinite(body.longitude)) {
      return new Response(JSON.stringify({ error: "invalid_request" }), { status: 400, headers })
    }
    const params = new URLSearchParams({
      latitude: String(body.latitude),
      longitude: String(body.longitude),
      current: "temperature_2m,precipitation,wind_speed_10m,cloud_cover,weather_code",
      forecast_days: "1",
      timezone: "auto",
    })
    const upstream = await fetch(`https://api.open-meteo.com/v1/forecast?${params}`)
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
    const observedAt = new Date().toISOString()
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString()
    return new Response(JSON.stringify({
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
    }), { headers })
  } catch {
    return new Response(JSON.stringify({ error: "invalid_request" }), { status: 400, headers })
  }
})
