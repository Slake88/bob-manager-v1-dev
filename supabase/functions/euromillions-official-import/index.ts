import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const requestHeaders = {
  "User-Agent": "Mozilla/5.0 (compatible; BOB-Manager/1.0)",
  "Accept": "text/html,application/xhtml+xml",
  "Accept-Language": "pt-PT,pt;q=0.9,en;q=0.7",
  "Cache-Control": "no-cache",
};

const santaCasaSources = [
  "https://www.jogossantacasa.pt/web/ResultsBoard/",
  "https://www.jogossantacasa.pt/web/ResultsBoard/euromilhoes",
  "https://www.jogossantacasa.pt/web/SCCartazResult/",
  "https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes",
  "https://diadamae.jogossantacasa.pt/web/ResultsBoard/",
  "https://diadamae.jogossantacasa.pt/web/SCCartazResult/",
];

const combos: Array<[number, number, number]> = [
  [1, 5, 2], [2, 5, 1], [3, 5, 0], [4, 4, 2], [5, 4, 1],
  [6, 3, 2], [7, 4, 0], [8, 2, 2], [9, 3, 1], [10, 3, 0],
  [11, 1, 2], [12, 2, 1], [13, 2, 0],
];

type Result = {
  drawNumber: string;
  drawDate: string;
  numbers: number[];
  stars: number[];
  prizes: Record<string, number>;
  source: string;
};

type ExpectedDraw = {
  drawNumber: string;
  drawDate: string;
};

type KeyOnly = {
  drawDate: string;
  numbers: number[];
  stars: number[];
};

function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&euro;|&#8364;/gi, "€")
    .replace(/\s+/g, " ")
    .trim();
}

function euroPt(raw: string): number {
  return Number(raw.replace(/\./g, "").replace(",", "."));
}

function normalizeDrawNumber(raw: string): string {
  const match = raw.match(/(\d{1,3})\s*\/\s*(\d{4})/);
  if (!match) return raw.trim();
  return `${match[1].padStart(3, "0")}/${match[2]}`;
}

function sameKey(a: { numbers: number[]; stars: number[] }, b: { numbers: number[]; stars: number[] }): boolean {
  return a.numbers.join(",") === b.numbers.join(",") && a.stars.join(",") === b.stars.join(",");
}

function validateKey(numbers: number[], stars: number[]): void {
  if (
    numbers.length !== 5 || new Set(numbers).size !== 5 || numbers.some((n) => n < 1 || n > 50) ||
    stars.length !== 2 || new Set(stars).size !== 2 || stars.some((s) => s < 1 || s > 12)
  ) {
    throw new Error("A chave recebida não é válida.");
  }
}

function comboRegex(numbers: number, stars: number): RegExp {
  return new RegExp(
    `\\b${numbers}\\b[^0-9+]{1,100}\\+[^0-9]{0,60}\\b${stars}\\b`,
    "i",
  );
}

function parsePrizesFromSantaCasa(text: string): Record<string, number> {
  const anchors: Array<{ category: number; start: number; end: number }> = [];
  let from = 0;

  for (const [category, numbers, stars] of combos) {
    const match = comboRegex(numbers, stars).exec(text.slice(from));
    if (!match || match.index == null) continue;
    const start = from + match.index;
    const end = start + match[0].length;
    anchors.push({ category, start, end });
    from = end;
  }

  const prizes: Record<string, number> = {};
  for (let i = 0; i < anchors.length; i++) {
    const current = anchors[i];
    const next = anchors[i + 1];
    const end = next?.start ?? Math.min(text.length, current.end + 700);
    const chunk = text.slice(current.end, end);
    const amount = chunk.match(/([0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2})/);
    if (!amount) continue;
    const value = euroPt(amount[1]);
    if (Number.isFinite(value) && value > 0) prizes[String(current.category)] = value;
  }
  return prizes;
}

function parseSantaCasa(text: string): Result {
  const draw = text.match(/Sorteio:\s*([0-9]{1,3}\/[0-9]{4})/i);
  const date = text.match(/Data\s+do\s+Sorteio\s*-\s*([0-9]{2})\/([0-9]{2})\/([0-9]{4})/i);
  if (!draw || !date || date.index == null) {
    throw new Error("Não foi possível interpretar o sorteio oficial.");
  }

  const afterDate = text.slice(date.index + date[0].length, date.index + date[0].length + 900);
  const key = afterDate.match(
    /(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s*\+\s*(\d{1,2})\s+(\d{1,2})/,
  );
  if (!key) throw new Error("Não foi possível interpretar a chave oficial.");

  const numbers = key.slice(1, 6).map(Number).sort((a, b) => a - b);
  const stars = key.slice(6, 8).map(Number).sort((a, b) => a - b);
  validateKey(numbers, stars);

  return {
    drawNumber: normalizeDrawNumber(draw[1]),
    drawDate: `${date[3]}-${date[2]}-${date[1]}`,
    numbers,
    stars,
    prizes: parsePrizesFromSantaCasa(text),
    source: "jogossantacasa.pt",
  };
}

function parseSaiuAgora(text: string, expected: ExpectedDraw): Result {
  const contest = text.match(/Concurso\s+([0-9]{1,3}\/[0-9]{4})/i);
  if (!contest) throw new Error(`Não foi possível interpretar o concurso ${expected.drawNumber}.`);

  const keyAreaStart = text.search(/Chave\s+sorteada/i);
  const prizeAreaStart = text.search(/Pr[eé]mios\s+por\s+escal[aã]o/i);
  if (keyAreaStart < 0 || prizeAreaStart < 0 || prizeAreaStart <= keyAreaStart) {
    throw new Error(`A página do concurso ${expected.drawNumber} está incompleta.`);
  }

  const keyArea = text.slice(keyAreaStart, prizeAreaStart);
  const numericTokens = [...keyArea.matchAll(/\b(\d{1,2})\b/g)].map((m) => Number(m[1]));
  if (numericTokens.length < 7) throw new Error(`Não foi possível ler a chave do concurso ${expected.drawNumber}.`);

  const numbers = numericTokens.slice(0, 5).sort((a, b) => a - b);
  const stars = numericTokens.slice(5, 7).sort((a, b) => a - b);
  validateKey(numbers, stars);

  const prizes: Record<string, number> = {};
  const prizeText = text.slice(prizeAreaStart);
  for (let category = 1; category <= 13; category++) {
    const re = new RegExp(
      `${category}\\.?º?\\s*Pr[eé]mio[\\s\\S]{0,220}?([0-9]{1,3}(?:\\.[0-9]{3})*,[0-9]{2})`,
      "i",
    );
    const match = prizeText.match(re);
    if (!match) continue;
    const value = euroPt(match[1]);
    if (Number.isFinite(value) && value > 0) prizes[String(category)] = value;
  }

  if (Object.keys(prizes).length < 12) {
    throw new Error(`A tabela de prémios do concurso ${expected.drawNumber} está incompleta (${Object.keys(prizes).length}/13).`);
  }

  const drawNumber = normalizeDrawNumber(contest[1]);
  if (drawNumber !== expected.drawNumber) {
    throw new Error(`O histórico devolveu ${drawNumber} quando era esperado ${expected.drawNumber}.`);
  }

  return {
    drawNumber,
    drawDate: expected.drawDate,
    numbers,
    stars,
    prizes,
    source: "jogossantacasa.pt (histórico validado)",
  };
}

function dateOnly(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function expectedDraws(year: number, month: number): ExpectedDraw[] {
  const today = dateOnly(new Date());
  const draws: ExpectedDraw[] = [];
  let ordinal = 0;

  for (let m = 0; m < month; m++) {
    const days = new Date(Date.UTC(year, m + 1, 0)).getUTCDate();
    for (let day = 1; day <= days; day++) {
      const date = new Date(Date.UTC(year, m, day, 12));
      const weekday = date.getUTCDay();
      if (weekday !== 2 && weekday !== 5) continue;
      ordinal++;
      if (m !== month - 1) continue;
      const drawDate = dateOnly(date);
      if (drawDate > today) continue;
      draws.push({
        drawNumber: `${String(ordinal).padStart(3, "0")}/${year}`,
        drawDate,
      });
    }
  }
  return draws;
}

async function fetchHtml(url: string): Promise<string> {
  const response = await fetch(url, { headers: requestHeaders, redirect: "follow" });
  if (!response.ok) throw new Error(`Fonte respondeu ${response.status}.`);
  return await response.text();
}

async function fetchSantaCasaSnapshots(): Promise<Map<string, Result>> {
  const byDate = new Map<string, Result>();
  for (const url of santaCasaSources) {
    try {
      const result = parseSantaCasa(htmlToText(await fetchHtml(url)));
      const current = byDate.get(result.drawDate);
      if (!current || Object.keys(result.prizes).length > Object.keys(current.prizes).length) {
        byDate.set(result.drawDate, result);
      }
    } catch (_) {
      // Uma fonte espelho pode estar temporariamente indisponível.
    }
  }
  return byDate;
}

function parseIrishHistory(text: string): Map<string, KeyOnly> {
  const result = new Map<string, KeyOnly>();
  const dateRe = /(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(\d{2})\/(\d{2})\/(\d{2})/g;
  const matches = [...text.matchAll(dateRe)];

  for (let i = 0; i < matches.length; i++) {
    const match = matches[i];
    if (match.index == null) continue;
    const end = matches[i + 1]?.index ?? text.length;
    const chunk = text.slice(match.index, end);
    const key = chunk.match(
      /Winning\s+numbers\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+Lucky\s+Stars\s+(\d{1,2})\s+(\d{1,2})/i,
    );
    if (!key) continue;
    const numbers = key.slice(1, 6).map(Number).sort((a, b) => a - b);
    const stars = key.slice(6, 8).map(Number).sort((a, b) => a - b);
    try {
      validateKey(numbers, stars);
    } catch (_) {
      continue;
    }
    const year = 2000 + Number(match[3]);
    const drawDate = `${year}-${match[2]}-${match[1]}`;
    result.set(drawDate, { drawDate, numbers, stars });
  }
  return result;
}

async function fetchIrishHistory(): Promise<Map<string, KeyOnly>> {
  const html = await fetchHtml("https://www.lottery.ie/results/euromillions/history");
  return parseIrishHistory(htmlToText(html));
}

async function fetchHistoricalDraw(expected: ExpectedDraw, irish: Map<string, KeyOnly>): Promise<Result> {
  const [year, month, day] = expected.drawDate.split("-");
  const url = `https://saiuagora.pt/euromilhoes/resultado-${day}-${month}-${year}`;
  const mirror = parseSaiuAgora(htmlToText(await fetchHtml(url)), expected);

  const officialCrossCheck = irish.get(expected.drawDate);
  if (!officialCrossCheck) {
    throw new Error(`Não foi possível validar o concurso ${expected.drawNumber} numa segunda fonte oficial.`);
  }
  if (!sameKey(mirror, officialCrossCheck)) {
    throw new Error(`As fontes consultadas não coincidem na chave do concurso ${expected.drawNumber}.`);
  }
  return mirror;
}

function prizeCount(value: unknown): number {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return Object.keys(value as Record<string, unknown>).length;
  }
  return 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const auth = req.headers.get("Authorization");
    if (!auth) {
      return new Response(JSON.stringify({ error: "Autenticação necessária." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const client = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: auth } },
    });

    const body = await req.json().catch(() => ({}));
    const clubId = body.club_id?.toString();
    const year = Number(body.year);
    const month = Number(body.month);
    if (!clubId || !Number.isInteger(year) || !Number.isInteger(month) || month < 1 || month > 12) {
      return new Response(JSON.stringify({ error: "Parâmetros inválidos." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: userData, error: userError } = await client.auth.getUser();
    if (userError || !userData.user) throw new Error("Sessão inválida.");

    const expected = expectedDraws(year, month);
    if (expected.length === 0) {
      return new Response(JSON.stringify({
        imported: false,
        imported_count: 0,
        updated_count: 0,
        skipped_count: 0,
        official_count: 0,
        reason: "no_completed_draws",
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const first = `${year}-${String(month).padStart(2, "0")}-01`;
    const nextMonth = month === 12
      ? `${year + 1}-01-01`
      : `${year}-${String(month + 1).padStart(2, "0")}-01`;

    const { data: existingRows, error: existingError } = await client
      .from("euromillions_results")
      .select("draw_date,official_draw_number,prize_table")
      .eq("club_id", clubId)
      .gte("draw_date", first)
      .lt("draw_date", nextMonth);
    if (existingError) throw existingError;

    const existingByDate = new Map<string, Record<string, unknown>>();
    for (const row of (existingRows ?? []) as Array<Record<string, unknown>>) {
      existingByDate.set(String(row.draw_date), row);
    }

    const needsFetch = expected.filter((draw) => {
      const row = existingByDate.get(draw.drawDate);
      if (!row) return true;
      return normalizeDrawNumber(String(row.official_draw_number ?? "")) !== draw.drawNumber || prizeCount(row.prize_table) < 12;
    });

    if (needsFetch.length === 0) {
      return new Response(JSON.stringify({
        imported: false,
        imported_count: 0,
        updated_count: 0,
        skipped_count: expected.length,
        processed_count: 0,
        official_count: expected.length,
        reason: "already_up_to_date",
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const snapshots = await fetchSantaCasaSnapshots();
    let irishHistory: Map<string, KeyOnly> | null = null;
    let importedCount = 0;
    let updatedCount = 0;
    let skippedCount = 0;
    const processed: Result[] = [];

    for (const draw of expected) {
      const existing = existingByDate.get(draw.drawDate);
      const existingNumber = normalizeDrawNumber(String(existing?.official_draw_number ?? ""));
      if (existing && existingNumber === draw.drawNumber && prizeCount(existing.prize_table) >= 12) {
        skippedCount++;
        continue;
      }

      let parsed = snapshots.get(draw.drawDate);
      if (!parsed || parsed.drawNumber !== draw.drawNumber || Object.keys(parsed.prizes).length < 12) {
        if (irishHistory == null) irishHistory = await fetchIrishHistory();
        parsed = await fetchHistoricalDraw(draw, irishHistory);
      }

      const { error } = await client.rpc("process_euromillions_official_result_v1", {
        target_club: clubId,
        p_draw_date: parsed.drawDate,
        p_draw_number: parsed.drawNumber,
        p_numbers: parsed.numbers,
        p_stars: parsed.stars,
        p_prizes: parsed.prizes,
        p_source: parsed.source,
      });
      if (error) throw error;

      if (existing) updatedCount++;
      else importedCount++;
      processed.push(parsed);
    }

    const processedCount = importedCount + updatedCount;
    return new Response(JSON.stringify({
      imported: processedCount > 0,
      imported_count: importedCount,
      updated_count: updatedCount,
      skipped_count: skippedCount,
      processed_count: processedCount,
      official_count: expected.length,
      draws: processed,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
