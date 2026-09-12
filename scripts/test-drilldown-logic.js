/**
 * TESTE AUTOMATIZADO DA LÓGICA DE DRILLDOWN REVISADA
 */

import assert from 'assert';

// Simulação das funções do dashboard
function toIsoDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function getActiveDateRangeMock(filters, today) {
  if (filters.dateStart && filters.dateEnd) {
    const start = new Date(`${filters.dateStart}T00:00:00-03:00`);
    const [y, m, d] = filters.dateEnd.split('-').map(Number);
    const endNextDay = new Date(y, m - 1, d + 1, 0, 0, 0);
    const end = new Date(`${toIsoDate(endNextDay)}T00:00:00-03:00`);
    return { start, end };
  }
  const now = new Date();
  if (filters.period === 'today') {
    const todayIso = toIsoDate(today);
    const start = new Date(`${todayIso}T00:00:00-03:00`);
    return { start, end: now };
  }
  if (filters.period === '7d') {
    return { start: new Date(now.getTime() - 7 * 86400000), end: now };
  }
  return { start: new Date(now.getTime() - 30 * 86400000), end: now };
}

function testWaitCalculation(t) {
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
  return waitStr;
}

console.log("Iniciando testes de unidade do drill-down...");

// Teste 1: Intervalo de Hoje
const today = new Date();
const rangeToday = getActiveDateRangeMock({ period: 'today' }, today);
assert(rangeToday.start <= rangeToday.end, "Início de hoje deve ser <= fim");
console.log("✅ Teste 1: getActiveDateRange (today) OK");

// Teste 2: Intervalo Customizado
const rangeCustom = getActiveDateRangeMock({ dateStart: '2026-09-01', dateEnd: '2026-09-10' }, today);
assert(rangeCustom.start.toISOString().includes('2026-09-01'), "Start deve bater 2026-09-01");
console.log("✅ Teste 2: getActiveDateRange (custom) OK");

// Teste 3: Espera de ticket resolvido
const resolvedTicket = {
  status: 'resolved',
  created_at: '2026-09-01T10:00:00Z',
  first_public_reply_at: '2026-09-01T10:05:00Z',
  resolved_at: '2026-09-01T10:30:00Z'
};
const waitResolved = testWaitCalculation(resolvedTicket);
assert.strictEqual(waitResolved, "5 min", `Espera deve ser 5 min, mas foi ${waitResolved}`);
console.log("✅ Teste 3: Cálculo de espera para ticket resolvido não acumula dias passados");

console.log("Todos os testes de unidade do drilldown passaram com sucesso!");
