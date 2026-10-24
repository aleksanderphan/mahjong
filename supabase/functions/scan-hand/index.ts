// Edge Function: reads a photo of a winning hand with Google Gemini.
// Replaces Firebase AI Logic. The Gemini key stays on the server:  supabase secrets set GEMINI_API_KEY=...
// Deploy:  supabase functions deploy scan-hand
// Only phones that unlocked the app (has_access()) can call it; the JWT is verified by Supabase (verify_jwt = true).
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

const MAX_IMAGE_CHARS = 8_000_000; // ~6 MB of base64
const MAX_PROMPT_CHARS = 20_000;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);

  const key = Deno.env.get('GEMINI_API_KEY');
  if (!key) return json({ error: 'GEMINI_API_KEY not configured' }, 500);

  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: allowed } = await sb.rpc('has_access');
  if (allowed !== true) return json({ error: 'locked' }, 403);

  let body: { prompt?: string; image?: string; mimeType?: string; model?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }
  const { prompt = '', image = '', mimeType = 'image/jpeg', model = 'gemini-3.8-flash' } = body;
  if (!prompt || prompt.length > MAX_PROMPT_CHARS) return json({ error: 'bad prompt' }, 400);
  if (!image || image.length > MAX_IMAGE_CHARS) return json({ error: 'bad image' }, 400);
  if (!/^image\/(jpeg|png|webp)$/.test(mimeType)) return json({ error: 'bad mime type' }, 400);
  if (!/^[a-z0-9.\-]{3,60}$/.test(model)) return json({ error: 'bad model' }, 400);

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: mimeType, data: image } }] }],
      generationConfig: { responseMimeType: 'application/json', temperature: 0.1 },
    }),
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok) return json({ error: out?.error?.message ?? `Gemini ${res.status}`, status: res.status }, res.status === 429 ? 429 : 502);
  const text = out?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? '').join('') ?? '';
  if (!text) return json({ error: out?.promptFeedback?.blockReason ? `SAFETY blocked: ${out.promptFeedback.blockReason}` : 'Empty answer' }, 502);
  return json({ text });
});
