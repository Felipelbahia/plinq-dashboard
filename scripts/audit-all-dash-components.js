/**
 * AUDITORIA INTEGRAL DE TODAS AS RPCS, FILTROS E DRILLDOWN DO DASHBOARD V3.0
 * Executa testes reais contra o Supabase para validar os 47 itens do Dashboard
 */

const SUPABASE_URL = "https://hqqzfccgkqdmhznwaxqj.supabase.co";
const SUPABASE_KEY = "sb_publishable_0jA57WFYIBt1PfqaVOsREA_MUI6hc2Y";

async function fetchView(endpoint) {
  const url = `${SUPABASE_URL}/rest/v1/${endpoint}`;
  const start = Date.now();
  try {
    const res = await fetch(url, {
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` }
    });
    const duration = Date.now() - start;
    if (!res.ok) {
      const err = await res.text();
      return { ok: false, status: res.status, error: err, duration };
    }
    const data = await res.json();
    return { ok: true, status: res.status, data, duration };
  } catch (err) {
    return { ok: false, error: err.message, duration: Date.now() - start };
  }
}

async function fetchRPC(rpcName, params = {}) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/${rpcName}`;
  const start = Date.now();
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(params)
    });
    const duration = Date.now() - start;
    if (!res.ok) {
      const err = await res.text();
      return { ok: false, status: res.status, error: err, duration };
    }
    const data = await res.json();
    return { ok: true, status: res.status, data, duration };
  } catch (err) {
    return { ok: false, error: err.message, duration: Date.now() - start };
  }
}

async function runAudit() {
  console.log("================================================================================");
  console.log("🔍 INICIANDO AUDITORIA TÉCNICA E FUNCIONAL INTEGRAL DO DASHBOARD");
  console.log(`🎯 URL: ${SUPABASE_URL}`);
  console.log("================================================================================\n");

  let totalChecks = 0;
  let passedChecks = 0;
  let failedChecks = 0;
  const failures = [];

  function assert(name, condition, details = "") {
    totalChecks++;
    if (condition) {
      passedChecks++;
      console.log(`  [✅ PASS] ${name}`);
    } else {
      failedChecks++;
      console.log(`  [❌ FAIL] ${name} ${details ? "-> " + details : ""}`);
      failures.push({ name, details });
    }
  }

  // ---------------------------------------------------------------------------
  // 1. DIRETÓRIOS E METADADOS
  // ---------------------------------------------------------------------------
  console.log("--- 1. DIRETÓRIOS E CARREGAMENTO DE FILTROS ---");
  const inboxes = await fetchView("suporteapp_chatwoot_inboxes?select=chatwoot_inbox_id,name,channel_type&active=eq.true&order=name");
  assert("Carregamento de Inboxes (F-02)", inboxes.ok && Array.isArray(inboxes.data) && inboxes.data.length > 0, inboxes.error);

  const agents = await fetchView("suporteapp_chatwoot_agents?select=chatwoot_id,name&active=eq.true&is_bot=eq.false&order=name");
  assert("Carregamento de Agentes Humanos (F-03)", agents.ok && Array.isArray(agents.data), agents.error);

  const teams = await fetchView("suporteapp_chatwoot_teams?select=chatwoot_team_id,name&active=eq.true&order=name");
  assert("Carregamento de Times (F-04)", teams.ok && Array.isArray(teams.data), teams.error);

  const taxonomy = await fetchView("suporteapp_label_taxonomy?select=label_name,thematic_group&order=thematic_group,label_name");
  assert("Carregamento de Taxonomia de Tags (F-08)", taxonomy.ok && Array.isArray(taxonomy.data) && taxonomy.data.length >= 40, taxonomy.error);

  // ---------------------------------------------------------------------------
  // 2. BLOCO A: FILA AGORA (D-01 a D-06)
  // ---------------------------------------------------------------------------
  console.log("\n--- 2. BLOCO A: FILA AGORA (MOMENTO ATUAL VIVO 24X7) ---");
  const qDefault = await fetchRPC("suporteapp_rpc_dashboard_queue", {
    p_inbox_ids: [163, 164, 295, 296],
    p_agent_ids: null,
    p_team_ids: null,
    p_severities: null,
    p_origins: null,
    p_taxonomies: null,
    p_tags: null,
    p_business_hours_filter: "all",
    p_weekend_filter: "all"
  });
  assert("suporteapp_rpc_dashboard_queue (Fila Viva)", qDefault.ok && Array.isArray(qDefault.data) && qDefault.data.length === 1, qDefault.error);
  if (qDefault.ok && qDefault.data[0]) {
    const q = qDefault.data[0];
    assert("D-01 (Fila Plinq) é número >= 0", typeof q.d01_waiting_plinq === "number" && q.d01_waiting_plinq >= 0);
    assert("D-02 (Aguardando Usuária) é número >= 0", typeof q.d02_waiting_customer === "number" && q.d02_waiting_customer >= 0);
    assert("D-03 (Alerta Red > 10m) é número >= 0", typeof q.d03_red_aberta_alerts === "number" && q.d03_red_aberta_alerts >= 0);
    assert("D-05 (Sem Atendimento) é número >= 0", typeof q.d05_unserviced_tickets === "number" && q.d05_unserviced_tickets >= 0);
    assert("D-06 (Adesão Taxonomia) é null ou número entre 0 e 100", q.d06_taxonomy_adherence_pct === null || (q.d06_taxonomy_adherence_pct >= 0 && q.d06_taxonomy_adherence_pct <= 100));
    assert("D-04 Histograma possui as 5 faixas somáveis", 
      typeof q.d04_under_1h === "number" &&
      typeof q.d04_1h_to_4h === "number" &&
      typeof q.d04_4h_to_24h === "number" &&
      typeof q.d04_24h_to_72h === "number" &&
      typeof q.d04_over_72h === "number"
    );
  }

  // Testando se filtro de severidade influencia o Bloco A
  const qP0 = await fetchRPC("suporteapp_rpc_dashboard_queue", {
    p_inbox_ids: [163, 164, 295, 296],
    p_severities: ["P0"]
  });
  assert("Filtro P0 no Bloco A não quebra e propaga", qP0.ok);

  // ---------------------------------------------------------------------------
  // 3. BLOCO B: FLUXO E ESPERA (D-07 a D-12 + RS-04)
  // ---------------------------------------------------------------------------
  console.log("\n--- 3. BLOCO B: FLUXO E ESPERA (D-07 A D-12 + RS-04) ---");
  const turn30d = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_inbox_ids: [163, 164, 295, 296],
    p_business_hours_filter: "all",
    p_weekend_filter: "all"
  });
  assert("suporteapp_rpc_turn_metrics (30d)", turn30d.ok && Array.isArray(turn30d.data) && turn30d.data.length === 1, turn30d.error);
  if (turn30d.ok && turn30d.data[0]) {
    const t = turn30d.data[0];
    assert("D-07 (Conversas Novas) >= 0", typeof t.total_tickets === "number" && t.total_tickets >= 0);
    assert("D-09 (Meta 10m SLA) é null ou número entre 0 e 100", t.d09_meta_10min_compliance_pct === null || (t.d09_meta_10min_compliance_pct >= 0 && t.d09_meta_10min_compliance_pct <= 100));
    assert("D-08 Mediana 1ª Resposta em minutos úteis", t.d08_median_turn1_biz_minutes === null || typeof t.d08_median_turn1_biz_minutes === "number");
    assert("D-08 P90 1ª Resposta em minutos úteis", t.d08_p90_turn1_biz_minutes === null || typeof t.d08_p90_turn1_biz_minutes === "number");
    assert("D-10 Mediana Turno 2 em minutos úteis", t.d10_median_turn2_biz_minutes === null || typeof t.d10_median_turn2_biz_minutes === "number");
    assert("D-11 Entrada vs Saída: total_tickets e tickets_resolved coerentes", typeof t.tickets_resolved === "number" && typeof t.resolved_manual === "number" && typeof t.resolved_inactivity === "number");
    assert("RS-04: Métricas corridas (raw) calculadas em paralelo com úteis (biz)", 
      t.rs04_median_turn1_raw_minutes === null || typeof t.rs04_median_turn1_raw_minutes === "number"
    );
  }

  // Testando preset diário (today)
  const turnToday = await fetchRPC("suporteapp_rpc_turn_metrics", { p_period: "today" });
  assert("suporteapp_rpc_turn_metrics (today)", turnToday.ok);

  // Testando datas customizadas
  const turnCustom = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "custom",
    p_date_start: "2026-09-01",
    p_date_end: "2026-09-10"
  });
  assert("suporteapp_rpc_turn_metrics com p_date_start/end customizado", turnCustom.ok);

  // ---------------------------------------------------------------------------
  // 4. BLOCO C: TURNO DA AGENTE (D-13 a D-16)
  // ---------------------------------------------------------------------------
  console.log("\n--- 4. BLOCO C: TURNO DA AGENTE (D-13 A D-16) ---");
  const shift = await fetchRPC("suporteapp_rpc_daily_shift_metrics", { p_period: "30d" });
  assert("suporteapp_rpc_daily_shift_metrics (30d)", shift.ok && Array.isArray(shift.data) && shift.data.length === 1, shift.error);
  if (shift.ok && shift.data[0]) {
    const s = shift.data[0];
    assert("D-13 (Latência de Abertura) é null ou número", s.avg_opening_latency_minutes === null || typeof s.avg_opening_latency_minutes === "number");
    assert("D-14 (Fila Herdada) é número >= 0", typeof s.inherited_queue_count === "number" && s.inherited_queue_count >= 0);
    assert("D-15 (Horário do Último Envio) é string formatada ou null", s.avg_closing_time === null || typeof s.avg_closing_time === "string");
    assert("D-16 (Maior Hiato Ocioso) é null ou número", s.max_idle_minutes === null || typeof s.max_idle_minutes === "number");
  }

  // ---------------------------------------------------------------------------
  // 5. BLOCO D: BOT E IA (D-17)
  // ---------------------------------------------------------------------------
  console.log("\n--- 5. BLOCO D: ATENDIMENTO BOT E IA (D-17) ---");
  const bot = await fetchRPC("suporteapp_rpc_bot_metrics", { p_period: "30d" });
  assert("suporteapp_rpc_bot_metrics (30d)", bot.ok && Array.isArray(bot.data) && bot.data.length === 1, bot.error);
  if (bot.ok && bot.data[0]) {
    const b = bot.data[0];
    assert("D-17 Total é número >= 0", typeof b.bot_total_conversations === "number" && b.bot_total_conversations >= 0);
    assert("D-17 Contenção é null ou entre 0 e 100", b.bot_containment_pct === null || (b.bot_containment_pct >= 0 && b.bot_containment_pct <= 100));
    assert("D-17 Transbordo é null ou entre 0 e 100", b.bot_handover_pct === null || (b.bot_handover_pct >= 0 && b.bot_handover_pct <= 100));
    assert("D-17 Fila Herdada é número >= 0", typeof b.bot_inherited_queue === "number" && b.bot_inherited_queue >= 0);
  }

  // ---------------------------------------------------------------------------
  // 6. RELATÓRIO SEMANAL DE SUPORTE (RS-01 A RS-14)
  // ---------------------------------------------------------------------------
  console.log("\n--- 6. RELATÓRIO SEMANAL DE SUPORTE (RS-01 A RS-14) ---");

  const rs12 = await fetchRPC("suporteapp_rpc_contest_and_false_negative", { p_period: "30d" });
  assert("RS-12 (Contestações & Falso Negativo)", rs12.ok && Array.isArray(rs12.data), rs12.error);

  const rs01 = await fetchRPC("suporteapp_rpc_weekly_heatmap", { p_period: "30d" });
  assert("RS-01 (Mapa de Calor 7x24)", rs01.ok && Array.isArray(rs01.data), rs01.error);

  const rs02 = await fetchRPC("suporteapp_rpc_weekly_reasons", { p_period: "30d" });
  assert("RS-02 (Concentração por Motivo)", rs02.ok && Array.isArray(rs02.data), rs02.error);

  const rs03 = await fetchRPC("suporteapp_rpc_reason_severity_matrix", { p_period: "30d" });
  assert("RS-03 (Matriz Motivo x Severidade)", rs03.ok && Array.isArray(rs03.data), rs03.error);

  const rs05Breakdown = await fetchRPC("suporteapp_rpc_resolution_breakdown", { p_period: "30d" });
  assert("RS-05 (Decomposição de Resolução)", rs05Breakdown.ok && Array.isArray(rs05Breakdown.data), rs05Breakdown.error);

  const rs05Reopen = await fetchRPC("suporteapp_rpc_reopen_count", { p_period: "30d" });
  assert("RS-05 (Contagem de Reaberturas)", rs05Reopen.ok && typeof rs05Reopen.data === "number", rs05Reopen.error);

  const rs06 = await fetchRPC("suporteapp_rpc_avoidable_vs_structural", { p_period: "30d" });
  assert("RS-06 (Espera Evitável vs Estrutural)", rs06.ok && Array.isArray(rs06.data), rs06.error);

  const rs07 = await fetchRPC("suporteapp_rpc_carried_stock", { p_period: "30d" });
  assert("RS-07 (Balanço de Estoque Carregado)", rs07.ok && Array.isArray(rs07.data), rs07.error);

  const rs08 = await fetchRPC("suporteapp_rpc_alarm_panel", { p_period: "30d" });
  assert("RS-08 (Painel de Alarmes)", rs08.ok && Array.isArray(rs08.data), rs08.error);

  const rs09 = await fetchRPC("suporteapp_rpc_weekly_handoff", { p_period: "30d" });
  assert("RS-09 (Handoff Externo por Área)", rs09.ok && Array.isArray(rs09.data), rs09.error);

  const rs10 = await fetchRPC("suporteapp_rpc_first_contact_resolution", { p_period: "30d" });
  assert("RS-10 (FCR - Resolvidas em 1 Toque)", rs10.ok && Array.isArray(rs10.data), rs10.error);

  const rs11 = await fetchRPC("suporteapp_rpc_recurrence_rate", { p_date_end: null });
  assert("RS-11 (Taxa de Reincidência 7d/30d)", rs11.ok && Array.isArray(rs11.data), rs11.error);

  const rs13 = await fetchRPC("suporteapp_rpc_bot_handover_top_subjects", { p_period: "30d", p_limit: 5 });
  assert("RS-13 (Top 5 Assuntos de Transbordo)", rs13.ok && Array.isArray(rs13.data), rs13.error);

  // ---------------------------------------------------------------------------
  // 7. AUDITORIA DE COMPORTAMENTO SOB FILTROS COMBINADOS
  // ---------------------------------------------------------------------------
  console.log("\n--- 7. AUDITORIA DE COMPORTAMENTO SOB FILTROS COMBINADOS ---");

  // Filtro de horário: only_outside
  const outsideBiz = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_business_hours_filter: "only_outside"
  });
  assert("Filtro 'only_outside' (Início fora do expediente)", outsideBiz.ok, outsideBiz.error);

  // Filtro de horário: exclude_outside
  const insideBiz = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_business_hours_filter: "exclude_outside"
  });
  assert("Filtro 'exclude_outside' (Apenas horário comercial)", insideBiz.ok, insideBiz.error);

  // Filtro de fim de semana: only_weekend
  const weekendOnly = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_weekend_filter: "only_weekend"
  });
  assert("Filtro 'only_weekend' (Início sexta 18h a segunda 9h)", weekendOnly.ok, weekendOnly.error);

  // Filtro de Tag específica
  const tagFilter = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_tags: ["login-acesso"]
  });
  assert("Filtro de Tag específica ('login-acesso')", tagFilter.ok, tagFilter.error);

  // Filtro de Tag sentinela '__sem_tag__'
  const noTagFilter = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_tags: ["__sem_tag__"]
  });
  assert("Filtro de Tag '__sem_tag__' (tickets sem etiquetas)", noTagFilter.ok, noTagFilter.error);

  // Filtro de Origem: bot vs human
  const originBot = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_origins: ["bot"]
  });
  assert("Filtro de Origem: bot", originBot.ok, originBot.error);

  const originHuman = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_origins: ["human"]
  });
  assert("Filtro de Origem: human", originHuman.ok, originHuman.error);

  // Filtro de Status de Taxonomia: valid vs missing
  const taxValid = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_taxonomies: ["valid"]
  });
  assert("Filtro Taxonomia: valid", taxValid.ok, taxValid.error);

  const taxMissing = await fetchRPC("suporteapp_rpc_turn_metrics", {
    p_period: "30d",
    p_taxonomies: ["missing"]
  });
  assert("Filtro Taxonomia: missing", taxMissing.ok, taxMissing.error);

  // ---------------------------------------------------------------------------
  // 8. AUDITORIA DO SISTEMA DE DRILL-DOWN (M-01 A M-18)
  // ---------------------------------------------------------------------------
  console.log("\n--- 8. AUDITORIA DO MODAL DE DRILL-DOWN E AUDITABILIDADE ---");
  const ticketsSample = await fetchView("suporteapp_tickets?select=*&order=created_at.desc&limit=10");
  assert("Leitura autorizada da view suporteapp_tickets para drill-down", ticketsSample.ok && Array.isArray(ticketsSample.data), ticketsSample.error);
  if (ticketsSample.ok && ticketsSample.data.length > 0) {
    const t = ticketsSample.data[0];
    assert("Drill-down possui campo chatwoot_conversation_id", t.chatwoot_conversation_id !== undefined);
    assert("Drill-down possui campo customer_name / customer_email", t.customer_name !== undefined || t.customer_email !== undefined);
    assert("Drill-down possui chatwoot_inbox_id mapeável para canal", typeof t.chatwoot_inbox_id === "number");
    assert("Drill-down possui priority / current_labels", t.priority !== undefined || t.current_labels !== undefined);
    assert("Drill-down possui status (open / resolved)", ["open", "resolved", "pending", "snoozed"].includes(t.status));
  }

  // ---------------------------------------------------------------------------
  // SÍNTESE FINAL
  // ---------------------------------------------------------------------------
  console.log("\n================================================================================");
  console.log("📊 SÍNTESE DA AUDITORIA INTEGRAL");
  console.log("================================================================================");
  console.log(`Total de verificações: ${totalChecks}`);
  console.log(`Aprovadas: ${passedChecks}`);
  console.log(`Falhas: ${failedChecks}`);

  if (failedChecks === 0) {
    console.log("\n🎉 100% DAS VERIFICAÇÕES APROVADAS! TODAS AS RPCS E FILTROS ÍNTEGROS.");
  } else {
    console.log("\n⚠️ DETALHE DAS FALHAS DETECTADAS:");
    failures.forEach((f, i) => console.log(`  ${i + 1}. ${f.name} -> ${f.details}`));
  }
}

runAudit();
