import { createClient } from 'npm:@supabase/supabase-js@2';

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type ClaimedDelivery = {
  delivery_id: string;
  notification_id: string;
  push_device_id: string;
  push_token: string;
  title: string;
  body: string;
  priority?: string | null;
  module_code?: string | null;
  entity_type?: string | null;
  entity_id?: string | null;
  action_route?: string | null;
};

const jsonHeaders = { 'Content-Type': 'application/json' };

function base64UrlBytes(input: Uint8Array): string {
  let binary = '';
  for (const byte of input) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function base64UrlText(input: string): string {
  return base64UrlBytes(new TextEncoder().encode(input));
}

function pemToBytes(pem: string): Uint8Array {
  const raw = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replaceAll(/\s/g, '');
  const binary = atob(raw);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function googleAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlText(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64UrlText(JSON.stringify({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  ));
  const assertion = `${unsigned}.${base64UrlBytes(signature)}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const body = await response.json();
  if (!response.ok || !body.access_token) {
    throw new Error(`OAuth Google falhou (${response.status}): ${JSON.stringify(body)}`);
  }
  return String(body.access_token);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}';
  let secretKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  try {
    const secretKeys = JSON.parse(secretKeysRaw) as Record<string, string>;
    secretKey = secretKeys.default ?? secretKey;
  } catch (_) {
    // Fallback para SUPABASE_SERVICE_ROLE_KEY em ambientes antigos.
  }
  if (!supabaseUrl || !secretKey) {
    return new Response(JSON.stringify({ error: 'supabase_server_config_missing' }), {
      status: 500,
      headers: jsonHeaders,
    });
  }

  const admin = createClient(supabaseUrl, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let deliveryId = '';
  try {
    const requestBody = await req.json();
    deliveryId = String(requestBody?.delivery_id ?? '');
    const dispatchToken = String(requestBody?.dispatch_token ?? '');
    if (!deliveryId || !dispatchToken) {
      return new Response(JSON.stringify({ error: 'invalid_dispatch_capability' }), {
        status: 401,
        headers: jsonHeaders,
      });
    }

    const { data: claimed, error: claimError } = await admin.rpc(
      'claim_push_delivery_v1',
      { p_delivery: deliveryId, p_dispatch_token: dispatchToken },
    );
    if (claimError) throw claimError;
    if (!claimed) {
      return new Response(JSON.stringify({ status: 'ignored' }), {
        status: 200,
        headers: jsonHeaders,
      });
    }

    const delivery = claimed as ClaimedDelivery;
    const serviceAccountRaw = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    if (!serviceAccountRaw) {
      await admin.rpc('complete_push_delivery_v1', {
        p_delivery: delivery.delivery_id,
        p_status: 'deferred',
        p_provider_message_id: null,
        p_error: 'FCM_SERVICE_ACCOUNT_JSON ainda não configurado no Supabase.',
      });
      return new Response(JSON.stringify({ status: 'deferred', reason: 'fcm_not_configured' }), {
        status: 202,
        headers: jsonHeaders,
      });
    }

    const serviceAccount = JSON.parse(serviceAccountRaw) as ServiceAccount;
    if (!serviceAccount.project_id || !serviceAccount.client_email || !serviceAccount.private_key) {
      throw new Error('FCM_SERVICE_ACCOUNT_JSON incompleto.');
    }

    const accessToken = await googleAccessToken(serviceAccount);
    const priority = String(delivery.priority ?? 'normal').toLowerCase();
    const highPriority = priority === 'high' || priority === 'urgent';
    const data: Record<string, string> = {
      notification_id: delivery.notification_id,
      module_code: String(delivery.module_code ?? 'general'),
      entity_type: String(delivery.entity_type ?? ''),
      entity_id: String(delivery.entity_id ?? ''),
      action_route: String(delivery.action_route ?? ''),
    };

    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(serviceAccount.project_id)}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: delivery.push_token,
            notification: {
              title: delivery.title || 'BOB Manager',
              body: delivery.body || delivery.title || 'Nova notificação',
            },
            data,
            android: {
              priority: highPriority ? 'HIGH' : 'NORMAL',
              notification: { sound: 'default' },
            },
            apns: {
              headers: { 'apns-priority': highPriority ? '10' : '5' },
              payload: { aps: { sound: 'default' } },
            },
          },
        }),
      },
    );

    const raw = await fcmResponse.text();
    let parsed: Record<string, unknown> = {};
    try {
      parsed = raw ? JSON.parse(raw) : {};
    } catch (_) {
      parsed = { raw };
    }

    if (!fcmResponse.ok) {
      const errorText = JSON.stringify(parsed);
      if (errorText.includes('UNREGISTERED') || errorText.includes('registration-token-not-registered')) {
        await admin.rpc('deactivate_push_device_server_v1', {
          p_device: delivery.push_device_id,
        });
      }
      await admin.rpc('complete_push_delivery_v1', {
        p_delivery: delivery.delivery_id,
        p_status: 'failed',
        p_provider_message_id: null,
        p_error: `FCM ${fcmResponse.status}: ${errorText}`,
      });
      return new Response(JSON.stringify({ status: 'failed', provider_status: fcmResponse.status }), {
        status: 502,
        headers: jsonHeaders,
      });
    }

    const providerMessageId = typeof parsed.name === 'string' ? parsed.name : null;
    await admin.rpc('complete_push_delivery_v1', {
      p_delivery: delivery.delivery_id,
      p_status: 'sent',
      p_provider_message_id: providerMessageId,
      p_error: null,
    });

    return new Response(JSON.stringify({ status: 'sent', message_id: providerMessageId }), {
      status: 200,
      headers: jsonHeaders,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (deliveryId) {
      try {
        await admin.rpc('complete_push_delivery_v1', {
          p_delivery: deliveryId,
          p_status: 'failed',
          p_provider_message_id: null,
          p_error: message,
        });
      } catch (_) {
        // Evita mascarar o erro original.
      }
    }
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: jsonHeaders,
    });
  }
});
