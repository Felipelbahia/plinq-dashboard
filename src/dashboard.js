/**
 * PLINQ CHAMADOS APP · DASHBOARD DE SUPORTE V3.0
 * Lógica Completa Frontend, Barramento de Filtros Globais, D-11 Detalhado e RS-01 a RS-14
 *
 * Reescrito em 2026-08-27 (ver acompanhamento-de-projeto/) para corrigir: filtros globais
 * que não filtravam nada, RPCs inexistentes/incompletas, fallback de dado fabricado,
 * mapeamento de canal errado (chatwoot_inbox_id === 88, que é o account_id) e blocos RS
 * estáticos nunca atualizados. Nenhum número aqui é inventado: quando uma RPC falha, a UI
 * mostra erro explícito; quando o período não tem dado, mostra "sem dado", nunca um valor
 * fabricado.
 *
 * Reescrito em 2026-09-11 para: (1) converter todos os filtros de dropdown único para
 * multi-seleção por checkbox; (2) adicionar filtro de Tag (com opção "Sem Tag"); (3) adicionar
 * filtros de início fora do expediente e início no fim de semana (3 posições: todas/só
 * essas/excluir essas). Contrato novo documentado em
 * supabase/migrations/20260911_multiselect_filters_tags_business_hours_weekend.sql.
 */

const SUPABASE_URL = (typeof window !== 'undefined' && window.APP_CONFIG && window.APP_CONFIG.SUPABASE_URL) || "";
const SUPABASE_KEY = (typeof window !== 'undefined' && window.APP_CONFIG && window.APP_CONFIG.SUPABASE_KEY) || "";

// Caixas de entrada marcadas por padrão (WhatsApp, Site, Facebook e Instagram).
// Demais (Gov, Marketing e canais técnicos de API do Chamados APP) começam desmarcadas.
const DEFAULT_INBOX_IDS = [163, 164, 295, 296]; // 163: WhatsApp, 164: Site, 295: Facebook - Plinq, 296: deumplinq

let currentFilters = {
  period: '30d',
  activePreset: '30d',
  dateStart: null, // 'YYYY-MM-DD', quando em intervalo explícito ou personalizado
  dateEnd: null    // 'YYYY-MM-DD', quando em intervalo explícito ou personalizado
};

const periodLabels = {
  'today': 'Hoje',
  'yesterday': 'Ontem',
  'this_week': 'Esta Semana',
  'last_week': 'Semana Passada',
  '7d': 'Últimos 7 Dias',
  '30d': 'Últimos 30 Dias',
  'this_month': 'Este Mês',
  'last_month': 'Mês Anterior',
  'custom': 'Personalizado'
};

const weekdayLabels = { 1: 'Segunda', 2: 'Terça', 3: 'Quarta', 4: 'Quinta', 5: 'Sexta', 6: 'Sábado', 7: 'Domingo' };
const heatmapBuckets = ['00h-04h', '04h-08h', '09h-12h', '12h-15h', '15h-18h', '18h-21h', '21h-24h'];

// =============================================================================
// 1. MULTI-SELECT DE CHECKBOX — motor genérico reusado pelos 7 filtros multi-seleção
// (Canal, Agente, Time, Severidade, Origem, Taxonomia, Tag)
// =============================================================================
// msState[key] = { type: 'int'|'text', items: [{value, label}], selected: Set<string>, allLabel: string }
const msState = {};

function msInit(key, items, opts = {}) {
  const type = opts.type || 'text';
  const allLabel = opts.allLabel || 'Todas';
  const defaultSelected = opts.defaultSelected || items.map(i => String(i.value));
  msState[key] = {
    type,
    items,
    selected: new Set(defaultSelected.map(String)),
    allLabel
  };
  msRenderOptions(key);
  msRenderLabel(key);
}

function msRenderOptions(key, filterText = '') {
  const container = document.getElementById(`ms-options-${key}`);
  if (!container) return;
  const state = msState[key];
  const needle = filterText.trim().toLowerCase();
  const visibleItems = needle ? state.items.filter(i => i.label.toLowerCase().includes(needle)) : state.items;
  if (visibleItems.length === 0) {
    container.innerHTML = `<div class="multiselect-empty">Nenhuma opção encontrada.</div>`;
    return;
  }
  container.innerHTML = visibleItems.map(item => {
    const value = String(item.value);
    const checked = state.selected.has(value) ? 'checked' : '';
    return `
      <label class="multiselect-option">
        <input type="checkbox" ${checked} onchange="msToggleOption('${key}', '${escapeHtml(value)}')">
        <span>${escapeHtml(item.label)}</span>
      </label>
    `;
  }).join('');
}

function msFilterSearch(key, text) {
  msRenderOptions(key, text);
}

function msRenderLabel(key) {
  const labelEl = document.getElementById(`ms-${key}-label`);
  if (!labelEl) return;
  const state = msState[key];
  const total = state.items.length;
  const n = state.selected.size;
  if (n === 0) labelEl.innerText = 'Nenhum selecionado';
  else if (n === total) labelEl.innerText = state.allLabel;
  else labelEl.innerText = `${n} selecionado${n > 1 ? 's' : ''}`;
}

function msToggleOption(key, value) {
  const state = msState[key];
  if (state.selected.has(value)) state.selected.delete(value);
  else state.selected.add(value);
  msRenderLabel(key);
  handleFilterChange();
}

function msSelectAll(key) {
  const state = msState[key];
  state.items.forEach(i => state.selected.add(String(i.value)));
  msRenderOptions(key);
  msRenderLabel(key);
  handleFilterChange();
}

function msSelectNone(key) {
  const state = msState[key];
  state.selected.clear();
  msRenderOptions(key);
  msRenderLabel(key);
  handleFilterChange();
}

function msToggle(key) {
  const panel = document.getElementById(`ms-panel-${key}`);
  const isOpen = !panel.hidden;
  msCloseAllPanels();
  if (!isOpen) {
    panel.hidden = false;
    document.getElementById(`ms-group-${key}`).classList.add('open');
  }
}

function msCloseAllPanels() {
  document.querySelectorAll('.multiselect-panel').forEach(p => p.hidden = true);
  document.querySelectorAll('.multiselect.open').forEach(g => g.classList.remove('open'));
}

document.addEventListener('click', (evt) => {
  if (!evt.target.closest('.multiselect')) msCloseAllPanels();
  if (!evt.target.closest('#date-picker-group')) closeDatePicker();
});

document.addEventListener('keydown', (evt) => {
  if (evt.key === 'Escape') {
    msCloseAllPanels();
    closeDatePicker();
  }
});

// NULL = sem restrição (todas as opções estão marcadas, equivalente a não filtrar);
// array (mesmo vazio) = restringe às opções marcadas.
function msGetParam(key) {
  const state = msState[key];
  if (!state) return null;
  if (state.selected.size === state.items.length) return null;
  const values = Array.from(state.selected);
  return state.type === 'int' ? values.map(v => parseInt(v, 10)) : values;
}

function msLabelFor(key, value) {
  const state = msState[key];
  if (!state) return String(value);
  const item = state.items.find(i => String(i.value) === String(value));
  return item ? item.label : String(value);
}

// =============================================================================
// 2. GERENCIAMENTO DE FILTROS GLOBAIS & SELETOR DE PERÍODO COM PRESETS (FUSO BRT)
// =============================================================================

function getBrtTodayDate() {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  });
  const isoDate = formatter.format(new Date());
  const [y, m, d] = isoDate.split('-').map(Number);
  return new Date(y, m - 1, d, 12, 0, 0);
}

function toIsoDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function formatDateBR(isoStr) {
  if (!isoStr) return '';
  const [y, m, d] = isoStr.split('-');
  return `${d}/${m}/${y}`;
}

function formatDateBRShort(isoStr) {
  if (!isoStr) return '';
  const [y, m, d] = isoStr.split('-');
  return `${d}/${m}`;
}

function toggleDatePicker(evt) {
  if (evt) evt.stopPropagation();
  msCloseAllPanels();
  const group = document.getElementById('date-picker-group');
  const panel = document.getElementById('date-picker-panel');
  if (!group || !panel) return;
  const isOpen = group.classList.contains('open');
  if (isOpen) {
    closeDatePicker();
  } else {
    group.classList.add('open');
    panel.hidden = false;
  }
}

function closeDatePicker() {
  const group = document.getElementById('date-picker-group');
  const panel = document.getElementById('date-picker-panel');
  if (group) group.classList.remove('open');
  if (panel) panel.hidden = true;
}

function updatePeriodBadges(label) {
  const text = `Período: ${label}`;
  ['period-badge-b', 'period-badge-c', 'period-badge-d', 'period-badge-p3'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.innerText = text;
  });
}

function selectPreset(presetKey) {
  const today = getBrtTodayDate();
  const todayStr = toIsoDate(today);

  let triggerText = 'Hoje';
  let badgeText = `Hoje (${formatDateBR(todayStr)})`;
  let start = null;
  let end = null;
  let rpcPeriod = 'today';

  switch (presetKey) {
    case 'today':
      rpcPeriod = 'today';
      triggerText = `Hoje (${formatDateBRShort(todayStr)})`;
      badgeText = `Hoje (${formatDateBR(todayStr)})`;
      start = null;
      end = null;
      break;

    case 'yesterday': {
      const yesterday = new Date(today);
      yesterday.setDate(today.getDate() - 1);
      const yStr = toIsoDate(yesterday);
      rpcPeriod = 'custom';
      start = yStr;
      end = yStr;
      triggerText = `Ontem (${formatDateBRShort(yStr)})`;
      badgeText = `Ontem (${formatDateBR(yStr)})`;
      break;
    }

    case 'this_week': {
      const dayOfWeek = today.getDay();
      const diffToMonday = (dayOfWeek === 0 ? 6 : dayOfWeek - 1);
      const monday = new Date(today);
      monday.setDate(today.getDate() - diffToMonday);
      const monStr = toIsoDate(monday);
      rpcPeriod = 'custom';
      start = monStr;
      end = todayStr;
      triggerText = `Esta Semana (${formatDateBRShort(monStr)} a ${formatDateBRShort(todayStr)})`;
      badgeText = `${formatDateBR(monStr)} a ${formatDateBR(todayStr)}`;
      break;
    }

    case 'last_week': {
      const dayOfWeek = today.getDay();
      const diffToMonday = (dayOfWeek === 0 ? 6 : dayOfWeek - 1);
      const monday = new Date(today);
      monday.setDate(today.getDate() - diffToMonday);
      const lastMonday = new Date(monday);
      lastMonday.setDate(monday.getDate() - 7);
      const lastSunday = new Date(monday);
      lastSunday.setDate(monday.getDate() - 1);
      const lmStr = toIsoDate(lastMonday);
      const lsStr = toIsoDate(lastSunday);
      rpcPeriod = 'custom';
      start = lmStr;
      end = lsStr;
      triggerText = `Semana Passada (${formatDateBRShort(lmStr)} a ${formatDateBRShort(lsStr)})`;
      badgeText = `${formatDateBR(lmStr)} a ${formatDateBR(lsStr)}`;
      break;
    }

    case '7d': {
      const d7 = new Date(today);
      d7.setDate(today.getDate() - 7);
      const d7Str = toIsoDate(d7);
      rpcPeriod = '7d';
      triggerText = `Últimos 7 Dias (${formatDateBRShort(d7Str)} a ${formatDateBRShort(todayStr)})`;
      badgeText = `Últimos 7 Dias (${formatDateBR(d7Str)} a ${formatDateBR(todayStr)})`;
      start = null;
      end = null;
      break;
    }

    case '30d': {
      const d30 = new Date(today);
      d30.setDate(today.getDate() - 30);
      const d30Str = toIsoDate(d30);
      rpcPeriod = '30d';
      triggerText = `Últimos 30 Dias (${formatDateBRShort(d30Str)} a ${formatDateBRShort(todayStr)})`;
      badgeText = `Últimos 30 Dias (${formatDateBR(d30Str)} a ${formatDateBR(todayStr)})`;
      start = null;
      end = null;
      break;
    }

    case 'this_month': {
      const firstDay = new Date(today.getFullYear(), today.getMonth(), 1, 12, 0, 0);
      const fStr = toIsoDate(firstDay);
      rpcPeriod = 'custom';
      start = fStr;
      end = todayStr;
      triggerText = `Este Mês (${formatDateBRShort(fStr)} a ${formatDateBRShort(todayStr)})`;
      badgeText = `Este Mês (${formatDateBR(fStr)} a ${formatDateBR(todayStr)})`;
      break;
    }

    case 'last_month': {
      const firstDayLastMonth = new Date(today.getFullYear(), today.getMonth() - 1, 1, 12, 0, 0);
      const lastDayLastMonth = new Date(today.getFullYear(), today.getMonth(), 0, 12, 0, 0);
      const fStr = toIsoDate(firstDayLastMonth);
      const lStr = toIsoDate(lastDayLastMonth);
      rpcPeriod = 'custom';
      start = fStr;
      end = lStr;
      triggerText = `Mês Anterior (${formatDateBRShort(fStr)} a ${formatDateBRShort(lStr)})`;
      badgeText = `Mês Anterior (${formatDateBR(fStr)} a ${formatDateBR(lStr)})`;
      break;
    }

    default:
      rpcPeriod = 'today';
      triggerText = `Hoje (${formatDateBRShort(todayStr)})`;
      badgeText = `Hoje (${formatDateBR(todayStr)})`;
  }

  currentFilters.period = rpcPeriod;
  currentFilters.activePreset = presetKey;
  currentFilters.dateStart = start;
  currentFilters.dateEnd = end;

  // Atualiza botões de preset
  document.querySelectorAll('.date-preset-chip').forEach(btn => {
    btn.classList.toggle('active', btn.getAttribute('data-preset') === presetKey);
  });

  // Atualiza label do trigger
  const labelEl = document.getElementById('date-picker-label');
  if (labelEl) labelEl.innerText = triggerText;

  // Atualiza inputs customizados com os valores atuais para comodidade
  if (start && end) {
    const inStart = document.getElementById('filter-date-start');
    const inEnd = document.getElementById('filter-date-end');
    if (inStart) inStart.value = start;
    if (inEnd) inEnd.value = end;
  }

  const errEl = document.getElementById('date-custom-error');
  if (errEl) errEl.style.display = 'none';

  updatePeriodBadges(badgeText);
  closeDatePicker();
  updateDashboard();
}

function validateCustomDateInputs() {
  const inStart = document.getElementById('filter-date-start');
  const inEnd = document.getElementById('filter-date-end');
  const errEl = document.getElementById('date-custom-error');
  if (!inStart || !inEnd || !errEl) return;

  const startVal = inStart.value;
  const endVal = inEnd.value;

  if (startVal && endVal && startVal > endVal) {
    errEl.innerText = "Data inicial não pode ser posterior à final.";
    errEl.style.display = 'block';
    return false;
  }
  errEl.style.display = 'none';
  return true;
}

function applyCustomDateRange() {
  const inStart = document.getElementById('filter-date-start');
  const inEnd = document.getElementById('filter-date-end');
  const errEl = document.getElementById('date-custom-error');
  if (!inStart || !inEnd || !errEl) return;

  const startVal = inStart.value;
  const endVal = inEnd.value;

  if (!startVal || !endVal) {
    errEl.innerText = "Por favor, selecione ambas as datas (De e Até).";
    errEl.style.display = 'block';
    return;
  }

  if (startVal > endVal) {
    errEl.innerText = "Data inicial não pode ser posterior à final.";
    errEl.style.display = 'block';
    return;
  }

  errEl.style.display = 'none';

  currentFilters.period = 'custom';
  currentFilters.activePreset = 'custom';
  currentFilters.dateStart = startVal;
  currentFilters.dateEnd = endVal;

  // Remove active de todos os presets
  document.querySelectorAll('.date-preset-chip').forEach(btn => btn.classList.remove('active'));

  const triggerText = `Personalizado (${formatDateBRShort(startVal)} a ${formatDateBRShort(endVal)})`;
  const badgeText = `${formatDateBR(startVal)} a ${formatDateBR(endVal)}`;

  const labelEl = document.getElementById('date-picker-label');
  if (labelEl) labelEl.innerText = triggerText;

  updatePeriodBadges(badgeText);
  closeDatePicker();
  updateDashboard();
}

function handleFilterChange() {
  // Chamado por outros filtros na barra (ex: Horário comercial e Fins de semana)
  updateDashboard();
}

// =============================================================================
// 3. REQUISIÇÃO REST / RPC AO SUPABASE — nunca engole erro em silêncio
// =============================================================================
async function fetchView(pathAndQuery) {
  if (!SUPABASE_URL || !SUPABASE_KEY) {
    return { ok: false, error: "Credenciais do Supabase ausentes. Configure SUPABASE_URL e SUPABASE_ANON_KEY no .env ou na Vercel." };
  }
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, {
      headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }
    });
    if (!response.ok) {
      const body = await response.text();
      return { ok: false, error: `HTTP ${response.status}: ${body.slice(0, 200)}` };
    }
    return { ok: true, data: await response.json() };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function fetchRPC(rpcName, params = {}) {
  if (!SUPABASE_URL || !SUPABASE_KEY) {
    return { ok: false, error: "Credenciais do Supabase ausentes. Configure SUPABASE_URL e SUPABASE_ANON_KEY no .env ou na Vercel." };
  }
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${rpcName}`, {
      method: 'POST',
      headers: {
        'apikey': SUPABASE_KEY,
        'Authorization': `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(params)
    });
    if (!response.ok) {
      const body = await response.text();
      return { ok: false, error: `HTTP ${response.status}: ${body.slice(0, 200)}` };
    }
    return { ok: true, data: await response.json() };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

// Params de filtro comuns — todas as 17 RPCs aceitam exatamente este contrato desde
// supabase/migrations/20260911_multiselect_filters_tags_business_hours_weekend.sql.
function filterParams(extra = {}) {
  return {
    p_inbox_ids: msGetParam('channel'),
    p_agent_ids: msGetParam('agent'),
    p_team_ids: msGetParam('team'),
    p_severities: msGetParam('severity'),
    p_origins: msGetParam('origin'),
    p_taxonomies: msGetParam('taxonomy'),
    p_tags: msGetParam('tag'),
    p_business_hours_filter: document.getElementById('filter-business-hours').value,
    p_weekend_filter: document.getElementById('filter-weekend').value,
    ...extra
  };
}

// Params de data customizada — preenchidos quando period === 'custom' ou quando um preset calcula datas específicas;
// caso contrário (today, 7d, 30d nativos) a RPC resolve pelo p_period.
function dateRangeParams() {
  const hasCustomDates = currentFilters.period === 'custom' || (currentFilters.dateStart && currentFilters.dateEnd);
  return {
    p_date_start: hasCustomDates ? currentFilters.dateStart : null,
    p_date_end: hasCustomDates ? currentFilters.dateEnd : null
  };
}

// Período efetivo para RPCs que remapeiam 'today' -> '7d' (RS-* sem granularidade diária) —
// preserva 'custom' e '7d'/'30d' como estão.
function rsPeriod() {
  return currentFilters.period === 'today' ? '7d' : currentFilters.period;
}

function escapeHtml(unsafe) {
  if (unsafe === null || unsafe === undefined) return '';
  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function fmtPct(v) { return (v === null || v === undefined) ? 'sem dado' : `${v}%`; }
function fmtMin(v) { return (v === null || v === undefined) ? 'sem dado' : `${Math.round(v)} min`; }
// null = motivo não existia no período anterior (não dá pra calcular variação % de uma base zero)
function fmtDelta(v) {
  if (v === null || v === undefined) return 'novo';
  const n = Number(v);
  return `${n > 0 ? '+' : ''}${n}%`;
}
function errorRow(colspan, msg) {
  return `<tr><td colspan="${colspan}" style="text-align:center; color: var(--accent-red);">Erro ao carregar: ${escapeHtml(msg)}</td></tr>`;
}
function emptyRow(colspan, msg = 'Sem dado no período selecionado.') {
  return `<tr><td colspan="${colspan}" style="text-align:center; color: var(--text-muted);">${escapeHtml(msg)}</td></tr>`;
}

// =============================================================================
// 4. DIRETÓRIOS — popula os 7 filtros multi-seleção
// =============================================================================
async function loadInboxDirectory() {
  const res = await fetchView("suporteapp_chatwoot_inboxes?select=chatwoot_inbox_id,name,channel_type&active=eq.true&order=name");
  if (!res.ok || !res.data || res.data.length === 0) {
    console.error("Não foi possível carregar suporteapp_chatwoot_inboxes:", res.error);
    msInit('channel', [], { type: 'int', allLabel: 'Todos os Canais' });
    return;
  }
  const items = res.data.map(inbox => ({
    value: inbox.chatwoot_inbox_id,
    label: `${inbox.name} (${inbox.channel_type.replace('Channel::', '')})`
  }));
  const defaultSelected = items
    .filter(i => DEFAULT_INBOX_IDS.includes(i.value))
    .map(i => String(i.value));
  msInit('channel', items, { type: 'int', allLabel: 'Todos os Canais', defaultSelected });
}

function channelLabelForInbox(inboxId) {
  return msLabelFor('channel', inboxId).replace(/ \([^)]*\)$/, '') || (inboxId ? `Inbox ${inboxId}` : 'Desconhecido');
}

// Popula o filtro de Agente (só humanos — bots já são cobertos pelo filtro Origem)
async function loadAgentDirectory() {
  const res = await fetchView("suporteapp_chatwoot_agents?select=chatwoot_id,name&active=eq.true&is_bot=eq.false&order=name");
  if (!res.ok || !res.data || res.data.length === 0) {
    console.error("Não foi possível carregar suporteapp_chatwoot_agents:", res.error);
    msInit('agent', [], { type: 'int', allLabel: 'Todas' });
    return;
  }
  const items = res.data.map(agent => ({ value: agent.chatwoot_id, label: agent.name }));
  msInit('agent', items, { type: 'int', allLabel: 'Todas' });
}

// Popula o filtro de Time
async function loadTeamDirectory() {
  const res = await fetchView("suporteapp_chatwoot_teams?select=chatwoot_team_id,name&active=eq.true&order=name");
  if (!res.ok || !res.data || res.data.length === 0) {
    console.error("Não foi possível carregar suporteapp_chatwoot_teams:", res.error);
    msInit('team', [], { type: 'int', allLabel: 'Todos' });
    return;
  }
  const items = res.data.map(team => ({ value: team.chatwoot_team_id, label: team.name }));
  msInit('team', items, { type: 'int', allLabel: 'Todos' });
}

// Popula o filtro de Tag a partir da taxonomia real (42 etiquetas), com opção "Sem Tag"
async function loadTagDirectory() {
  const res = await fetchView("suporteapp_label_taxonomy?select=label_name,thematic_group&order=thematic_group,label_name");
  const items = [{ value: '__sem_tag__', label: 'Sem Tag' }];
  if (!res.ok || !res.data) {
    console.error("Não foi possível carregar suporteapp_label_taxonomy:", res.error);
  } else {
    res.data.forEach(row => items.push({ value: row.label_name, label: row.label_name }));
  }
  msInit('tag', items, { type: 'text', allLabel: 'Todas' });
}

function initStaticFilters() {
  msInit('severity', [
    { value: 'P0', label: 'P0 / Red (Risco Churn/Cobrança)' },
    { value: 'P1', label: 'P1 / Yellow (Erro Login/Consulta)' },
    { value: 'P2', label: 'P2 / Green (Dúvidas de Recursos)' },
    { value: 'P3', label: 'P3 / Green (Feedback/Elogios)' }
  ], { type: 'text', allLabel: 'Todas as Severidades' });

  msInit('origin', [
    { value: 'human', label: 'Atendimento Humano' },
    { value: 'bot', label: 'Respostas por Bot' }
  ], { type: 'text', allLabel: 'Todos (Humano + Bot)' });

  msInit('taxonomy', [
    { value: 'valid', label: 'Com Taxonomia Válida (2 Tags)' },
    { value: 'missing', label: 'Com Taxonomia Ausente / Incompleta' }
  ], { type: 'text', allLabel: 'Todas as Conversas' });
}

// =============================================================================
// 5. ATUALIZAÇÃO INTEGRAL DO DASHBOARD (D-01 A D-17 E RS-01 A RS-14)
// =============================================================================
let isManualRefreshing = false;

function updateLastSyncTimestamp() {
  const timeLabel = document.getElementById("last-update-time");
  if (timeLabel) {
    const now = new Date();
    const timeStr = now.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
    timeLabel.innerText = `Atualizado às ${timeStr}`;
  }
}

async function triggerManualRefresh() {
  if (isManualRefreshing) return;
  isManualRefreshing = true;

  const btn = document.getElementById("btn-manual-refresh");
  const icon = document.getElementById("refresh-icon");
  const timeLabel = document.getElementById("last-update-time");

  if (btn) btn.disabled = true;
  if (icon) icon.classList.add("spinning");
  if (timeLabel) timeLabel.innerText = "Atualizando...";

  try {
    await updateDashboard();
    updateLastSyncTimestamp();
  } catch (err) {
    console.error("Erro na atualização manual:", err);
    if (timeLabel) timeLabel.innerText = "Erro ao sincronizar";
  } finally {
    if (icon) icon.classList.remove("spinning");
    if (btn) btn.disabled = false;
    isManualRefreshing = false;
  }
}
window.triggerManualRefresh = triggerManualRefresh;

async function updateDashboard() {
  console.log(`🔄 Atualizando Dashboard com Filtros Globais:`, currentFilters);

  await Promise.all([
    renderBlocoA(),
    renderBlocoB(),
    renderBlocoC(),
    renderBlocoD(),
    renderRS02(),
    renderRS06(),
    renderRS01Heatmap(),
    renderRS03Matrix(),
    renderRS05(),
    renderRS07(),
    renderRS08(),
    renderRS09(),
    renderRS10(),
    renderRS11(),
    renderRS12(),
    renderRS13()
  ]);

  if (!isManualRefreshing) {
    updateLastSyncTimestamp();
  }
}

// ---------------------------------------------------------------------------
// BLOCO A: FILA AGORA (sem filtro de período/data — é a fila em tempo real)
// ---------------------------------------------------------------------------
async function renderBlocoA() {
  const res = await fetchRPC("suporteapp_rpc_dashboard_queue", filterParams());
  if (!res.ok) {
    console.error("suporteapp_rpc_dashboard_queue:", res.error);
    ['d01-value','d02-value','d03-value','d05-value','d06-value'].forEach(id => document.getElementById(id).innerText = 'erro');
    document.getElementById("d06-subtext").innerText = "Erro ao carregar adesão de taxonomia.";
    document.getElementById("d04-median").innerText = 'erro';
    document.getElementById("d04-p90").innerText = 'erro';
    ['bar-u1h','bar-1-4h','bar-4-24h','bar-24-72h','bar-o72h'].forEach(id => document.getElementById(id).style.width = '0%');
    ['val-u1h','val-1-4h','val-4-24h','val-24-72h','val-o72h'].forEach(id => document.getElementById(id).innerText = '—');
    return;
  }
  const q = (res.data && res.data[0]) || {};
  document.getElementById("d01-value").innerText = q.d01_waiting_plinq ?? 0;
  document.getElementById("d02-value").innerText = q.d02_waiting_customer ?? 0;

  const redCount = q.d03_red_aberta_alerts ?? 0;
  const d03Card = document.getElementById("d03-card");
  document.getElementById("d03-value").innerText = redCount;
  d03Card.className = redCount > 0 ? "card card-danger-animated card-interactive" : "card card-success card-interactive";

  document.getElementById("d05-value").innerText = q.d05_unserviced_tickets ?? 0;

  const adherence = q.d06_taxonomy_adherence_pct;
  const d06Card = document.getElementById("d06-card");
  document.getElementById("d06-value").innerText = adherence === null || adherence === undefined ? 'sem dado' : `${adherence}%`;
  document.getElementById("d06-subtext").innerText = (adherence !== null && adherence !== undefined && adherence < 95)
    ? `Atenção: Apenas ${adherence}% dos chamados contêm as 2 tags obrigatórias.`
    : (adherence === null || adherence === undefined ? "Sem tickets na fila para calcular adesão." : "Excelente: Meta de adesão (≥ 95%) cumprida.");
  d06Card.className = (adherence !== null && adherence !== undefined && adherence < 95) ? "card card-warning" : "card card-info";

  const badgeTop = document.getElementById("badge-adherence-top");
  const showBadge = adherence !== null && adherence !== undefined && adherence < 95;
  badgeTop.innerText = `Adesão Taxonomia: ${adherence ?? '--'}%`;
  badgeTop.style.display = showBadge ? "inline-flex" : "none";

  const u1h = q.d04_under_1h ?? 0, h1_4 = q.d04_1h_to_4h ?? 0, h4_24 = q.d04_4h_to_24h ?? 0, h24_72 = q.d04_24h_to_72h ?? 0, o72h = q.d04_over_72h ?? 0;
  const totalQueue = Math.max(1, (q.d01_waiting_plinq ?? 0));
  document.getElementById("bar-u1h").style.width = `${(u1h / totalQueue) * 100}%`;
  document.getElementById("val-u1h").innerText = u1h;
  document.getElementById("bar-1-4h").style.width = `${(h1_4 / totalQueue) * 100}%`;
  document.getElementById("val-1-4h").innerText = h1_4;
  document.getElementById("bar-4-24h").style.width = `${(h4_24 / totalQueue) * 100}%`;
  document.getElementById("val-4-24h").innerText = h4_24;
  document.getElementById("bar-24-72h").style.width = `${(h24_72 / totalQueue) * 100}%`;
  document.getElementById("val-24-72h").innerText = h24_72;
  document.getElementById("bar-o72h").style.width = `${(o72h / totalQueue) * 100}%`;
  document.getElementById("val-o72h").innerText = o72h;

  document.getElementById("d04-median").innerText = fmtMin(q.d04_median_biz_minutes);
  document.getElementById("d04-p90").innerText = fmtMin(q.d04_p90_biz_minutes);
}

// ---------------------------------------------------------------------------
// BLOCO B: FLUXO E ESPERA (D-07 a D-12) + RS-04
// ---------------------------------------------------------------------------
async function renderBlocoB() {
  const res = await fetchRPC("suporteapp_rpc_turn_metrics", filterParams({ p_period: currentFilters.period, ...dateRangeParams() }));
  if (!res.ok) {
    console.error("suporteapp_rpc_turn_metrics:", res.error);
    ['d07-value','d09-value','d08-median','d08-p90','d10-median','d12-value',
     'd11-created','d11-manual','d11-inactivity','d11-balance-val',
     'rs04-avg-biz','rs04-med-biz','rs04-p90-biz','rs04-meta-biz',
     'rs04-avg-raw','rs04-med-raw','rs04-p90-raw','rs04-meta-raw'].forEach(id => document.getElementById(id).innerText = 'erro');
    ['d11-manual-pct','d11-inactivity-pct'].forEach(id => document.getElementById(id).innerText = 'erro');
    ['d11-manual-bar','d11-inactivity-bar'].forEach(id => document.getElementById(id).style.width = '0%');
    return;
  }
  const t = (res.data && res.data[0]) || {};
  const created = Number(t.total_tickets) || 0;
  const resolvedManual = Number(t.resolved_manual) || 0;
  const resolvedInactivity = Number(t.resolved_inactivity) || 0;
  const resolvedBotAuto = Number(t.resolved_bot_auto) || 0;
  const totalResolved = Number(t.tickets_resolved) || 0;
  const balance = created - totalResolved;

  document.getElementById("d07-value").innerText = created;
  document.getElementById("d08-median").innerText = fmtMin(t.d08_median_turn1_biz_minutes);
  document.getElementById("d08-p90").innerText = fmtMin(t.d08_p90_turn1_biz_minutes);
  document.getElementById("d09-value").innerText = fmtPct(t.d09_meta_10min_compliance_pct);
  document.getElementById("d10-median").innerText = fmtMin(t.d10_median_turn2_biz_minutes);

  document.getElementById("d11-created").innerText = created;
  document.getElementById("d11-manual").innerText = resolvedManual;
  document.getElementById("d11-inactivity").innerText = resolvedInactivity;
  document.getElementById("d11-balance-val").innerText = balance >= 0 ? `+${balance}` : `${balance}`;

  const balanceCard = document.getElementById("d11-balance-card");
  if (balance > 0) {
    balanceCard.className = "card card-warning";
    document.getElementById("d11-balance-sub").innerText = "Fila em crescimento (Atenção)";
  } else {
    balanceCard.className = "card card-success";
    document.getElementById("d11-balance-sub").innerText = "Fila em redução ou estável";
  }

  const denomResolved = Math.max(1, resolvedManual + resolvedInactivity + resolvedBotAuto);
  const manualPct = Math.round((resolvedManual / denomResolved) * 100);
  const inactPct = Math.round((resolvedInactivity / denomResolved) * 100);
  document.getElementById("d11-manual-pct").innerText = totalResolved > 0 ? `${manualPct}% (${resolvedManual} chamados)` : 'sem dado';
  document.getElementById("d11-inactivity-pct").innerText = totalResolved > 0 ? `${inactPct}% (${resolvedInactivity} chamados)` : 'sem dado';
  document.getElementById("d11-manual-bar").style.width = `${manualPct}%`;
  document.getElementById("d11-inactivity-bar").style.width = `${inactPct}%`;

  document.getElementById("d12-value").innerText = fmtPct(t.outside_biz_pct);
  document.getElementById("d12-subtext").innerText = `Total fora do expediente: ${t.outside_biz_count ?? 0} (Red: ${t.outside_red_count ?? 0})`;

  // RS-04: espera atendível (biz) vs. corrida (raw)
  const setIfExists = (id, val) => { const el = document.getElementById(id); if (el) el.innerText = val; };
  setIfExists("rs04-avg-biz", fmtMin(t.d08_avg_turn1_biz_minutes));
  setIfExists("rs04-med-biz", fmtMin(t.d08_median_turn1_biz_minutes));
  setIfExists("rs04-p90-biz", fmtMin(t.d08_p90_turn1_biz_minutes));
  setIfExists("rs04-meta-biz", fmtPct(t.d09_meta_10min_compliance_pct));
  setIfExists("rs04-avg-raw", fmtMin(t.rs04_avg_turn1_raw_minutes));
  setIfExists("rs04-med-raw", fmtMin(t.rs04_median_turn1_raw_minutes));
  setIfExists("rs04-p90-raw", fmtMin(t.rs04_p90_turn1_raw_minutes));
  setIfExists("rs04-meta-raw", fmtPct(t.rs04_meta_10min_compliance_raw_pct));
}

// ---------------------------------------------------------------------------
// BLOCO C: TURNO DA AGENTE
// ---------------------------------------------------------------------------
async function renderBlocoC() {
  const res = await fetchRPC("suporteapp_rpc_daily_shift_metrics", filterParams({ p_period: currentFilters.period, ...dateRangeParams() }));
  if (!res.ok) {
    console.error("suporteapp_rpc_daily_shift_metrics:", res.error);
    ['d13-latency','d14-value','d15-time','d16-value'].forEach(id => document.getElementById(id).innerText = 'erro');
    return;
  }
  const s = (res.data && res.data[0]) || {};
  document.getElementById("d13-latency").innerText = s.avg_opening_latency_minutes != null ? `${Math.max(0, Math.round(s.avg_opening_latency_minutes))} min` : 'sem dado';
  document.getElementById("d14-value").innerText = `${s.inherited_queue_count ?? 0} tks`;
  document.getElementById("d14-subtext").innerText = `Fila às 09:00h | Tempo p/ zerar: ${s.time_to_zero_hours != null ? s.time_to_zero_hours + 'h' : 'em aberto'}`;
  document.getElementById("d15-time").innerText = s.avg_closing_time || "--:--";
  document.getElementById("d16-value").innerText = s.max_idle_minutes != null ? `${Math.round(s.max_idle_minutes)} min` : 'sem dado';
  document.getElementById("d16-subtext").innerText = s.max_idle_start ? `Maior hiato com fila iniciado às ${s.max_idle_start}` : 'Sem mensagens de agente hoje ainda.';
}

// ---------------------------------------------------------------------------
// BLOCO D: BOT E IA
// ---------------------------------------------------------------------------
async function renderBlocoD() {
  const res = await fetchRPC("suporteapp_rpc_bot_metrics", filterParams({ p_period: currentFilters.period, ...dateRangeParams() }));
  if (!res.ok) {
    console.error("suporteapp_rpc_bot_metrics:", res.error);
    ['d17-total','d17-contencao','d17-transbordo','d17-herdada'].forEach(id => document.getElementById(id).innerText = 'erro');
    return;
  }
  const b = (res.data && res.data[0]) || {};
  document.getElementById("d17-total").innerText = b.bot_total_conversations ?? 0;
  document.getElementById("d17-contencao").innerText = fmtPct(b.bot_containment_pct);
  document.getElementById("d17-transbordo").innerText = fmtPct(b.bot_handover_pct);
  document.getElementById("d17-herdada").innerText = b.bot_inherited_queue ?? 0;
}

// ---------------------------------------------------------------------------
// RS-02: Tabela de assuntos por motivo
// ---------------------------------------------------------------------------
async function renderRS02() {
  const tbody = document.getElementById("tbody-reasons");
  const res = await fetchRPC("suporteapp_rpc_weekly_reasons", filterParams({ p_period: currentFilters.period, ...dateRangeParams() }));
  if (!res.ok) { tbody.innerHTML = errorRow(6, res.error); return; }
  if (!res.data || res.data.length === 0) { tbody.innerHTML = emptyRow(6); return; }
  tbody.innerHTML = res.data.map(r => `
    <tr>
      <td><strong><code>${escapeHtml(r.reason_label)}</code></strong></td>
      <td>${r.total_count}</td>
      <td>${r.volume_pct}%</td>
      <td>${fmtDelta(r.volume_delta_pct)}</td>
      <td>${fmtMin(r.median_wait_biz_minutes)}</td>
      <td>${fmtMin(r.median_resolution_biz_minutes)}</td>
    </tr>
  `).join("");
}

// ---------------------------------------------------------------------------
// RS-06: Espera Evitável vs Estrutural
// ---------------------------------------------------------------------------
async function renderRS06() {
  const res = await fetchRPC("suporteapp_rpc_avoidable_vs_structural", filterParams({ p_period: currentFilters.period, ...dateRangeParams() }));
  if (!res.ok) {
    console.error("suporteapp_rpc_avoidable_vs_structural:", res.error);
    ['rs06-avoidable-text','rs06-structural-text','rs06-avoidable-hrs','rs06-structural-hrs'].forEach(id => document.getElementById(id).innerText = 'erro');
    ['rs06-avoidable-bar','rs06-structural-bar'].forEach(id => document.getElementById(id).style.width = '0%');
    return;
  }
  const w = (res.data && res.data[0]) || {};
  const avoidablePct = w.avoidable_pct ?? 0, structuralPct = w.structural_pct ?? 0;
  document.getElementById("rs06-avoidable-bar").style.width = `${avoidablePct}%`;
  document.getElementById("rs06-avoidable-text").innerText = fmtPct(w.avoidable_pct);
  document.getElementById("rs06-structural-bar").style.width = `${structuralPct}%`;
  document.getElementById("rs06-structural-text").innerText = fmtPct(w.structural_pct);
  document.getElementById("rs06-avoidable-hrs").innerText = `${w.avoidable_hours ?? 0}h`;
  document.getElementById("rs06-structural-hrs").innerText = `${w.structural_hours ?? 0}h`;
}

// ---------------------------------------------------------------------------
// RS-01: Heatmap 7x24
// ---------------------------------------------------------------------------
async function renderRS01Heatmap() {
  const tbody = document.getElementById("tbody-heatmap");
  const res = await fetchRPC("suporteapp_rpc_weekly_heatmap", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }));
  if (!res.ok) { tbody.innerHTML = errorRow(8, res.error); return; }
  const grid = {};
  (res.data || []).forEach(row => {
    grid[row.isodow] = grid[row.isodow] || {};
    grid[row.isodow][row.hour_bucket] = row.total_count;
  });
  const maxVal = Math.max(1, ...(res.data || []).map(r => r.total_count));
  tbody.innerHTML = [1,2,3,4,5,6,7].map(dow => {
    const isWeekend = dow >= 6;
    const cells = heatmapBuckets.map(bucket => {
      const val = (grid[dow] && grid[dow][bucket]) || 0;
      const intensity = Math.min(0.55, 0.05 + (val / maxVal) * 0.5);
      const color = isWeekend ? `rgba(251,146,60,${intensity.toFixed(2)})` : `rgba(56,189,248,${intensity.toFixed(2)})`;
      const bold = val / maxVal > 0.5 ? 'font-weight:700;' : '';
      return `<td style="background:${color}; ${bold}">${val}</td>`;
    }).join("");
    const dayStyle = isWeekend ? 'style="color: var(--accent-orange);"' : '';
    return `<tr><td ${dayStyle}>${weekdayLabels[dow]}</td>${cells}</tr>`;
  }).join("");
}

// ---------------------------------------------------------------------------
// RS-03: Matriz Motivo x Severidade
// ---------------------------------------------------------------------------
async function renderRS03Matrix() {
  const tbody = document.getElementById("tbody-rs03-matrix");
  const res = await fetchRPC("suporteapp_rpc_reason_severity_matrix", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }));
  if (!res.ok) { tbody.innerHTML = errorRow(5, res.error); return; }
  if (!res.data || res.data.length === 0) { tbody.innerHTML = emptyRow(5, 'Nenhum chamado com etiqueta de motivo no período (adesão à taxonomia ainda baixa).'); return; }
  tbody.innerHTML = res.data.map(r => `
    <tr>
      <td><code>${escapeHtml(r.reason_label)}</code></td>
      <td>${r.p0_count}</td>
      <td>${r.p1_count}</td>
      <td>${r.p2_p3_count}</td>
      <td><strong>${r.total_count}</strong></td>
    </tr>
  `).join("");
}

// ---------------------------------------------------------------------------
// RS-05: Decomposição de resolução + reaberturas
// ---------------------------------------------------------------------------
async function renderRS05() {
  const [breakdownRes, reopenRes] = await Promise.all([
    fetchRPC("suporteapp_rpc_resolution_breakdown", filterParams({ p_period: rsPeriod(), ...dateRangeParams() })),
    fetchRPC("suporteapp_rpc_reopen_count", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }))
  ]);
  const setIfExists = (id, val) => { const el = document.getElementById(id); if (el) el.innerText = val; };
  if (breakdownRes.ok && breakdownRes.data) {
    const manual = breakdownRes.data.find(r => r.resolution_type === 'manual') || {};
    const inact = breakdownRes.data.find(r => r.resolution_type === 'inactivity_3d') || {};
    setIfExists("rs05-manual-count", manual.total_count ?? 0);
    setIfExists("rs05-manual-pct", fmtPct(manual.pct));
    setIfExists("rs05-manual-med", manual.median_hours != null ? `${manual.median_hours}h` : 'sem dado');
    setIfExists("rs05-manual-p90", manual.p90_hours != null ? `${manual.p90_hours}h` : 'sem dado');
    setIfExists("rs05-inact-count", inact.total_count ?? 0);
    setIfExists("rs05-inact-pct", fmtPct(inact.pct));
  } else {
    console.error("suporteapp_rpc_resolution_breakdown:", breakdownRes.error);
    ['rs05-manual-count','rs05-manual-pct','rs05-manual-med','rs05-manual-p90','rs05-inact-count','rs05-inact-pct']
      .forEach(id => setIfExists(id, 'erro'));
  }
  setIfExists("rs05-reopen-count", reopenRes.ok ? (reopenRes.data ?? 0) : 'erro');
}

// ---------------------------------------------------------------------------
// RS-07: Balanço de estoque carregado
// ---------------------------------------------------------------------------
async function renderRS07() {
  const res = await fetchRPC("suporteapp_rpc_carried_stock", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }));
  const setIfExists = (id, val) => { const el = document.getElementById(id); if (el) el.innerText = val; };
  if (!res.ok) { console.error("suporteapp_rpc_carried_stock:", res.error); return; }
  const c = (res.data && res.data[0]) || {};
  setIfExists("rs07-opening", c.opening_stock ?? 0);
  setIfExists("rs07-carried", c.carried_stock ?? 0);
  setIfExists("rs07-carried-inline", c.carried_stock ?? 0);
  setIfExists("rs07-over7d", `${c.carried_over_7d ?? 0} conversas possuem`);
}

// ---------------------------------------------------------------------------
// RS-08: Painel de alarmes
// ---------------------------------------------------------------------------
async function renderRS08() {
  const res = await fetchRPC("suporteapp_rpc_alarm_panel", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }));
  const setIfExists = (id, val) => { const el = document.getElementById(id); if (el) el.innerText = val; };
  if (!res.ok) { console.error("suporteapp_rpc_alarm_panel:", res.error); return; }
  const a = (res.data && res.data[0]) || {};
  setIfExists("rs08-sem-atendimento", a.sem_atendimento ?? 0);
  setIfExists("rs08-red-janela", a.red_estourado_janela ?? 0);
  setIfExists("rs08-red-fora", a.red_estourado_fora ?? 0);
  setIfExists("rs08-acima-72h", a.acima_72h ?? 0);
}

// ---------------------------------------------------------------------------
// RS-09: Handoff Externo
// ---------------------------------------------------------------------------
async function renderRS09() {
  const tbody = document.getElementById("tbody-handoff");
  const res = await fetchRPC("suporteapp_rpc_weekly_handoff", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }));
  if (!res.ok) { tbody.innerHTML = errorRow(4, res.error); return; }
  if (!res.data || res.data.length === 0) { tbody.innerHTML = emptyRow(4, 'Nenhum chamado etiquetado com área de destino no período.'); return; }
  tbody.innerHTML = res.data.map(h => `
    <tr>
      <td><strong>${escapeHtml(h.destiny_area)}</strong></td>
      <td><code>${escapeHtml(h.reason_label)}</code></td>
      <td>${h.total_tickets}</td>
      <td>${h.median_resolution_days != null ? escapeHtml(h.median_resolution_days) + ' dias' : 'sem dado'}</td>
    </tr>
  `).join("");
}

// ---------------------------------------------------------------------------
// RS-10: Resolvidas em 1 toque (FCR)
// ---------------------------------------------------------------------------
async function renderRS10() {
  const tbody = document.getElementById("tbody-fcr");
  const res = await fetchRPC("suporteapp_rpc_first_contact_resolution", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }));
  if (!res.ok) { tbody.innerHTML = errorRow(3, res.error); return; }
  if (!res.data || res.data.length === 0) { tbody.innerHTML = emptyRow(3); return; }
  tbody.innerHTML = res.data.map(r => `
    <tr>
      <td><code>${escapeHtml(r.reason_label)}</code></td>
      <td><strong style="color: ${r.fcr_pct >= 50 ? 'var(--accent-green)' : 'var(--accent-red)'}">${r.fcr_pct}%</strong></td>
      <td>${r.total_resolved}</td>
    </tr>
  `).join("");
}

// ---------------------------------------------------------------------------
// RS-11: Taxa de reincidência
// ---------------------------------------------------------------------------
async function renderRS11() {
  // RS-11 mede recorrência em janelas fixas de 7d/30d contadas a partir de uma data de
  // referência (p_date_end) — não de um p_period, já que "recorrência nos últimos 7 dias
  // dentro de uma janela de 7 dias" não faz sentido. Com período customizado, a referência
  // vira a data final escolhida; nos presets, a referência é sempre "agora" (p_date_end null).
  const res = await fetchRPC("suporteapp_rpc_recurrence_rate", filterParams({
    p_date_end: currentFilters.period === 'custom' ? currentFilters.dateEnd : null
  }));
  const setIfExists = (id, val) => { const el = document.getElementById(id); if (el) el.innerText = val; };
  if (!res.ok) { console.error("suporteapp_rpc_recurrence_rate:", res.error); return; }
  const r = (res.data && res.data[0]) || {};
  setIfExists("rs11-7d", fmtPct(r.recurrence_7d_pct));
  setIfExists("rs11-30d", fmtPct(r.recurrence_30d_pct));
  setIfExists("rs11-top-reason", r.top_recurring_reason || '(sem dado)');
}

// ---------------------------------------------------------------------------
// RS-12: Contestações & Falso Negativo
// ---------------------------------------------------------------------------
async function renderRS12() {
  const res = await fetchRPC("suporteapp_rpc_contest_and_false_negative", filterParams({ p_period: rsPeriod(), ...dateRangeParams() }));
  if (!res.ok) { console.error("suporteapp_rpc_contest_and_false_negative:", res.error); return; }
  const c = (res.data && res.data[0]) || {};
  document.getElementById("rs12-contest-badge").innerText = `Contestações: ${c.contested_count ?? 0}`;
  document.getElementById("rs12-falso-badge").innerText = `Falso Negativo: ${c.false_negative_count ?? 0}`;
  const hasAny = (c.contested_count ?? 0) > 0 || (c.false_negative_count ?? 0) > 0;
  document.getElementById("rs12-list-content").innerHTML = `
    <div style="display:flex; flex-direction:column; gap:0.3rem;">
      <p>${hasAny ? '⚠️' : '✅'} ${hasAny ? 'Há contestações/falsos-negativos registrados' : 'Nenhuma contestação formal registrada'} na janela selecionada (${periodLabels[currentFilters.period]}).</p>
      <p style="font-size:0.78rem; color:var(--text-muted);">Baseado nas etiquetas <code>relatorio-contestado</code> / <code>falso-negativo</code> aplicadas na conversa no Chatwoot.</p>
    </div>
  `;
}

// ---------------------------------------------------------------------------
// RS-13: Transbordo do Bot / Whitelist
// ---------------------------------------------------------------------------
async function renderRS13() {
  const tbody = document.getElementById("tbody-bot-handover");
  const res = await fetchRPC("suporteapp_rpc_bot_handover_top_subjects", filterParams({ p_period: rsPeriod(), p_limit: 5, ...dateRangeParams() }));
  if (!res.ok) { tbody.innerHTML = errorRow(2, res.error); return; }
  if (!res.data || res.data.length === 0) { tbody.innerHTML = emptyRow(2, 'Nenhum transbordo de bot etiquetado no período.'); return; }
  tbody.innerHTML = res.data.map(r => `<tr><td><code>${escapeHtml(r.reason_label)}</code></td><td>${escapeHtml(r.handover_count)}</td></tr>`).join("");
}

// =============================================================================
// 6. MODAL DE DRILL-DOWN / INSPEÇÃO GRANULAR DE CHAMADOS (DADOS REAIS DO SUPABASE)
// =============================================================================
function getActiveDateRange() {
  const today = getBrtTodayDate();
  if (currentFilters.dateStart && currentFilters.dateEnd) {
    const start = new Date(`${currentFilters.dateStart}T00:00:00-03:00`);
    const [y, m, d] = currentFilters.dateEnd.split('-').map(Number);
    const endNextDay = new Date(y, m - 1, d + 1, 0, 0, 0);
    const end = new Date(`${toIsoDate(endNextDay)}T00:00:00-03:00`);
    return { start, end };
  }
  const now = new Date();
  if (currentFilters.period === 'today') {
    const todayIso = toIsoDate(today);
    const start = new Date(`${todayIso}T00:00:00-03:00`);
    return { start, end: now };
  }
  if (currentFilters.period === '7d') {
    return { start: new Date(now.getTime() - 7 * 86400000), end: now };
  }
  return { start: new Date(now.getTime() - 30 * 86400000), end: now };
}

async function openDrilldownModal(type) {
  const modal = document.getElementById("drilldown-modal");
  const title = document.getElementById("modal-title");
  const subtitle = document.getElementById("modal-subtitle");
  const tbody = document.getElementById("modal-tbody");

  modal.style.display = "flex";
  tbody.innerHTML = `<tr><td colspan="8" style="text-align: center; color: var(--text-muted); padding: 2rem;">Carregando chamados reais do Supabase...</td></tr>`;

  const qs = new URLSearchParams({ select: '*', order: 'created_at.desc', limit: '300' });
  const inboxIds = msGetParam('channel');
  if (inboxIds) qs.set('chatwoot_inbox_id', `in.(${inboxIds.join(',') || 'null'})`);
  const severities = msGetParam('severity');
  if (severities) qs.set('priority', `in.(${severities.join(',') || 'null'})`);
  const agentIds = msGetParam('agent');
  if (agentIds) qs.set('current_agent_id', `in.(${agentIds.join(',') || 'null'})`);
  const teamIds = msGetParam('team');
  if (teamIds) qs.set('current_team_id', `in.(${teamIds.join(',') || 'null'})`);

  const res = await fetchView(`suporteapp_tickets?${qs.toString()}`);
  if (!res.ok) {
    tbody.innerHTML = `<tr><td colspan="8" style="text-align: center; color: var(--accent-red); padding: 2rem;">Erro ao carregar dados do Supabase: ${res.error}</td></tr>`;
    return;
  }
  const tickets = res.data || [];

  let scoped = tickets.map(t => ({
    ...t,
    queue_state: (t.last_customer_message_at && (!t.last_agent_message_at || t.last_customer_message_at > t.last_agent_message_at))
      ? 'waiting_plinq' : 'waiting_customer'
  }));

  // 1. Filtro de Tags
  const tagsParam = msGetParam('tag');
  if (tagsParam && tagsParam.length > 0) {
    scoped = scoped.filter(t => {
      const labels = t.current_labels || [];
      if (tagsParam.includes('__sem_tag__') && labels.length === 0) return true;
      return labels.some(l => tagsParam.includes(l));
    });
  }

  // 2. Filtro de Origem (Humano vs Bot)
  const originsParam = msGetParam('origin');
  if (originsParam && originsParam.length > 0) {
    const hasHuman = originsParam.includes('human');
    const hasBot = originsParam.includes('bot');
    if (hasHuman && !hasBot) {
      scoped = scoped.filter(t => t.current_agent_id !== 1);
    } else if (hasBot && !hasHuman) {
      scoped = scoped.filter(t => t.current_agent_id === 1);
    }
  }

  // 3. Filtro de Taxonomia (Válida vs Ausente)
  const taxParam = msGetParam('taxonomy');
  if (taxParam && taxParam.length > 0) {
    const sevTags = ['sev-red', 'sev-yellow', 'sev-green'];
    const reasonTags = ['login-acesso','duvida-de-plano','erro-tecnico','app-fora-do-ar','reembolso','meus-dados-lgpd','pessoa-consultada','advogado-ou-autoridade'];
    const wantValid = taxParam.includes('valid') && !taxParam.includes('missing');
    const wantMissing = taxParam.includes('missing') && !taxParam.includes('valid');
    if (wantValid || wantMissing) {
      scoped = scoped.filter(t => {
        const labels = t.current_labels || [];
        const isValid = labels.some(l => sevTags.includes(l)) && labels.some(l => reasonTags.includes(l));
        return wantValid ? isValid : !isValid;
      });
    }
  }

  // 4. Filtro de Horário Comercial (Início Fora do Expediente)
  const bhFilter = document.getElementById('filter-business-hours')?.value;
  if (bhFilter === 'only_outside' || bhFilter === 'exclude_outside') {
    scoped = scoped.filter(t => {
      if (!t.created_at) return true;
      const spDate = new Date(new Date(t.created_at).toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
      const dow = spDate.getDay();
      const hrs = spDate.getHours();
      const isInside = (dow >= 1 && dow <= 5 && hrs >= 9 && hrs < 18);
      return bhFilter === 'only_outside' ? !isInside : isInside;
    });
  }

  // 5. Filtro de Fim de Semana
  const weFilter = document.getElementById('filter-weekend')?.value;
  if (weFilter === 'only_weekend' || weFilter === 'exclude_weekend') {
    scoped = scoped.filter(t => {
      if (!t.created_at) return true;
      const spDate = new Date(new Date(t.created_at).toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
      const dow = spDate.getDay();
      const hrs = spDate.getHours();
      const isWeekend = (dow === 5 && hrs >= 18) || (dow === 6) || (dow === 0) || (dow === 1 && hrs < 9);
      return weFilter === 'only_weekend' ? isWeekend : !isWeekend;
    });
  }

  // 6. Recorte de Período Temporal Ativo (exceto Bloco A que é fila viva em tempo real)
  const isQueueType = ['d01', 'd02', 'd03', 'd04', 'd05', 'd06'].includes(type);
  const isResolutionType = ['d11_manual', 'd11_inactivity', 'rs05_manual', 'rs05_inact'].includes(type);
  const activeRange = getActiveDateRange();

  if (!isQueueType && activeRange) {
    scoped = scoped.filter(t => {
      if (isResolutionType) {
        if (!t.resolved_at) return false;
        const rDate = new Date(t.resolved_at);
        return rDate >= activeRange.start && rDate < activeRange.end;
      } else {
        if (!t.created_at) return false;
        const cDate = new Date(t.created_at);
        return cDate >= activeRange.start && cDate < activeRange.end;
      }
    });
  }

  let filtered = scoped;
  let labelTitle = "Inspeção Granular de Chamados";
  let labelSub = "Detalhamento individual dos registros da base de dados";

  switch (type) {
    case 'd01':
      labelTitle = "D-01 · Fila de Atendimento Plinq (Chamados Abertos)";
      labelSub = "Chamados abertos aguardando resposta humana (Plinq com a bola)";
      filtered = scoped.filter(t => t.status === 'open' && t.queue_state === 'waiting_plinq');
      break;
    case 'd02':
      labelTitle = "D-02 · Aguardando Resposta da Usuária";
      labelSub = "Conversas abertas aguardando retorno da cliente";
      filtered = scoped.filter(t => t.status === 'open' && t.queue_state === 'waiting_customer');
      break;
    case 'd03':
      labelTitle = "🚨 D-03 · Alerta Red (> 10 min em Relógio Corrido 24x7)";
      labelSub = "Chamados P0 de risco crítico sem resposta há mais de 10 minutos (Ação Imediata)";
      filtered = scoped.filter(t => {
        if (t.status !== 'open' || t.queue_state !== 'waiting_plinq') return false;
        const isRed = t.priority === 'P0' || (t.current_labels && t.current_labels.includes('sev-red'));
        if (!isRed) return false;
        const refTime = t.last_customer_message_at ? new Date(t.last_customer_message_at) : (t.created_at ? new Date(t.created_at) : new Date());
        return (Date.now() - refTime.getTime()) / 60000 > 10;
      });
      break;
    case 'd04':
      labelTitle = "D-04 · Envelhecimento da Fila (Histograma)";
      labelSub = "Chamados abertos organizados por faixas de idade em janela comercial";
      filtered = scoped.filter(t => t.status !== 'resolved');
      break;
    case 'd05':
      labelTitle = "⚠️ D-05 · Chamados Sem Atendimento Nenhum";
      labelSub = "Chamados abertos na fila aguardando que ainda não receberam nenhuma resposta humana de saída";
      filtered = scoped.filter(t => t.status === 'open' && t.queue_state === 'waiting_plinq' && !t.last_agent_message_at);
      break;
    case 'd06':
      labelTitle = "D-06 · Audit de Taxonomia de Etiquetas";
      labelSub = "Verificação de rotulagem de severidade e motivo nos chamados";
      filtered = scoped;
      break;
    case 'd07':
    case 'd11_created':
      labelTitle = "D-07 / D-11 · Conversas Novas Criadas (Entradas)";
      labelSub = "Total de chamados criados no período selecionado";
      filtered = scoped;
      break;
    case 'd08_med':
    case 'd08_p90':
    case 'd09':
      labelTitle = "D-08 / D-09 · Métricas de 1ª Resposta e Cumprimento SLA";
      labelSub = "Chamados com primeira resposta pública registrada";
      filtered = scoped.filter(t => t.first_public_reply_at);
      break;
    case 'd10':
      labelTitle = "D-10 · Espera nas Respostas Seguintes";
      labelSub = "Conversas com múltiplos turnos de diálogo";
      filtered = scoped.filter(t => t.last_customer_message_at);
      break;
    case 'd11':
    case 'd11_balance':
      labelTitle = "D-11 · Balanço Geral de Fila (Entradas vs. Saídas)";
      labelSub = "Visão completa da movimentação de estoque de chamados";
      filtered = scoped;
      break;
    case 'd11_manual':
    case 'rs05_manual':
      labelTitle = "D-11 / RS-05 · Resoluções Manuais por Atendentes";
      labelSub = "Chamados encerrados por ação humana (resolution_type = manual)";
      filtered = scoped.filter(t => t.status === 'resolved' && t.resolution_type === 'manual');
      break;
    case 'd11_inactivity':
    case 'rs05_inact':
      labelTitle = "D-11 / RS-05 · Resoluções por Inatividade (3 Dias)";
      labelSub = "Encerramentos automáticos por inatividade do cliente";
      filtered = scoped.filter(t => t.status === 'resolved' && t.resolution_type === 'inactivity_3d');
      break;
    case 'd12':
      labelTitle = "D-12 · Demanda Fora da Janela Comercial";
      labelSub = "Chamados criados fora do horário comercial (antes das 09h, após 18h ou fim de semana)";
      filtered = scoped;
      break;
    case 'd13': case 'd14': case 'd15': case 'd16':
      labelTitle = `Turno da Agente (${type.toUpperCase()})`;
      labelSub = "Acompanhamento de latência, zeragem de fila e horários de atendimento do turno";
      filtered = scoped;
      break;
    case 'd17_total': case 'd17_containment': case 'd17_handover': case 'd17_inherited': case 'rs13':
      labelTitle = "D-17 / RS-13 · Atendimento Bot & IA";
      labelSub = "Detalhamento de conversas atendidas, contidas ou transbordadas pelo Bot";
      filtered = scoped;
      break;
    case 'rs12':
      labelTitle = "RS-12 · Contestações de Relatório & Falso Negativo";
      labelSub = "Chamados etiquetados com relatorio-contestado / falso-negativo";
      filtered = scoped.filter(t => t.current_labels && (t.current_labels.includes('relatorio-contestado') || t.current_labels.includes('falso-negativo')));
      break;
    default:
      labelTitle = `Inspeção de Chamados (${type.toUpperCase()})`;
      labelSub = "Lista detalhada de chamados associados à métrica";
      filtered = scoped;
      break;
  }

  title.innerText = labelTitle;
  subtitle.innerText = `${labelSub} (${filtered.length} chamados encontrados)`;

  if (!filtered || filtered.length === 0) {
    tbody.innerHTML = `<tr><td colspan="8" style="text-align: center; color: var(--text-muted); padding: 2rem;">Nenhum chamado encontrado para os critérios selecionados nesta janela.</td></tr>`;
    return;
  }

  tbody.innerHTML = filtered.map(t => {
    const rawConvId = t.chatwoot_conversation_id || t.id || "N/A";
    const rawCustomerName = t.customer_name || t.customer_email || "Usuária Plinq";
    const rawChannel = channelLabelForInbox(t.chatwoot_inbox_id);
    const createdAt = t.created_at ? new Date(t.created_at).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—";

    let waitStr = '—';
    if (t.status === 'resolved') {
      if (t.first_public_reply_at && t.created_at) {
        const diffMin = Math.max(0, Math.round((new Date(t.first_public_reply_at) - new Date(t.created_at)) / 60000));
        waitStr = diffMin > 60 ? `${Math.floor(diffMin / 60)}h ${diffMin % 60}m` : `${diffMin} min`;
      } else if (t.resolved_at && t.created_at) {
        const diffMin = Math.max(0, Math.round((new Date(t.resolved_at) - new Date(t.created_at)) / 60000));
        waitStr = diffMin > 60 ? `${Math.floor(diffMin / 60)}h ${diffMin % 60}m` : `${diffMin} min`;
      }
    } else {
      const refTime = t.last_customer_message_at ? new Date(t.last_customer_message_at) : (t.created_at ? new Date(t.created_at) : new Date());
      const diffMin = Math.max(1, Math.round((Date.now() - refTime.getTime()) / 60000));
      waitStr = diffMin > 60 ? `${Math.floor(diffMin / 60)}h ${diffMin % 60}m` : `${diffMin} min`;
    }

    const priority = t.priority || '—';
    const nativePriorityLabels = { none: 'Nenhuma', low: 'Baixa', medium: 'Média', high: 'Alta', urgent: 'Urgente' };
    const nativePriority = nativePriorityLabels[t.chatwoot_native_priority] || nativePriorityLabels.none;
    const isResolved = t.status === 'resolved';
    const resType = t.resolution_type === 'inactivity_3d' ? 'INATIVIDADE (3D)' : (t.resolution_type === 'bot_auto' ? 'BOT' : 'RESOLVIDO (MANUAL)');
    const statusLabel = isResolved ? resType : (t.queue_state === 'waiting_customer' ? 'AGUARDANDO USUÁRIA' : 'AGUARDANDO PLINQ');
    const statusBg = isResolved
      ? (t.resolution_type === 'inactivity_3d' ? 'background: rgba(245,158,11,0.15); color: var(--accent-yellow); border-color: var(--accent-yellow);' : 'background: rgba(52,211,153,0.15); color: var(--accent-green); border-color: var(--accent-green);')
      : (t.queue_state === 'waiting_customer' ? 'background: rgba(147,51,234,0.15); color: var(--accent-purple); border-color: var(--accent-purple);' : 'background: rgba(248,113,113,0.15); color: var(--accent-red); border-color: var(--accent-red);');

    const convId = escapeHtml(rawConvId);
    const customerName = escapeHtml(rawCustomerName);
    const channel = escapeHtml(rawChannel);
    const safePriority = escapeHtml(priority);
    const safeNativePriority = escapeHtml(nativePriority);
    const safeStatusLabel = escapeHtml(statusLabel);
    const safeWaitStr = escapeHtml(waitStr);
    const safeUrlConvId = encodeURIComponent(rawConvId);

    return `
      <tr>
        <td><strong>#${convId}</strong></td>
        <td><strong style="color: var(--text-primary);">${customerName}</strong></td>
        <td>${channel}</td>
        <td>${escapeHtml(createdAt)}</td>
        <td><span style="color: ${priority === 'P0' ? 'var(--accent-red)' : 'var(--text-primary)'}">${safeWaitStr}</span></td>
        <td>
          <span class="badge ${priority === 'P0' ? 'badge-warning' : ''}">${safePriority}</span>
          <div style="font-size: 0.7rem; color: var(--text-muted); margin-top: 0.2rem;">Chatwoot: ${safeNativePriority}</div>
        </td>
        <td><span class="badge" style="${statusBg}">${safeStatusLabel}</span></td>
        <td>
          <a href="https://app.digi2b.com/app/accounts/88/conversations/${safeUrlConvId}" target="_blank" rel="noopener noreferrer" style="color: var(--accent-blue); text-decoration: none; font-weight: 600;">
            Abrir no Chatwoot (${convId}) &rarr;
          </a>
        </td>
      </tr>
    `;
  }).join("");
}

function closeDrilldownModal() {
  document.getElementById("drilldown-modal").style.display = "none";
}

// =============================================================================
// 7. RS-14: Notas Qualitativas — Armazenamento Local Seguro (Read-Only)
// =============================================================================
function currentIsoWeekRange() {
  const now = new Date();
  const day = now.getDay() === 0 ? 7 : now.getDay(); // 1=Mon..7=Sun
  const monday = new Date(now); monday.setDate(now.getDate() - (day - 1));
  const sunday = new Date(monday); sunday.setDate(monday.getDate() + 6);
  const fmt = (d) => d.toISOString().slice(0, 10);
  return { week_start: fmt(monday), week_end: fmt(sunday) };
}

function loadSavedQualitativeNotes() {
  const { week_start, week_end } = currentIsoWeekRange();
  const storageKey = `plinq_rs14_notes_${week_start}_${week_end}`;
  try {
    const raw = localStorage.getItem(storageKey);
    if (raw) {
      const data = JSON.parse(raw);
      if (data?.qualitative_notes) {
        if (document.getElementById("rs14-block1")) document.getElementById("rs14-block1").value = data.qualitative_notes.recorrencias_fora_do_suporte || '';
        if (document.getElementById("rs14-block2")) document.getElementById("rs14-block2").value = data.qualitative_notes.caso_improviso || '';
        if (document.getElementById("rs14-block3")) document.getElementById("rs14-block3").value = data.qualitative_notes.frase_desalinhada || '';
      }
    }
  } catch (e) {
    console.warn("Erro ao recuperar notas do localStorage:", e);
  }
}

async function saveQualitativeNotes(evt) {
  const btn = evt?.target;
  const b1 = document.getElementById("rs14-block1").value;
  const b2 = document.getElementById("rs14-block2").value;
  const b3 = document.getElementById("rs14-block3").value;
  const { week_start, week_end } = currentIsoWeekRange();

  if (btn) { btn.disabled = true; btn.innerText = "Salvando..."; }

  const storageKey = `plinq_rs14_notes_${week_start}_${week_end}`;
  const payload = {
    week_start, week_end,
    qualitative_notes: {
      recorrencias_fora_do_suporte: b1,
      caso_improviso: b2,
      frase_desalinhada: b3
    },
    saved_at: new Date().toISOString()
  };

  try {
    localStorage.setItem(storageKey, JSON.stringify(payload));
  } catch (err) {
    console.error("Erro ao salvar localmente:", err);
  }

  if (btn) { btn.disabled = false; btn.innerText = "Salvar Anotações Executivas"; }
  alert(`Notas da semana ${week_start} a ${week_end} salvas no navegador com sucesso.\n(O Dashboard opera com chaves estritamente Read-Only para proteção de dados).`);
}

// =============================================================================
// Initial Loading
// =============================================================================
document.addEventListener("DOMContentLoaded", async () => {
  if (!SUPABASE_URL || !SUPABASE_KEY) {
    console.warn("⚠️ Credenciais do Supabase ausentes em window.APP_CONFIG. Configure SUPABASE_URL e SUPABASE_ANON_KEY.");
    const headerStatus = document.querySelector(".header-status");
    if (headerStatus) {
      const banner = document.createElement("div");
      banner.style.cssText = "background: rgba(248, 113, 113, 0.15); border: 1px solid var(--accent-red); color: var(--accent-red); padding: 0.4rem 0.8rem; border-radius: 8px; font-size: 0.8rem; font-weight: 600;";
      banner.innerText = "⚠️ Supabase não configurado (.env ou Vercel Environment Variables)";
      headerStatus.prepend(banner);
    }
    return;
  }
  // Inicializa datas e restrição de data máxima (hoje) nos inputs customizados
  const today = getBrtTodayDate();
  const todayIso = toIsoDate(today);
  const inStart = document.getElementById('filter-date-start');
  const inEnd = document.getElementById('filter-date-end');
  if (inStart) inStart.max = todayIso;
  if (inEnd) inEnd.max = todayIso;

  const d30 = new Date(today);
  d30.setDate(today.getDate() - 30);
  const d30Str = toIsoDate(d30);
  const labelEl = document.getElementById('date-picker-label');
  if (labelEl) labelEl.innerText = `Últimos 30 Dias (${formatDateBRShort(d30Str)} a ${formatDateBRShort(todayIso)})`;
  updatePeriodBadges(`Últimos 30 Dias (${formatDateBR(d30Str)} a ${formatDateBR(todayIso)})`);

  loadSavedQualitativeNotes();
  initStaticFilters();
  await Promise.all([loadInboxDirectory(), loadAgentDirectory(), loadTeamDirectory(), loadTagDirectory()]);
  updateDashboard();
  setInterval(updateDashboard, 30000);
});
