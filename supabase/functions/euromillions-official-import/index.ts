import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const requestHeaders = {
  "User-Agent": "Mozilla/5.0 (compatible; BOB-Manager/1.0)",
  "Accept": "text/html,application/xhtml+xml",
  "Accept-Language": "pt-PT,pt;q=0.9",
  "Cache-Control": "no-cache",
};

const catalogSources = [
  "https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes",
  "https://diadamae.jogossantacasa.pt/web/SCCartazResult/euroMilhoes",
  "https://www.jogossantacasa.pt/web/ResultsBoard/euromilhoes",
  "https://diadamae.jogossantacasa.pt/web/ResultsBoard/euromilhoes",
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
};

type ContestCandidate = {
  baseUrl: string;
  contestId: string;
};

type ExpectedDraw = {
  drawNumber: string;
  drawDate: string;
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
    .replace(/\s+/g, " ")
    .trim();
}

function euro(raw: string): number {
  return Number(raw.replace(/\./g, "").replace(",", "."));
}

function comboRegex(numbers: number, stars: number): RegExp {
  return new RegExp(
    `\\b${numbers}\\b[^0-9+]{1,100}\\+[^0-9]{0,60}\\b${stars}\\b`,
    "i",
  );
}

function parsePrizes(text: string): Record<string, number> {
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
    const value = euro(amount[1]);
    if (Number.isFinite(value) && value > 0) prizes[String(current.category)] = value;
  }

  return prizes;
}

function normalizeDrawNumber(raw: string): string {
  const match = raw.match(/(\d{1,3})\s*\/\s*(\d{4})/);
  if (!match) return raw.trim();
  return `${match[1].padStart(3, "0")}/${match[2]}`;
}

function parseResult(text: string): Result {
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
  if (
    new Set(numbers).size !== 5 || numbers.some((n) => n < 1 || n > 50) ||
    new Set(stars).size !== 2 || stars.some((s) => s < 1 || s > 12)
  ) {
    throw new Error("A chave oficial recebida não é válida.");
  }

  return {
    drawNumber: normalizeDrawNumber(draw[1]),
    drawDate: `${date[3]}-${date[2]}-${date[1]}`,
    numbers,
    stars,
    prizes: parsePrizes(text),
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

function extractContestCandidates(
  html: string,
  baseUrl: string,
): Array<{ drawNumber: string; candidate: ContestCandidate }> {
  const found: Array<{ drawNumber: string; candidate: ContestCandidate }> = [];
  const seen = new Set<string>();

  const add = (label: string, rawValue: string) => {
    const drawMatch = htmlToText(label).match(/(\d{1,3})\s*\/\s*(\d{4})/);
    if (!drawMatch) return;
    const drawNumber = normalizeDrawNumber(`${drawMatch[1]}/${drawMatch[2]}`);
    const value = rawValue.replace(/&amp;/gi, "&").trim();
    const idMatch = value.match(/selectContest=(\d+)/i);
    const contestId = idMatch?.[1] ?? (/^\d+$/.test(value) ? value : null);
    if (!contestId) return;
    const key = `${drawNumber}|${baseUrl}|${contestId}`;
    if (seen.has(key)) return;
    seen.add(key);
    found.push({ drawNumber, candidate: { baseUrl, contestId } });
  };

  const optionRe = /<option\b([^>]*)>([\s\S]*?)<\/option>/gi;
  let option: RegExpExecArray | null;
  while ((option = optionRe.exec(html)) != null) {
    const attrs = option[1];
    const valueMatch = attrs.match(/\bvalue\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
    const value = valueMatch?.[1] ?? valueMatch?.[2] ?? valueMatch?.[3];
    if (value) add(option[2], value);
  }

  const linkRe = /<a\b[^>]*href\s*=\s*(?:"([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)<\/a>/gi;
  let link: RegExpExecArray | null;
  while ((link = linkRe.exec(html)) != null) {
    const href = link[1] ?? link[2] ?? "";
    if (/selectContest=/i.test(href)) add(link[3], href);
  }

  return found;
}

async function fetchHtml(url: string): Promise<string> {
  const response = await fetch(url, { headers: requestHeaders });
  if (!response.ok) throw new Error(`Portal oficial respondeu ${response.status}.`);
  return await response.text();
}

async function loadContestCatalog(): Promise<Map<string, ContestCandidate[]>> {
  const catalog = new Map<string, ContestCandidate[]>();

  for (const baseUrl of catalogSources) {
    try {
      const html = await fetchHtml(baseUrl);
      for (const item of extractContestCandidates(html, baseUrl)) {
        const list = catalog.get(item.drawNumber) ?? [];
        if (!list.some((row) => row.baseUrl === item.candidate.baseUrl && row.contestId === item.candidate.contestId)) {
          list.push(item.candidate);
          catalog.set(item.drawNumber, list);
        }
      }
    } catch (_) {
      // Uma fonte alternativa pode estar temporariamente indisponível.
    }
  }

  if (catalog.size === 0) {
    throw new Error("Não foi possível ler a lista oficial de sorteios do Euromilhões.");
  }
  return catalog;
}

async function fetchOfficialDraw(
  expected: ExpectedDraw,
  candidates: ContestCandidate[],
): Promise<Result> {
  let best: Result | null = null;
  let lastError: unknown;

  for (const candidate of candidates) {
    try {
      const separator = candidate.baseUrl.includes("?") ? "&" : "?";
      const url = `${candidate.baseUrl}${separator}selectContest=${encodeURIComponent(candidate.contestId)}`;
      const parsed = parseResult(htmlToText(await fetchHtml(url)));
      if (parsed.drawNumber !== expected.drawNumber || parsed.drawDate !== expected.drawDate) continue;
      if (best == null || Object.keys(parsed.prizes).length > Object.keys(best.prizes).length) {
        best = parsed;
      }
      if (Object.keys(parsed.prizes).length >= 12) return parsed;
    } catch (error) {
      lastError = error;
    }
  }

  if (best) {
    throw new Error(
      `Sorteio ${expected.drawNumber} encontrado, mas a tabela de prémios está incompleta (${Object.keys(best.prizes).length}/13).`,
    );
  }
  if (lastError instanceof Error) throw lastError;
  throw new Error(`Não foi possível obter o sorteio oficial ${expected.drawNumber}.`);
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
      const number = normalizeDrawNumber(String(row.official_draw_number ?? ""));
      return number !== draw.drawNumber || prizeCount(row.prize_table) < 12;
    });

    const catalog = needsFetch.length > 0 ? await loadContestCatalog() : new Map<string, ContestCandidate[]>();
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

      const candidates = catalog.get(draw.drawNumber) ?? [];
      if (candidates.length === 0) {
        throw new Error(`Não foi possível localizar o sorteio ${draw.drawNumber} no histórico oficial.`);
      }

      const parsed = await fetchOfficialDraw(draw, candidates);
      const { error } = await client.rpc("process_euromillions_official_result_v1", {
        target_club: clubId,
        p_draw_date: parsed.drawDate,
        p_draw_number: parsed.drawNumber,
        p_numbers: parsed.numbers,
        p_stars: parsed.stars,
        p_prizes: parsed.prizes,
        p_source: "jogossantacasa.pt",
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
