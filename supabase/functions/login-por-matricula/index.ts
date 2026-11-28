import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function saoPauloParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(date);
  return Object.fromEntries(parts.filter(p => p.type !== "literal").map(p => [p.type, p.value]));
}

function shiftAccess(shift, minutes) {
  // Libera até 15 minutos antes; encerra no horário final do turno.
  if (shift === "Manhã") return minutes >= 345 && minutes < 840;       // 05:45–14:00
  if (shift === "Tarde") return minutes >= 825 && minutes < 1320;      // 13:45–22:00
  if (shift === "Noite") return minutes >= 1305 || minutes < 360;      // 21:45–06:00
  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Método não permitido." }), { status: 405, headers: corsHeaders });
  }

  try {
    const { matricula, senha } = await req.json();
    if (!/^\d{1,20}$/.test(String(matricula || "")) ||
        typeof senha !== "string" || senha.length < 1 || senha.length > 256) {
      return new Response(JSON.stringify({ error: "Informe matrícula e senha válidas." }), { status: 400, headers: corsHeaders });
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")!);
    const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")!);
    const serviceKey = secretKeys["default"];
    const publishableKey = publishableKeys["default"];

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id, matricula, role")
      .eq("matricula", String(matricula))
      .maybeSingle();

    if (profileError || !profile) {
      return new Response(JSON.stringify({ error: "Matrícula ou senha incorreta." }), { status: 401, headers: corsHeaders });
    }

    const { data: authUser, error: userError } = await admin.auth.admin.getUserById(profile.id);
    if (userError || !authUser.user?.email) {
      return new Response(JSON.stringify({ error: "Conta de acesso não configurada." }), { status: 401, headers: corsHeaders });
    }

    const tokenResponse = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: publishableKey },
      body: JSON.stringify({ email: authUser.user.email, password: senha }),
    });
    const tokenBody = await tokenResponse.json();
    if (!tokenResponse.ok) {
      return new Response(JSON.stringify({ error: "Matrícula ou senha incorreta." }), { status: 401, headers: corsHeaders });
    }

    // Analistas mantêm acesso administrativo sem restrição de turno.
    if (profile.role === "abastecedor") {
      const { data: roster, error: rosterError } = await admin
        .from("colaboradores")
        .select("equipe, ativo")
        .eq("matricula", String(profile.matricula))
        .maybeSingle();

      if (rosterError || !roster || !roster.ativo) {
        return new Response(JSON.stringify({ error: "Colaborador sem equipe ativa. Procure o analista." }), { status: 403, headers: corsHeaders });
      }

      const now = saoPauloParts();
      const today = `${now.year}-${now.month}-${now.day}`;
      const minutes = Number(now.hour) * 60 + Number(now.minute);
      const { data: todayShift, error: todayError } = await admin.rpc("turno_da_equipe", {
        p_equipe: roster.equipe, p_data: today,
      });
      if (todayError) throw todayError;

      if (!shiftAccess(todayShift, minutes)) {
        return new Response(JSON.stringify({
          error: "Acesso liberado somente 15 minutos antes do início do seu turno e durante o horário da escala.",
          turno: todayShift || "Folga",
        }), { status: 403, headers: corsHeaders });
      }
    }

    return new Response(JSON.stringify(tokenBody), { status: 200, headers: corsHeaders });
  } catch (error) {
    console.error("Erro no login:", error);
    return new Response(JSON.stringify({ error: "Não foi possível concluir o login." }), { status: 500, headers: corsHeaders });
  }
});
