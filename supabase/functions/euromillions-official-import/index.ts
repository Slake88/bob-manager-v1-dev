import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const combos: Array<[number, number, number]> = [
  [1, 5, 2], [2, 5, 1], [3, 5, 0], [4, 4, 2], [5, 4, 1],
  [6, 3, 2], [7, 4, 0], [8, 2, 2], [9, 3, 1], [10, 3, 0],
  [11, 1, 2], [12, 2, 1], [13, 2, 0],
];

function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/gi, " ")
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

function parseResult(text: string) {
  const draw = text.match(/Sorteio:\s*([0-9]{3}\/[0-9]{4})/i);
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
    drawNumber: draw[1],
    drawDate: `${date[3]}-${date[2]}-${date[1]}`,
    numbers,
    stars,
    prizes: parsePrizes(text),
  };
}

type Result = ReturnType<typeof parseResult>;

async function fetchOfficial(): Promise<Result> {
  const urls = [
    "https://www.jogossantacasa.pt/web/ResultsBoard/",
    "https://www.jogossantacasa.pt/web/ResultsBoard/euromilhoes",
    "https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes",
    "https://www.jogossantacasa.pt/web/SCCartazResult/",
    "https://diadopai.jogossantacasa.pt/web/ResultsBoard/euromilhoes",
    "https://diadopai.jogossantacasa.pt/web/SCCartazResult/euroMilhoes",
    "https://diadamae.jogossantacasa.pt/web/SCCartazResult/",
  ];

  let best: Result | null = null;
  let validSources = 0;
  let lastError: unknown;

  for (const url of urls) {
    try {
      const response = await fetch(url, {
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; BOB-Manager/1.0)",
          "Accept": "text/html,application/xhtml+xml",
          "Accept-Language": "pt-PT,pt;q=0.9",
          "Cache-Control": "no-cache",
        },
      });
      if (!response.ok) continue;

      const candidate = parseResult(htmlToText(await response.text()));
      validSources++;
      if (
        best == null ||
        candidate.drawDate > best.drawDate ||
        (candidate.drawDate === best.drawDate &&
          Object.keys(candidate.prizes).length > Object.keys(best.prizes).length)
      ) {
        best = candidate;
      }
      if (Object.keys(candidate.prizes).length >= 12) return candidate;
    } catch (error) {
      lastError = error;
    }
  }

  if (best && Object.keys(best.prizes).length >= 10) return best;
  if (best) {
    throw new Error(
      `Resultado encontrado, mas a tabela de prémios está incompleta (${Object.keys(best.prizes).length}/13; ${validSources} fontes válidas).`,
    );
  }
  if (lastError instanceof Error) throw lastError;
  throw new Error("Não foi possível obter o resultado oficial do Euromilhões.");
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

    const parsed = await fetchOfficial();
    const parsedDate = new Date(`${parsed.drawDate}T12:00:00Z`);
    if (parsedDate.getUTCFullYear() !== year || parsedDate.getUTCMonth() + 1 !== month) {
      return new Response(JSON.stringify({
        imported: false,
        reason: "latest_outside_requested_month",
        latest: parsed,
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

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

    return new Response(JSON.stringify({ imported: true, ...parsed }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : String(error) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
