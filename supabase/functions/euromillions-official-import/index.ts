import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const htmlEntities: Record<string, string> = {
  nbsp: " ", amp: "&", quot: '"', apos: "'", lt: "<", gt: ">",
  ordm: "º", euro: "€", aacute: "á", eacute: "é", iacute: "í",
  oacute: "ó", uacute: "ú", agrave: "à", atilde: "ã", otilde: "õ",
  acirc: "â", ecirc: "ê", ocirc: "ô", ccedil: "ç",
};

function decodeHtmlEntities(value: string): string {
  return value.replace(
    /&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]+);?/gi,
    (match, entity: string) => {
      if (entity.startsWith("#x") || entity.startsWith("#X")) {
        const code = Number.parseInt(entity.slice(2), 16);
        return Number.isFinite(code) ? String.fromCodePoint(code) : match;
      }
      if (entity.startsWith("#")) {
        const code = Number.parseInt(entity.slice(1), 10);
        return Number.isFinite(code) ? String.fromCodePoint(code) : match;
      }
      return htmlEntities[entity.toLowerCase()] ?? match;
    },
  );
}

function cleanHtml(html: string): string {
  const withoutMarkup = html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ");

  return decodeHtmlEntities(withoutMarkup)
    .replace(/\u00a0/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .normalize("NFC");
}

function euroToNumber(raw: string): number {
  return Number(raw.replace(/\./g, "").replace(",", "."));
}

function ordinalHeader(category: number): RegExp {
  return new RegExp(`\\b${category}\\s*\\.?\\s*(?:Â?º|o)`, "i");
}

function parsePrizeTable(text: string): Record<string, number> {
  const prizes: Record<string, number> = {};

  for (let category = 1; category <= 13; category++) {
    const current = ordinalHeader(category).exec(text);
    if (!current || current.index == null) continue;

    const start = current.index + current[0].length;
    let end = Math.min(text.length, start + 360);

    if (category < 13) {
      const next = ordinalHeader(category + 1).exec(text.slice(start));
      if (next?.index != null) end = start + next.index;
    }

    const chunk = text.slice(start, end);
    const amount = chunk.match(/([0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2})/);
    if (!amount) continue;

    const value = euroToNumber(amount[1]);
    if (Number.isFinite(value) && value > 0) {
      prizes[String(category)] = value;
    }
  }

  return prizes;
}

function parseOfficial(text: string) {
  const draw = text.match(/Sorteio:\s*([0-9]{3}\/[0-9]{4})/i);
  const date = text.match(/Data\s+do\s+Sorteio\s*-\s*([0-9]{2})\/([0-9]{2})\/([0-9]{4})/i);

  let key: RegExpMatchArray | null = null;
  if (date?.index != null) {
    const start = date.index + date[0].length;
    key = text.slice(start, start + 700).match(
      /(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s*\+\s*(\d{1,2})\s+(\d{1,2})/,
    );
  }
  if (!key) {
    const keyStart = text.search(/\bChave\b/i);
    if (keyStart >= 0) {
      key = text.slice(keyStart, keyStart + 900).match(
        /(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s*\+\s*(\d{1,2})\s+(\d{1,2})/,
      );
    }
  }

  if (!draw || !date || !key) {
    throw new Error("Não foi possível interpretar o resultado oficial do Euromilhões.");
  }

  const drawDate = `${date[3]}-${date[2]}-${date[1]}`;
  const numbers = key.slice(1, 6).map(Number).sort((a, b) => a - b);
  const stars = key.slice(6, 8).map(Number).sort((a, b) => a - b);

  if (
    new Set(numbers).size !== 5 || numbers.some((value) => value < 1 || value > 50) ||
    new Set(stars).size !== 2 || stars.some((value) => value < 1 || value > 12)
  ) {
    throw new Error("A chave oficial recebida não é válida.");
  }

  return {
    drawNumber: draw[1],
    drawDate,
    numbers,
    stars,
    prizes: parsePrizeTable(text),
  };
}

type OfficialResult = ReturnType<typeof parseOfficial>;

function isBetterCandidate(candidate: OfficialResult, best: OfficialResult | null): boolean {
  if (best == null) return true;
  if (candidate.drawDate !== best.drawDate) return candidate.drawDate > best.drawDate;
  return Object.keys(candidate.prizes).length > Object.keys(best.prizes).length;
}

async function fetchOfficialResult(): Promise<OfficialResult> {
  const urls = [
    "https://www.jogossantacasa.pt/web/ResultsBoard/",
    "https://www.jogossantacasa.pt/web/SCCartazResult/",
    "https://www.jogossantacasa.pt/web/ResultsBoard/euromilhoes",
    "https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes",
  ];

  let best: OfficialResult | null = null;
  let lastError: unknown;

  for (const url of urls) {
    try {
      const response = await fetch(url, {
        headers: {
          "User-Agent": "BOB-Manager/1.0 (+official-results-import)",
          "Accept": "text/html,application/xhtml+xml",
          "Accept-Language": "pt-PT,pt;q=0.9,en;q=0.5",
        },
      });
      if (!response.ok) {
        lastError = new Error(`Portal oficial indisponível (${response.status}).`);
        continue;
      }

      const candidate = parseOfficial(cleanHtml(await response.text()));
      if (isBetterCandidate(candidate, best)) best = candidate;
    } catch (error) {
      lastError = error;
    }
  }

  if (best && Object.keys(best.prizes).length >= 10) return best;
  if (best) {
    throw new Error(
      "O resultado oficial foi encontrado, mas a tabela de prémios não pôde ser lida com segurança.",
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

    const parsed = await fetchOfficialResult();
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
