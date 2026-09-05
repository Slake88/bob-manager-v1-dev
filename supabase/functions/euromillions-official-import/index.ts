import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const categories: Array<[number, string]> = [
  [1, "5 Números + 2 Estrelas"],
  [2, "5 Números + 1 Estrela"],
  [3, "5 Números + 0 Estrelas"],
  [4, "4 Números + 2 Estrelas"],
  [5, "4 Números + 1 Estrela"],
  [6, "3 Números + 2 Estrelas"],
  [7, "4 Números + 0 Estrelas"],
  [8, "2 Números + 2 Estrelas"],
  [9, "3 Números + 1 Estrela"],
  [10, "3 Números + 0 Estrelas"],
  [11, "1 Número + 2 Estrelas"],
  [12, "2 Números + 1 Estrela"],
  [13, "2 Números + 0 Estrelas"],
];

function cleanHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&ordm;|&#186;/gi, "º")
    .replace(/&euro;|&#8364;/gi, "€")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function euroToNumber(raw: string): number {
  return Number(raw.replace(/\./g, "").replace(",", "."));
}

function parseOfficial(text: string) {
  const draw = text.match(/Sorteio:\s*([0-9]{3}\/[0-9]{4})\s*-\s*(?:terça-feira|sexta-feira)/i);
  const date = text.match(/Data do Sorteio\s*-\s*([0-9]{2})\/([0-9]{2})\/([0-9]{4})/i);
  const key = text.match(/Chave\s+Ordem de saída\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\+\s*(\d+)\s+(\d+)/i);
  if (!draw || !date || !key) {
    throw new Error("Não foi possível interpretar o resultado oficial do Euromilhões.");
  }

  const drawDate = `${date[3]}-${date[2]}-${date[1]}`;
  const numbers = key.slice(1, 6).map(Number).sort((a, b) => a - b);
  const stars = key.slice(6, 8).map(Number).sort((a, b) => a - b);
  const prizes: Record<string, number> = {};

  for (let i = 0; i < categories.length; i++) {
    const [category, label] = categories[i];
    const start = text.indexOf(label);
    if (start < 0) continue;
    const nextLabel = i + 1 < categories.length
      ? categories[i + 1][1]
      : "Os prémios atribuídos";
    const next = text.indexOf(nextLabel, start + label.length);
    const chunk = text.slice(
      start + label.length,
      next > start ? next : start + label.length + 220,
    );
    const amount = chunk.match(/€\s*([0-9.]+,[0-9]{2})/);
    if (amount) prizes[String(category)] = euroToNumber(amount[1]);
  }

  return { drawNumber: draw[1], drawDate, numbers, stars, prizes };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const auth = req.headers.get("Authorization");
    if (!auth) {
      return new Response(
        JSON.stringify({ error: "Autenticação necessária." }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
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
      return new Response(
        JSON.stringify({ error: "Parâmetros inválidos." }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { data: userData, error: userError } = await client.auth.getUser();
    if (userError || !userData.user) throw new Error("Sessão inválida.");

    const response = await fetch(
      "https://www.jogossantacasa.pt/web/SCCartazResult/",
      { headers: { "User-Agent": "BOB-Manager/1.0 (+official-results-import)" } },
    );
    if (!response.ok) {
      throw new Error(`Portal oficial indisponível (${response.status}).`);
    }

    const parsed = parseOfficial(cleanHtml(await response.text()));
    const parsedDate = new Date(`${parsed.drawDate}T12:00:00Z`);
    if (
      parsedDate.getUTCFullYear() !== year ||
      parsedDate.getUTCMonth() + 1 !== month
    ) {
      return new Response(
        JSON.stringify({
          imported: false,
          reason: "latest_outside_requested_month",
          latest: parsed,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { error } = await client.rpc(
      "process_euromillions_official_result_v1",
      {
        target_club: clubId,
        p_draw_date: parsed.drawDate,
        p_draw_number: parsed.drawNumber,
        p_numbers: parsed.numbers,
        p_stars: parsed.stars,
        p_prizes: parsed.prizes,
        p_source: "jogossantacasa.pt",
      },
    );
    if (error) throw error;

    return new Response(
      JSON.stringify({ imported: true, ...parsed }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
