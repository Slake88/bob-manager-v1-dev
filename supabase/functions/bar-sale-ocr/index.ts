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

type Candidate = {
  kind: 'stock' | 'preset';
  product_id?: string;
  sale_option_id?: string;
  sale_option_name?: string;
  preset_id?: string;
  description: string;
  quantity: number;
  confidence: number;
  evidence: string;
};

function response(body: J, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: H });
}

function b64(bytes: Uint8Array) {
  let s = '';
  const n = 0x8000;
  for (let i = 0; i < bytes.length; i += n) {
    s += String.fromCharCode(...bytes.subarray(i, Math.min(i + n, bytes.length)));
  }
  return btoa(s);
}

function normalize(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9x|/\\\-., ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function visionConfidence(root: J) {
  const values: number[] = [];
  const responses = Array.isArray(root.responses) ? root.responses : [];
  for (const item of responses) {
    if (!item || typeof item !== 'object') continue;
    const full = (item as J).fullTextAnnotation as J | undefined;
    const pages = Array.isArray(full?.pages) ? full.pages as unknown[] : [];
    for (const page of pages) {
      if (!page || typeof page !== 'object') continue;
      const blocks = Array.isArray((page as J).blocks)
        ? (page as J).blocks as unknown[]
        : [];
      for (const block of blocks) {
        if (!block || typeof block !== 'object') continue;
        const confidence = (block as J).confidence;
        if (typeof confidence === 'number' && Number.isFinite(confidence)) {
          values.push(confidence);
        }
      }
    }
  }
  if (!values.length) return null;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function visionText(root: J) {
  const responses = Array.isArray(root.responses) ? root.responses : [];
  const texts: string[] = [];
  for (const item of responses) {
    if (!item || typeof item !== 'object') continue;
    const error = (item as J).error as J | undefined;
    if (typeof error?.message === 'string') {
      throw new Error(`Google Vision: ${error.message}`);
    }
    const full = (item as J).fullTextAnnotation as J | undefined;
    if (typeof full?.text === 'string') texts.push(full.text);
  }
  return {
    text: texts.join('\n').trim(),
    confidence: visionConfidence(root),
  };
}

function escaped(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function quantityFromLine(line: string, name: string) {
  const nLine = normalize(line);
  const nName = normalize(name);
  if (!nName || !nLine.includes(nName)) return null;
  const nameRx = escaped(nName);

  const explicitAfter = nLine.match(
    new RegExp(`${nameRx}\\s*(?:[:=-]?\\s*)[x×]\\s*(\\d+(?:[.,]\\d+)?)\\b`),
  );
  if (explicitAfter) {
    return { quantity: Number(explicitAfter[1].replace(',', '.')), confidence: 0.96 };
  }

  const explicitBefore = nLine.match(
    new RegExp(`\\b(\\d+(?:[.,]\\d+)?)\\s*[x×]\\s*${nameRx}`),
  );
  if (explicitBefore) {
    return { quantity: Number(explicitBefore[1].replace(',', '.')), confidence: 0.96 };
  }

  const tail = nLine.slice(nLine.indexOf(nName) + nName.length).trim();
  const marks = tail.match(/(?:^|\s)(x|\||\/|\\)(?=\s|$)/g) ?? [];
  if (marks.length > 0) {
    return { quantity: marks.length, confidence: 0.72 };
  }

  if (!/[€$£]/.test(line)) {
    const standalone = tail.match(/^[:=\- ]*(\d{1,2})(?:\s|$)/);
    if (standalone) {
      const quantity = Number(standalone[1]);
      if (quantity > 0 && quantity <= 50) {
        return { quantity, confidence: 0.78 };
      }
    }
  }
  return null;
}

function saleOptions(product: J) {
  const raw = product.bar_product_sale_options;
  if (!Array.isArray(raw)) return [] as J[];
  return raw
    .filter((value) => value && typeof value === 'object')
    .map((value) => value as J)
    .filter((value) => value.active !== false);
}

function matchSaleOption(line: string, product: J) {
  const options = saleOptions(product);
  if (options.length === 1) return options[0];
  if (options.length === 0) return null;

  const normalizedLine = normalize(line);
  const explicit = options.filter((option) => {
    const optionName = normalize(String(option.name ?? ''));
    return optionName.length > 0 && normalizedLine.includes(optionName);
  });
  if (explicit.length === 1) return explicit[0];
  return null;
}

function suggestions(
  text: string,
  products: J[],
  presets: J[],
): Candidate[] {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean);
  const out: Candidate[] = [];

  for (const product of products) {
    const name = String(product.name ?? '').trim();
    const sku = String(product.sku ?? '').trim();
    if (!name) continue;
    let best: Candidate | null = null;

    for (const line of lines) {
      const normalizedLine = normalize(line);
      const matchesName = normalizedLine.includes(normalize(name));
      const matchesSku = sku.length > 0 && normalizedLine.includes(normalize(sku));
      if (!matchesName && !matchesSku) continue;

      const matchedToken = matchesName ? name : sku;
      const quantity = quantityFromLine(line, matchedToken);
      if (!quantity || !Number.isFinite(quantity.quantity) || quantity.quantity <= 0) {
        continue;
      }

      const option = matchSaleOption(line, product);
      if (!option) {
        // Com várias formas possíveis (ex.: Shot/Dose), nunca adivinhar.
        // A fotografia continua guardada e o utilizador confirma manualmente.
        continue;
      }
      const optionName = String(option.name ?? '').trim();
      const candidate: Candidate = {
        kind: 'stock',
        product_id: String(product.id),
        sale_option_id: String(option.id),
        sale_option_name: optionName,
        description: optionName ? `${name} · ${optionName}` : name,
        quantity: quantity.quantity,
        confidence: quantity.confidence,
        evidence: line.slice(0, 240),
      };
      if (!best || candidate.confidence > best.confidence) best = candidate;
    }
    if (best) out.push(best);
  }

  for (const preset of presets) {
    const name = String(preset.name ?? '').trim();
    if (!name) continue;
    let best: Candidate | null = null;
    for (const line of lines) {
      if (!normalize(line).includes(normalize(name))) continue;
      const quantity = quantityFromLine(line, name);
      if (!quantity || !Number.isFinite(quantity.quantity) || quantity.quantity <= 0) {
        continue;
      }
      const candidate: Candidate = {
        kind: 'preset',
        preset_id: String(preset.id),
        description: name,
        quantity: quantity.quantity,
        confidence: quantity.confidence,
        evidence: line.slice(0, 240),
      };
      if (!best || candidate.confidence > best.confidence) best = candidate;
    }
    if (best) out.push(best);
  }

  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { status: 200, headers: H });
  if (req.method !== 'POST') return response({ error: 'method_not_allowed' }, 405);

  const auth = req.headers.get('Authorization') ?? '';
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  let service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}') as Record<string, string>;
    service = keys.default ?? service;
  } catch (_) {}

  if (!auth || !url || !anon || !service) {
    return response({ error: 'supabase_server_config_missing' }, 500);
  }

  const user = createClient(url, anon, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: auth } },
  });
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let attachmentId = '';
  try {
    const body = await req.json() as J;
    attachmentId = String(body.attachment_id ?? '').trim();
    if (!attachmentId) return response({ error: 'attachment_id_required' }, 400);

    const { data: authData, error: authError } = await user.auth.getUser();
    if (authError || !authData.user) return response({ error: 'authentication_required' }, 401);

    const { data: attachment, error: attachmentError } = await user
      .from('bar_sale_attachments')
      .select('id,club_id,sale_id,storage_path,mime_type,ocr_status')
      .eq('id', attachmentId)
      .single();
    if (attachmentError || !attachment) {
      return response({ error: 'bar_sale_attachment_not_accessible' }, 403);
    }

    const clubId = String(attachment.club_id);
    const { data: allowed, error: permissionError } = await user.rpc(
      'has_club_permission',
      { target_club: clubId, requested_permission: 'manageBar' },
    );
    if (permissionError) throw permissionError;
    if (allowed !== true) return response({ error: 'bar_manage_permission_required' }, 403);

    if (attachment.ocr_status === 'ready') {
      return response({ status: 'ready', attachment_id: attachmentId });
    }

    const { data: claimed, error: claimError } = await admin
      .from('bar_sale_attachments')
      .update({
        ocr_status: 'processing',
        ocr_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', attachmentId)
      .select('storage_path,mime_type')
      .single();
    if (claimError || !claimed) {
      throw claimError ?? new Error('Não foi possível iniciar o OCR.');
    }

    const mime = String(claimed.mime_type ?? '').toLowerCase();
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(mime)) {
      throw new Error('O OCR do cartão aceita apenas JPG, PNG ou WEBP.');
    }

    const key = Deno.env.get('GOOGLE_VISION_API_KEY') ?? '';
    const project = Deno.env.get('GOOGLE_CLOUD_PROJECT_ID') ?? '';
    if (!key || !project) {
      throw new Error('Google Cloud Vision não está configurado no Supabase.');
    }

    const { data: file, error: downloadError } = await admin.storage
      .from('financial-documents')
      .download(String(claimed.storage_path));
    if (downloadError || !file) {
      throw new Error(
        `Não foi possível obter a fotografia: ${downloadError?.message ?? 'ficheiro indisponível'}`,
      );
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (!bytes.length) throw new Error('A fotografia está vazia.');
    if (bytes.length > MAX_BYTES) {
      throw new Error('Comprime a fotografia para menos de 7 MB para OCR.');
    }

    const endpoint = `https://eu-vision.googleapis.com/v1/projects/${encodeURIComponent(project)}/locations/eu/images:annotate`;
    const visionResponse = await fetch(`${endpoint}?key=${encodeURIComponent(key)}`, {
      method: 'POST',
      headers: H,
      body: JSON.stringify({
        requests: [{
          image: { content: b64(bytes) },
          features: [{ type: MODEL }],
          imageContext: { languageHints: ['pt', 'en'] },
        }],
      }),
    });
    const raw = await visionResponse.text();
    let vision: J = {};
    try {
      vision = raw ? JSON.parse(raw) as J : {};
    } catch (_) {
      vision = { raw };
    }
    if (!visionResponse.ok) {
      throw new Error(`Google Vision ${visionResponse.status}: ${raw.slice(0, 800)}`);
    }

    const read = visionText(vision);
    if (!read.text) throw new Error('O OCR não encontrou texto legível no cartão.');

    const [
      { data: products, error: productsError },
      { data: presets, error: presetsError },
    ] = await Promise.all([
      admin
        .from('products')
        .select(
          'id,name,sku,current_stock,bar_product_sale_options(id,name,stock_quantity,public_price,member_price,active,sort_order)',
        )
        .eq('club_id', clubId)
        .eq('inventory_area', 'bar')
        .eq('active', true),
      admin
        .from('bar_sale_presets')
        .select('id,name,unit_price')
        .eq('club_id', clubId)
        .eq('active', true),
    ]);
    if (productsError) throw productsError;
    if (presetsError) throw presetsError;

    const found = suggestions(
      read.text,
      (products ?? []) as J[],
      (presets ?? []) as J[],
    );

    const { error: updateError } = await admin
      .from('bar_sale_attachments')
      .update({
        ocr_status: 'ready',
        ocr_raw_text: read.text.slice(0, 20000),
        ocr_suggestions: found,
        ocr_confidence: read.confidence,
        ocr_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', attachmentId);
    if (updateError) throw updateError;

    return response({
      status: 'ready',
      attachment_id: attachmentId,
      provider: PROVIDER,
      suggestion_count: found.length,
      confidence: read.confidence,
      requires_review: true,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (attachmentId) {
      try {
        await admin
          .from('bar_sale_attachments')
          .update({
            ocr_status: 'failed',
            ocr_error: message.slice(0, 4000),
            updated_at: new Date().toISOString(),
          })
          .eq('id', attachmentId);
      } catch (_) {}
    }
    return response({ error: message, attachment_id: attachmentId || null }, 500);
  }
});
