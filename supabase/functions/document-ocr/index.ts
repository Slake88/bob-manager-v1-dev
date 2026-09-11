import { createClient } from 'npm:@supabase/supabase-js@2';

const H = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};
const PROVIDER = 'google_cloud_vision';
const MODEL = 'DOCUMENT_TEXT_DETECTION';
const MAX_BYTES = 7_000_000;
type J = Record<string, unknown>;

function b64(bytes: Uint8Array) {
  let out = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    out += String.fromCharCode(...bytes.subarray(i, Math.min(i + chunk, bytes.length)));
  }
  return btoa(out);
}

function confidence(annotation: J): number | null {
  const full = annotation.fullTextAnnotation as J | undefined;
  const pages = Array.isArray(full?.pages) ? full!.pages as unknown[] : [];
  const values: number[] = [];
  for (const page of pages) {
    if (!page || typeof page !== 'object') continue;
    const blocks = Array.isArray((page as J).blocks) ? (page as J).blocks as unknown[] : [];
    for (const block of blocks) {
      const value = block && typeof block === 'object' ? (block as J).confidence : null;
      if (typeof value === 'number' && Number.isFinite(value)) values.push(value);
    }
  }
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
}

function visionText(root: J, pdf: boolean) {
  const annotations: J[] = [];
  if (pdf) {
    for (const file of (Array.isArray(root.responses) ? root.responses : [])) {
      if (!file || typeof file !== 'object') continue;
      const responses = Array.isArray((file as J).responses) ? (file as J).responses as unknown[] : [];
      for (const page of responses) {
        if (page && typeof page === 'object') annotations.push(page as J);
      }
    }
  } else {
    for (const item of (Array.isArray(root.responses) ? root.responses : [])) {
      if (item && typeof item === 'object') annotations.push(item as J);
    }
  }
  const texts: string[] = [];
  const confidences: number[] = [];
  for (const annotation of annotations) {
    const error = annotation.error as J | undefined;
    if (typeof error?.message === 'string') throw new Error(`Google Vision: ${error.message}`);
    const full = annotation.fullTextAnnotation as J | undefined;
    if (typeof full?.text === 'string') texts.push(full.text);
    else {
      const basic = Array.isArray(annotation.textAnnotations) ? annotation.textAnnotations as unknown[] : [];
      if (basic[0] && typeof basic[0] === 'object' && typeof (basic[0] as J).description === 'string') {
        texts.push(String((basic[0] as J).description));
      }
    }
    const c = confidence(annotation);
    if (c !== null) confidences.push(c);
  }
  const text = texts.join('\n').trim();
  const score = confidences.length
    ? confidences.reduce((a, b) => a + b, 0) / confidences.length
    : (text ? 0.75 : 0);
  return {
    text: text.slice(0, 100000),
    confidence: Math.max(0, Math.min(1, score)),
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: H });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
      status: 405,
      headers: H,
    });
  }

  const auth = req.headers.get('Authorization') ?? '';
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  let service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  try {
    const keys = JSON.parse(
      Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}',
    ) as Record<string, string>;
    service = keys.default ?? service;
  } catch (_) {}
  if (!auth || !url || !anon || !service) {
    return new Response(
      JSON.stringify({ error: 'supabase_server_config_missing' }),
      { status: 500, headers: H },
    );
  }

  const user = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: auth } },
  });
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  let id = '';

  try {
    const body = await req.json();
    id = String(body?.ocr_id ?? '');
    if (!id) {
      return new Response(JSON.stringify({ error: 'ocr_id_required' }), {
        status: 400,
        headers: H,
      });
    }

    const { data: job, error: jobError } = await user
      .from('document_ocr')
      .select('id,status,document_id,version_id')
      .eq('id', id)
      .single();
    if (jobError || !job) {
      return new Response(
        JSON.stringify({ error: 'ocr_job_not_accessible' }),
        { status: 403, headers: H },
      );
    }

    const status = String(job.status ?? '');
    if (status === 'ready') {
      return new Response(JSON.stringify({ status, ocr_id: id }), {
        status: 200,
        headers: H,
      });
    }
    if (status === 'processing') {
      return new Response(JSON.stringify({ status, ocr_id: id }), {
        status: 202,
        headers: H,
      });
    }
    if (status !== 'pending') {
      return new Response(
        JSON.stringify({ error: 'ocr_job_not_pending', status }),
        { status: 409, headers: H },
      );
    }

    const { data: version, error: versionError } = await user
      .from('document_versions')
      .select('storage_path,mime_type,file_size')
      .eq('id', String(job.version_id ?? ''))
      .single();
    if (versionError || !version) {
      return new Response(
        JSON.stringify({ error: 'document_version_not_accessible' }),
        { status: 403, headers: H },
      );
    }

    const { data: claim, error: claimError } = await admin
      .from('document_ocr')
      .update({
        status: 'processing',
        started_at: new Date().toISOString(),
        completed_at: null,
        error_message: null,
        provider: PROVIDER,
        model: MODEL,
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .eq('status', 'pending')
      .select('id')
      .maybeSingle();
    if (claimError) throw claimError;
    if (!claim) {
      return new Response(
        JSON.stringify({ status: 'already_claimed', ocr_id: id }),
        { status: 202, headers: H },
      );
    }

    await admin
      .from('documents')
      .update({ ocr_status: 'processing', updated_at: new Date().toISOString() })
      .eq('id', String(job.document_id));

    const path = String(version.storage_path ?? '');
    const mime = String(version.mime_type ?? '').toLowerCase();
    const pdf = mime === 'application/pdf';
    if (!path) throw new Error('Documento sem ficheiro para OCR.');
    if (!['image/jpeg', 'image/png', 'image/webp', 'application/pdf'].includes(mime)) {
      throw new Error('Formato OCR não suportado.');
    }

    const key = Deno.env.get('GOOGLE_VISION_API_KEY') ?? '';
    const project = Deno.env.get('GOOGLE_CLOUD_PROJECT_ID') ?? '';
    if (!key || !project) {
      const message =
        'Falta configurar GOOGLE_VISION_API_KEY e GOOGLE_CLOUD_PROJECT_ID nos secrets do Supabase.';
      await admin
        .from('document_ocr')
        .update({
          status: 'unconfigured',
          provider: PROVIDER,
          model: MODEL,
          error_message: message,
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', id);
      await admin
        .from('documents')
        .update({ ocr_status: 'unconfigured', updated_at: new Date().toISOString() })
        .eq('id', String(job.document_id));
      return new Response(
        JSON.stringify({
          status: 'unconfigured',
          reason: 'google_vision_not_configured',
          ocr_id: id,
        }),
        { status: 503, headers: H },
      );
    }

    const { data: file, error: downloadError } = await admin.storage
      .from('club-documents')
      .download(path);
    if (downloadError || !file) {
      throw new Error(
        `Não foi possível obter o documento: ${downloadError?.message ?? 'ficheiro indisponível'}`,
      );
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (!bytes.length) throw new Error('O documento está vazio.');
    if (bytes.length > MAX_BYTES) {
      throw new Error(
        'Para OCR Google Vision direto, comprima o ficheiro para menos de 7 MB.',
      );
    }

    const content = b64(bytes);
    const base =
      `https://eu-vision.googleapis.com/v1/projects/${encodeURIComponent(project)}/locations/eu`;
    const endpoint = pdf ? `${base}/files:annotate` : `${base}/images:annotate`;
    const payload = pdf
      ? {
          requests: [
            {
              inputConfig: { content, mimeType: 'application/pdf' },
              features: [{ type: MODEL }],
              imageContext: { languageHints: ['pt', 'en'] },
              pages: [1, 2, 3, 4, 5],
            },
          ],
        }
      : {
          requests: [
            {
              image: { content },
              features: [{ type: MODEL }],
              imageContext: { languageHints: ['pt', 'en'] },
            },
          ],
        };
    const response = await fetch(`${endpoint}?key=${encodeURIComponent(key)}`, {
      method: 'POST',
      headers: H,
      body: JSON.stringify(payload),
    });
    const raw = await response.text();
    let vision: J = {};
    try {
      vision = raw ? JSON.parse(raw) as J : {};
    } catch (_) {
      vision = { raw };
    }
    if (!response.ok) {
      throw new Error(`Google Vision ${response.status}: ${raw.slice(0, 1200)}`);
    }

    const result = visionText(vision, pdf);
    await admin
      .from('document_ocr')
      .update({
        status: 'ready',
        provider: PROVIDER,
        model: MODEL,
        raw_text: result.text,
        confidence: result.confidence,
        error_message: null,
        completed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id);
    await admin
      .from('documents')
      .update({ ocr_status: 'ready', updated_at: new Date().toISOString() })
      .eq('id', String(job.document_id));
    return new Response(
      JSON.stringify({
        status: 'ready',
        ocr_id: id,
        confidence: result.confidence,
      }),
      { status: 200, headers: H },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (id) {
      const { data: row } = await admin
        .from('document_ocr')
        .select('document_id')
        .eq('id', id)
        .maybeSingle();
      await admin
        .from('document_ocr')
        .update({
          status: 'failed',
          provider: PROVIDER,
          model: MODEL,
          error_message: message.slice(0, 2000),
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', id);
      if (row?.document_id) {
        await admin
          .from('documents')
          .update({ ocr_status: 'failed', updated_at: new Date().toISOString() })
          .eq('id', String(row.document_id));
      }
    }
    return new Response(
      JSON.stringify({ error: 'ocr_failed', message }),
      { status: 500, headers: H },
    );
  }
});
