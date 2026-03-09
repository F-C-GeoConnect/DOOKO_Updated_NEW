import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const serviceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!)

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  const toBase64Url = (str: string) =>
    btoa(str).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_")

  const header = toBase64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }))
  const payload = toBase64Url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }))

  const signingInput = `${header}.${payload}`
  const enc = new TextEncoder()

  const pemKey = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\n/g, "")

  const keyData = Uint8Array.from(atob(pemKey), c => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8", keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]
  )

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", cryptoKey, enc.encode(signingInput)
  )

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_")

  const jwt = `${signingInput}.${sigB64}`

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`
  })

  const tokenJson = await tokenRes.json()
  console.log("Token response:", JSON.stringify(tokenJson))
  return tokenJson.access_token
}

serve(async (req) => {
  try {
    const body = await req.json()
    console.log("Request body:", JSON.stringify(body))

    const { product_name, seller_name, lat, lon, seller_id } = body

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

    const response = await fetch(
      `${supabaseUrl}/rest/v1/rpc/get_nearby_users`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": serviceRoleKey,
          "Authorization": `Bearer ${serviceRoleKey}`
        },
        body: JSON.stringify({
          target_lat: lat,
          target_lon: lon,
          radius_meters: 15000,
          exclude_user_id: seller_id
        })
      }
    )

    const tokens = await response.json()
    console.log("Nearby tokens:", JSON.stringify(tokens))

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ message: "No nearby users" }), { status: 200 })
    }

    const accessToken = await getAccessToken()
    const projectId = serviceAccount.project_id

    const results = await Promise.all(
      tokens.map(async ({ fcm_token }: { fcm_token: string }) => {
        const res = await fetch(
          `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
          {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${accessToken}`,
              "Content-Type": "application/json"
            },
            body: JSON.stringify({
              message: {
                token: fcm_token,
                notification: {
                  title: "🆕 New Product Nearby!",
                  body: `${product_name} by ${seller_name}`
                },
                data: { product_name, seller_name }
              }
            })
          }
        )
        const result = await res.json()
        console.log("FCM result:", JSON.stringify(result))
        return result
      })
    )

    return new Response(JSON.stringify({ success: true, results }), { status: 200 })

  } catch (err) {
    console.error("Error:", err.message, err.stack)
    return new Response(JSON.stringify({ error: err.message }), { status: 500 })
  }
})