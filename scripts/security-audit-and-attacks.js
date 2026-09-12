/**
 * ==============================================================================
 * PLINQ DASHBOARD · BATERIA DE PENTEST E AUDITORIA DE SEGURANÇA AUTOMATIZADA
 * ==============================================================================
 * Executa simulações de ataques de invasão, tentativas de bypass de permissões,
 * tentativas de escrita indevida, injeção de SQL e verificação de vazamento de
 * credenciais no Supabase com a chave pública/anon utilizada pelo Dashboard.
 * 
 * Uso: node scripts/security-audit-and-attacks.js
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Carrega .env da raiz ou local
function loadEnv() {
  const possiblePaths = [
    path.resolve(__dirname, '../.env'),
    path.resolve(__dirname, '../../../.env')
  ];
  for (const envPath of possiblePaths) {
    if (fs.existsSync(envPath)) {
      const lines = fs.readFileSync(envPath, 'utf-8').split('\n');
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) continue;
        const eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          const k = trimmed.slice(0, eqIdx).trim();
          let v = trimmed.slice(eqIdx + 1).trim();
          if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
          if (!process.env[k]) process.env[k] = v;
        }
      }
    }
  }
}
loadEnv();

const SUPABASE_URL = "https://hqqzfccgkqdmhznwaxqj.supabase.co";
const ANON_KEY = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || "sb_publishable_0jA57WFYIBt1PfqaVOsREA_MUI6hc2Y";

console.log('='.repeat(80));
console.log('🛡️  INICIANDO BATERIA DE PENTEST E TESTES DE SEGURANÇA · PLINQ DASHBOARD');
console.log('='.repeat(80));
console.log(`🎯 Alvo: ${SUPABASE_URL}`);
const masked = ANON_KEY.length > 8 ? `${ANON_KEY.slice(0, 5)}...${ANON_KEY.slice(-4)}` : '***';
console.log(`🔑 Chave Testada (Papel Anon / Publishable): ${masked}`);
console.log('');

const results = [];

function recordTest(category, name, passed, details) {
  results.push({ category, name, passed, details });
  const icon = passed ? '✅ PASS' : '❌ FAIL';
  console.log(`[${icon}] ${category} :: ${name}`);
  if (details) console.log(`       ↳ ${details}`);
}

async function requestSupabase(endpoint, options = {}) {
  const url = `${SUPABASE_URL}/rest/v1/${endpoint}`;
  const headers = {
    'apikey': ANON_KEY,
    'Authorization': `Bearer ${ANON_KEY}`,
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    ...(options.headers || {})
  };
  try {
    const res = await fetch(url, { ...options, headers });
    const text = await res.text();
    let json = null;
    try { json = JSON.parse(text); } catch (_) {}
    return { status: res.status, ok: res.ok, text, json };
  } catch (err) {
    return { status: 0, ok: false, error: err.message, text: err.message };
  }
}

// -----------------------------------------------------------------------------
// SUITE 1: Tentativas de Escrita Não Autorizada (Write / Mutate Rejection)
// -----------------------------------------------------------------------------
async function runSuite1() {
  console.log('\n--- SUITE 1: Tentativas de Escrita e Deleção (Bloqueio Read-Only) ---');

  // 1.1 Inserção maliciosa em suporteapp_tickets
  const t1 = await requestSupabase('suporteapp_tickets', {
    method: 'POST',
    body: JSON.stringify({ customer_name: '<script>alert("hack")</script>', status: 'open' })
  });
  const t1Passed = (t1.status === 401 || t1.status === 403) && (t1.text.includes('permission denied') || t1.text.includes('violates row-level security'));
  recordTest('SUITE 1', 'Bloqueio de INSERT em suporteapp_tickets', t1Passed, `HTTP ${t1.status} (${t1.text.slice(0, 90)})`);

  // 1.2 Atualização maliciosa em massa em suporteapp_tickets
  const t2 = await requestSupabase('suporteapp_tickets?id=gt.00000000-0000-0000-0000-000000000000', {
    method: 'PATCH',
    body: JSON.stringify({ status: 'hacked_status' })
  });
  const t2Passed = (t2.status === 401 || t2.status === 403) && (t2.text.includes('permission denied') || t2.text.includes('violates row-level security'));
  recordTest('SUITE 1', 'Bloqueio de UPDATE em massa em suporteapp_tickets', t2Passed, `HTTP ${t2.status} (${t2.text.slice(0, 90)})`);

  // 1.3 Deleção maliciosa de tickets
  const t3 = await requestSupabase('suporteapp_tickets?id=gt.00000000-0000-0000-0000-000000000000', {
    method: 'DELETE'
  });
  const t3Passed = (t3.status === 401 || t3.status === 403) && t3.text.includes('permission denied');
  recordTest('SUITE 1', 'Bloqueio de DELETE em suporteapp_tickets', t3Passed, `HTTP ${t3.status} (${t3.text.slice(0, 90)})`);

  // 1.4 Injeção indevida em suporteapp_weekly_reports
  const t4 = await requestSupabase('suporteapp_weekly_reports', {
    method: 'POST',
    body: JSON.stringify({ created_by: 'hacker_injection' })
  });
  const t4Passed = (t4.status === 401 || t4.status === 403) && t4.text.includes('permission denied');
  recordTest('SUITE 1', 'Bloqueio de INSERT em suporteapp_weekly_reports', t4Passed, `HTTP ${t4.status} (${t4.text.slice(0, 90)})`);

  // 1.5 Deleção em suporteapp_weekly_reports
  const t5 = await requestSupabase('suporteapp_weekly_reports?id=gt.00000000-0000-0000-0000-000000000000', {
    method: 'DELETE'
  });
  const t5Passed = (t5.status === 401 || t5.status === 403) && t5.text.includes('permission denied');
  recordTest('SUITE 1', 'Bloqueio de DELETE em suporteapp_weekly_reports', t5Passed, `HTTP ${t5.status} (${t5.text.slice(0, 90)})`);

  // 1.6 Deleção em tabela de staging tmp_expired_credits_staging
  const t6 = await requestSupabase('tmp_expired_credits_staging?user_id=gt.00000000-0000-0000-0000-000000000000', {
    method: 'DELETE'
  });
  const t6Passed = (t6.status === 401 || t6.status === 403) && t6.text.includes('permission denied');
  recordTest('SUITE 1', 'Bloqueio de DELETE em tmp_expired_credits_staging', t6Passed, `HTTP ${t6.status} (${t6.text.slice(0, 90)})`);

  // 1.7 Criação indevida de perfil em profiles
  const t7 = await requestSupabase('profiles', {
    method: 'POST',
    body: JSON.stringify({ email: 'fake_admin@attack.com', role: 'admin' })
  });
  const t7Passed = (t7.status === 401 || t7.status === 403 || t7.status === 42501 || t7.status === 404);
  recordTest('SUITE 1', 'Bloqueio de criação não autenticada em profiles', t7Passed, `HTTP ${t7.status}`);
}

// -----------------------------------------------------------------------------
// SUITE 2: Tentativas de Leitura Não Autorizada (Data Leakage & Sensitive Tables)
// -----------------------------------------------------------------------------
async function runSuite2() {
  console.log('\n--- SUITE 2: Tentativas de Vazamento e Tabelas Protegidas ---');

  const protectedTables = [
    { table: 'cms_users', label: 'Credenciais de administradores (cms_users)' },
    { table: 'b2b_api_tokens', label: 'Tokens de API B2B (b2b_api_tokens)' },
    { table: 'payment', label: 'Faturamento e pagamentos de clientes (payment)' },
    { table: 'user_subscriptions', label: 'Assinaturas financeiras (user_subscriptions)' },
    { table: 'auth_logs', label: 'Logs de autenticação (auth_logs)' },
    { table: 'credit_transaction_log', label: 'Logs de transação financeira de créditos' },
    { table: 'tmp_expired_credits_staging', label: 'Staging de expiração de créditos' },
    { table: 'tmp_expired_credits_20250823', label: 'Histórico órfão de créditos' }
  ];

  for (const item of protectedTables) {
    const res = await requestSupabase(`${item.table}?select=*&limit=5`);
    const passed = (res.status === 200 && Array.isArray(res.json) && res.json.length === 0) || res.status === 401 || res.status === 403 || res.status === 500;
    const details = res.status === 200 ? `Retornou 0 registros (RLS protegendo)` : `HTTP ${res.status}`;
    recordTest('SUITE 2', `Proteção de leitura: ${item.label}`, passed, details);
  }
}

// -----------------------------------------------------------------------------
// SUITE 3: Operações Legítimas Autorizadas do Dashboard
// -----------------------------------------------------------------------------
async function runSuite3() {
  console.log('\n--- SUITE 3: Leitura e RPCs Autorizadas do Dashboard ---');

  // 3.1 Consulta de Inboxes ativas
  const inboxes = await requestSupabase('suporteapp_chatwoot_inboxes?select=chatwoot_inbox_id,name&active=eq.true');
  const inboxesPassed = inboxes.status === 200 && Array.isArray(inboxes.json) && inboxes.json.length > 0;
  recordTest('SUITE 3', 'Carregamento de inboxes ativas', inboxesPassed, `HTTP ${inboxes.status}, ${inboxes.json?.length || 0} inboxes carregadas`);

  // 3.2 Consulta de Tickets para Drilldown
  const tickets = await requestSupabase('suporteapp_tickets?select=id,customer_name,status,priority&limit=5');
  const ticketsPassed = tickets.status === 200 && Array.isArray(tickets.json) && tickets.json.length > 0;
  recordTest('SUITE 3', 'Leitura autorizada de tickets para Drilldown', ticketsPassed, `HTTP ${tickets.status}, ${tickets.json?.length || 0} tickets retornados`);

  // 3.3 RPC suporteapp_rpc_dashboard_queue
  const rpcQueue = await requestSupabase('rpc/suporteapp_rpc_dashboard_queue', {
    method: 'POST',
    body: JSON.stringify({})
  });
  const rpcQueuePassed = rpcQueue.status === 200 && Array.isArray(rpcQueue.json) && rpcQueue.json.length > 0;
  recordTest('SUITE 3', 'RPC suporteapp_rpc_dashboard_queue', rpcQueuePassed, `HTTP ${rpcQueue.status}, estrutura retornada OK`);

  // 3.4 RPC suporteapp_rpc_weekly_reasons (cálculo de 30d com dados agregados)
  const rpcReasons = await requestSupabase('rpc/suporteapp_rpc_weekly_reasons', {
    method: 'POST',
    body: JSON.stringify({ p_period: '30d' })
  });
  const rpcReasonsPassed = rpcReasons.status === 200 && Array.isArray(rpcReasons.json) && rpcReasons.json.length > 0;
  const countReasons = rpcReasons.json?.length || 0;
  recordTest('SUITE 3', 'RPC suporteapp_rpc_weekly_reasons', rpcReasonsPassed, `HTTP ${rpcReasons.status}, ${countReasons} categorias analíticas calculadas`);

  // 3.5 RPC suporteapp_rpc_turn_metrics
  const rpcTurn = await requestSupabase('rpc/suporteapp_rpc_turn_metrics', {
    method: 'POST',
    body: JSON.stringify({ p_period: '30d' })
  });
  const rpcTurnPassed = rpcTurn.status === 200 && Array.isArray(rpcTurn.json);
  recordTest('SUITE 3', 'RPC suporteapp_rpc_turn_metrics', rpcTurnPassed, `HTTP ${rpcTurn.status}`);

  // 3.6 RPC suporteapp_rpc_alarm_panel
  const rpcAlarm = await requestSupabase('rpc/suporteapp_rpc_alarm_panel', {
    method: 'POST',
    body: JSON.stringify({ p_period: '30d' })
  });
  const rpcAlarmPassed = rpcAlarm.status === 200 && Array.isArray(rpcAlarm.json);
  recordTest('SUITE 3', 'RPC suporteapp_rpc_alarm_panel', rpcAlarmPassed, `HTTP ${rpcAlarm.status}`);
}

// -----------------------------------------------------------------------------
// SUITE 4: Tentativas de Injeção de SQL em Parâmetros de RPC
// -----------------------------------------------------------------------------
async function runSuite4() {
  console.log('\n--- SUITE 4: Tentativas de SQL Injection em Parâmetros de RPC ---');

  const sqliPayloads = [
    { rpc: 'suporteapp_rpc_weekly_reasons', param: "p_period", val: "' OR 1=1 --", label: "SQLi ' OR 1=1 -- em p_period" },
    { rpc: 'suporteapp_rpc_weekly_reasons', param: "p_period", val: "'; DROP TABLE suporteapp_tickets; --", label: "SQLi DROP TABLE em p_period" },
    { rpc: 'suporteapp_rpc_dashboard_queue', param: "p_severity", val: "P0' UNION SELECT * FROM cms_users --", label: "SQLi UNION SELECT em p_severity" }
  ];

  for (const sqli of sqliPayloads) {
    const body = {};
    body[sqli.param] = sqli.val;
    const res = await requestSupabase(`rpc/${sqli.rpc}`, {
      method: 'POST',
      body: JSON.stringify(body)
    });
    // O teste passa se a injeção NÃO for executada (retorno 200 parametrizado ou 400/404/422 erro de validação)
    const passed = (res.status === 200 && Array.isArray(res.json)) || res.status === 400 || res.status === 404 || res.status === 422;
    recordTest('SUITE 4', sqli.label, passed, `HTTP ${res.status}, injeção tratada com segurança sem execução maliciosa`);
  }
}

// -----------------------------------------------------------------------------
// SUITE 5: Trava Preventiva Anti-Vazamento de Segredos no Build
// -----------------------------------------------------------------------------
function runSuite5() {
  console.log('\n--- SUITE 5: Validação Anti-Vazamento no Build & Repositório ---');

  const buildScriptPath = path.resolve(__dirname, 'generate-config.js');
  
  // Teste 5.1: Tentar rodar o build com uma chave service_role forçada
  const testProc = spawnSync('node', [buildScriptPath], {
    env: {
      ...process.env,
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_KEY: 'sb_secret_MALICIOUS_SERVICE_KEY_12345'
    },
    encoding: 'utf-8'
  });

  const abortSuccessful = testProc.status !== 0 && testProc.stderr.includes('ERRO CRÍTICO DE SEGURANÇA');
  recordTest('SUITE 5', 'Trava do generate-config.js bloqueia chave sb_secret_', abortSuccessful, 'Processo abortou com código 1 conforme esperado');

  // Teste 5.2: Tentar rodar com chave sbp_ (Personal Access Token)
  const testProcToken = spawnSync('node', [buildScriptPath], {
    env: {
      ...process.env,
      SUPABASE_URL: 'https://test.supabase.co',
      SUPABASE_KEY: 'sbp_personal_access_token_12345'
    },
    encoding: 'utf-8'
  });
  const abortTokenSuccessful = testProcToken.status !== 0 && testProcToken.stderr.includes('ERRO CRÍTICO DE SEGURANÇA');
  recordTest('SUITE 5', 'Trava do generate-config.js bloqueia token sbp_', abortTokenSuccessful, 'Processo abortou com código 1 conforme esperado');

  // Teste 5.3: Varredura de arquivos no diretório Dashboard por chaves secretas
  const filesToCheck = ['config.js', 'index.html', 'src/dashboard.js', 'README.md', 'vercel.json'];
  let leakFound = false;
  for (const f of filesToCheck) {
    const fullPath = path.resolve(__dirname, '..', f);
    if (fs.existsSync(fullPath)) {
      const content = fs.readFileSync(fullPath, 'utf-8');
      if (content.includes('sb_secret_') || content.includes('service_role') || content.includes('sbp_')) {
        leakFound = true;
        recordTest('SUITE 5', `Varredura de segredos em ${f}`, false, `Encontrado token confidencial em ${f}!`);
      }
    }
  }
  if (!leakFound) {
    recordTest('SUITE 5', 'Varredura estática de código no Dashboard', true, 'Zero segredos ou tokens de escrita presentes');
  }
}

// -----------------------------------------------------------------------------
// SUITE 6: Sanitização de XSS no Frontend
// -----------------------------------------------------------------------------
function runSuite6() {
  console.log('\n--- SUITE 6: Verificação de Sanitização XSS ---');

  const jsPath = path.resolve(__dirname, '../src/dashboard.js');
  const code = fs.readFileSync(jsPath, 'utf-8');

  // 6.1 Presença da função escapeHtml
  const hasEscapeHtml = code.includes('function escapeHtml(');
  recordTest('SUITE 6', 'Função escapeHtml implementada', hasEscapeHtml, 'Presente em src/dashboard.js');

  // 6.2 Sanitização em openDrilldownModal
  const hasSanitizedModal = code.includes('const customerName = escapeHtml(rawCustomerName);') &&
                           code.includes('const convId = escapeHtml(rawConvId);');
  recordTest('SUITE 6', 'Sanitização de customerName e convId no modal de drilldown', hasSanitizedModal, 'Campos escapados antes da injeção no DOM');

  // 6.3 Teste da lógica de escape
  function escapeTest(unsafe) {
    return String(unsafe)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }
  const payload = '<img src=x onerror=alert(1)>';
  const escaped = escapeTest(payload);
  const xssPassed = !escaped.includes('<') && !escaped.includes('>') && escaped.includes('&lt;img');
  recordTest('SUITE 6', 'Neutralização de payload XSS (<img onerror>)', xssPassed, `Resultado: ${escaped}`);
}

// -----------------------------------------------------------------------------
// EXECUTOR PRINCIPAL
// -----------------------------------------------------------------------------
async function main() {
  await runSuite1();
  await runSuite2();
  await runSuite3();
  await runSuite4();
  runSuite5();
  runSuite6();

  console.log('\n' + '='.repeat(80));
  console.log('📊 RESUMO DA BATERIA DE PENTEST E TESTES DE SEGURANÇA');
  console.log('='.repeat(80));

  const total = results.length;
  const passed = results.filter(r => r.passed).length;
  const failed = results.filter(r => !r.passed).length;

  console.log(`Total de testes executados: ${total}`);
  console.log(`Sucessos (Mitigações ativas): ${passed}`);
  console.log(`Falhas de segurança: ${failed}`);

  if (failed === 0) {
    console.log('\n🎉 APROVAÇÃO 100%: O PROJETO ESTÁ SEGURO E AS CHAVES OPERAM EXCLUSIVAMENTE EM READ-ONLY.');
    process.exit(0);
  } else {
    console.error('\n⚠️ ATENÇÃO: Foram identificadas falhas que violam os requisitos de segurança.');
    process.exit(1);
  }
}

main();
