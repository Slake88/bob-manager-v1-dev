import { createClient } from 'npm:@supabase/supabase-js@2';

const H = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

type J = Record<string, unknown>;

function response(body: J, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: H });
}

function text(value: unknown) {
  return typeof value === 'string' ? value.trim() : '';
}

async function googleJson(url: string, init: RequestInit) {
  const result = await fetch(url, init);
  const raw = await result.text();
  let body: J = {};
  try {
    body = raw ? JSON.parse(raw) as J : {};
  } catch (_) {
    body = { raw };
  }
  if (!result.ok) {
    const googleError = body.error && typeof body.error === 'object'
      ? text((body.error as J).message)
      : '';
    throw new Error(
      googleError || `Google Places respondeu com HTTP ${result.status}.`,
    );
  }
  return body;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { status: 200, headers: H });
  if (req.method !== 'POST') return response({ error: 'method_not_allowed' }, 405);

  const auth = req.headers.get('Authorization') ?? '';
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  if (!auth || !url || !anon) {
    return response({ error: 'supabase_server_config_missing' }, 500);
  }

  const user = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: auth } },
  });

  try {
    const { data: authData, error: authError } = await user.auth.getUser();
    if (authError || !authData.user) {
      return response({ error: 'authentication_required' }, 401);
    }

    const body = await req.json() as J;
    const clubId = text(body.club_id);
    const action = text(body.action);
    if (!clubId) return response({ error: 'club_id_required' }, 400);

    const { data: allowed, error: permissionError } = await user.rpc(
      'has_club_permission',
      { target_club: clubId, requested_permission: 'manageEventRoadbook' },
    );
    if (permissionError) throw permissionError;
    if (allowed !== true) {
      return response({ error: 'roadbook_manage_permission_required' }, 403);
    }

    const key = Deno.env.get('GOOGLE_MAPS_API_KEY') ??
      Deno.env.get('GOOGLE_VISION_API_KEY') ?? '';
    if (!key) {
      return response({
        error: 'google_places_not_configured',
        message: 'Google Places ainda não está configurado no servidor.',
      }, 503);
    }

    if (action === 'autocomplete') {
      const input = text(body.input);
      const sessionToken = text(body.session_token);
      if (input.length < 3) return response({ suggestions: [] });
      if (!sessionToken) return response({ error: 'session_token_required' }, 400);

      const google = await googleJson(
        'https://places.googleapis.com/v1/places:autocomplete',
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': key,
            'X-Goog-FieldMask': [
              'suggestions.placePrediction.placeId',
              'suggestions.placePrediction.text.text',
              'suggestions.placePrediction.structuredFormat.mainText.text',
              'suggestions.placePrediction.structuredFormat.secondaryText.text',
            ].join(','),
          },
          body: JSON.stringify({
            input,
            sessionToken,
            languageCode: 'pt',
            regionCode: 'PT',
          }),
        },
      );

      const suggestions = Array.isArray(google.suggestions)
        ? google.suggestions as unknown[]
        : [];
      const normalized = suggestions
        .map((entry) => {
          if (!entry || typeof entry !== 'object') return null;
          const prediction = (entry as J).placePrediction;
          if (!prediction || typeof prediction !== 'object') return null;
          const p = prediction as J;
          const structured = p.structuredFormat && typeof p.structuredFormat === 'object'
            ? p.structuredFormat as J
            : {};
          const mainText = structured.mainText && typeof structured.mainText === 'object'
            ? text((structured.mainText as J).text)
            : '';
          const secondaryText = structured.secondaryText && typeof structured.secondaryText === 'object'
            ? text((structured.secondaryText as J).text)
            : '';
          const fullText = p.text && typeof p.text === 'object'
            ? text((p.text as J).text)
            : '';
          const placeId = text(p.placeId);
          if (!placeId || !fullText) return null;
          return {
            place_id: placeId,
            text: fullText,
            main_text: mainText || fullText,
            secondary_text: secondaryText,
          };
        })
        .filter((entry): entry is NonNullable<typeof entry> => entry !== null);

      return response({ suggestions: normalized });
    }

    if (action === 'details') {
      const placeId = text(body.place_id);
      const sessionToken = text(body.session_token);
      if (!placeId) return response({ error: 'place_id_required' }, 400);
      if (!sessionToken) return response({ error: 'session_token_required' }, 400);

      const params = new URLSearchParams({
        languageCode: 'pt',
        regionCode: 'PT',
        sessionToken,
      });
      const google = await googleJson(
        `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}?${params.toString()}`,
        {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': key,
            'X-Goog-FieldMask': 'id,formattedAddress,location',
          },
        },
      );
      const location = google.location && typeof google.location === 'object'
        ? google.location as J
        : {};
      const latitude = Number(location.latitude);
      const longitude = Number(location.longitude);
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
        throw new Error('O Google Places não devolveu coordenadas válidas para este local.');
      }
      return response({
        place_id: text(google.id) || placeId,
        formatted_address: text(google.formattedAddress),
        latitude,
        longitude,
      });
    }

    return response({ error: 'unsupported_action' }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return response({ error: 'roadbook_places_failed', message }, 500);
  }
});
