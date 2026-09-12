/**
 * Script de Geração de Configuração Dinâmica para Vercel / CI / Local
 * Lê as variáveis de ambiente SUPABASE_URL e SUPABASE_ANON_KEY (ou SUPABASE_KEY)
 * e gera o arquivo config.js para consumo no frontend.
 * 
 * Executado automaticamente pelo comando "npm run build" na Vercel.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// 1. Tenta carregar variáveis de um arquivo .env local se existir
function loadEnvFile() {
  const envPath = path.resolve(__dirname, '../.env');
  if (fs.existsSync(envPath)) {
    const lines = fs.readFileSync(envPath, 'utf-8').split('\n');
    lines.forEach(line => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return;
      const equalsIdx = trimmed.indexOf('=');
      if (equalsIdx > 0) {
        const key = trimmed.slice(0, equalsIdx).trim();
        let val = trimmed.slice(equalsIdx + 1).trim();
        if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
          val = val.slice(1, -1);
        }
        if (!process.env[key]) {
          process.env[key] = val;
        }
      }
    });
  }
}

loadEnvFile();

// 2. Resolve URL e Chave Anon a partir do ambiente (sem tokens embutidos no código)
const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || process.env.SUPABASE_KEY || "";

function isSecretKey(k) {
  if (!k || typeof k !== 'string') return false;
  return k.startsWith('sb_secret_') || k.includes('service_role') || k.startsWith('sbp_');
}

// Trava Preventiva de Segurança: Aborta o build se uma chave privilegiada/secreta for detectada em qualquer variável
if (isSecretKey(process.env.SUPABASE_ANON_KEY) || isSecretKey(process.env.SUPABASE_KEY) || isSecretKey(SUPABASE_KEY)) {
  console.error('\n🚨 [ERRO CRÍTICO DE SEGURANÇA] Tentativa de compilar o frontend com chave secreta/privilegiada!');
  console.error('👉 O Dashboard DEVE utilizar exclusivamente a chave pública/anon ("SUPABASE_ANON_KEY" ou "sb_publishable_...").');
  console.error('👉 Remova o token de serviço (.env ou Vercel Environment Variables) e use a chave de leitura pública.\n');
  process.exit(1);
}

const configContent = `/**
 * Configuração de Runtime Gerada Automaticamente
 * Gerado em: ${new Date().toISOString()}
 * Não altere diretamente. Configure via Environment Variables (.env ou Vercel).
 */
window.APP_CONFIG = {
  SUPABASE_URL: ${JSON.stringify(SUPABASE_URL)},
  SUPABASE_KEY: ${JSON.stringify(SUPABASE_KEY)}
};
`;

const outputPath = path.resolve(__dirname, '../config.js');
fs.writeFileSync(outputPath, configContent, 'utf-8');

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.warn('⚠️ [build] AVISO: SUPABASE_URL ou SUPABASE_ANON_KEY não foram informadas.');
  console.warn('👉 Configure-as nas Environment Variables da Vercel ou no arquivo .env local.');
} else {
  console.log('✅ [build] config.js gerado com sucesso!');
  console.log(`ℹ️ [build] SUPABASE_URL: ${SUPABASE_URL}`);
  const maskedKey = SUPABASE_KEY.length > 8 ? `${SUPABASE_KEY.slice(0, 4)}...${SUPABASE_KEY.slice(-4)}` : '***';
  console.log(`ℹ️ [build] SUPABASE_KEY: [OCULTO] (${maskedKey})`);
}
