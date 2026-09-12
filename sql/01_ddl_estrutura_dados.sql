-- ==============================================================================
-- CHAMADOS APP · DASHBOARD DE SUPORTE V3.0
-- Migração DDL: Tabelas de Apoio, Calendário, Mensagens Automáticas, Taxonomia e Audit Log
-- Projeto: Plinq_V1 (Supabase)
-- ==============================================================================

-- 1. Alteração da Tabela Principal de Tickets (Tipo de Resolução)
ALTER TABLE public.suporteapp_tickets
ADD COLUMN IF NOT EXISTS resolution_type TEXT CHECK (resolution_type IN ('manual', 'inactivity_3d', 'bot_auto'));

-- 2. Tabela de Calendário Comercial & Feriados (Brasil + SP 2026-2028)
CREATE TABLE IF NOT EXISTS public.suporteapp_calendar (
    calendar_date DATE PRIMARY KEY,
    is_business_day BOOLEAN NOT NULL DEFAULT true,
    start_time TIME NOT NULL DEFAULT '09:00:00',
    end_time TIME NOT NULL DEFAULT '18:00:00',
    is_holiday BOOLEAN NOT NULL DEFAULT false,
    holiday_type TEXT CHECK (holiday_type IN ('national', 'state_sp', 'city_sp', 'custom')),
    holiday_name TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index para buscas de intervalo por data
CREATE INDEX IF NOT EXISTS idx_suporteapp_calendar_biz 
ON public.suporteapp_calendar (calendar_date, is_business_day);

-- 3. Tabela de Templates de Mensagens Automáticas & Bots
CREATE TABLE IF NOT EXISTS public.suporteapp_auto_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_key TEXT NOT NULL UNIQUE,
    pattern_text TEXT NOT NULL,
    category TEXT CHECK (category IN ('greeting', 'opening', 'inactivity_closure_3d', 'broadcast')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insere os 3 templates padrão exigidos na especificação v3.0 (Anexo)
INSERT INTO public.suporteapp_auto_messages (template_key, pattern_text, category)
VALUES 
    ('greeting', 'Recebemos sua mensagem! Em breve nossa equipe irá te atender.', 'greeting'),
    ('opening', 'Olá! Seja bem-vinda ao Suporte Plinq. Como posso te ajudar hoje?', 'opening'),
    ('inactivity_closure_3d', 'Esta conversa foi encerrada automaticamente por inatividade de 3 dias.', 'inactivity_closure_3d')
ON CONFLICT (template_key) DO UPDATE 
SET pattern_text = EXCLUDED.pattern_text, category = EXCLUDED.category;

-- 4. Tabela de Taxonomia de Etiquetas (Tags & Severidade/Prioridade)
CREATE TABLE IF NOT EXISTS public.suporteapp_label_taxonomy (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    label_name TEXT NOT NULL UNIQUE,
    label_category TEXT NOT NULL CHECK (label_category IN ('severity', 'reason', 'workflow')),
    destiny_area TEXT CHECK (destiny_area IN ('engenharia', 'Gabi', 'Mariana', 'suporte_n1', 'financeiro')),
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insere a taxonomia de etiquetas padrão
INSERT INTO public.suporteapp_label_taxonomy (label_name, label_category, destiny_area, description)
VALUES
    ('sev-red', 'severity', 'suporte_n1', 'Risco Crítico / Churn / Cobrança (<15 min SLA)'),
    ('sev-yellow', 'severity', 'suporte_n1', 'Alto / Erro Acesso/Login (<1h SLA)'),
    ('sev-green', 'severity', 'suporte_n1', 'Normal / Dúvida ou Elogio'),
    ('login-acesso', 'reason', 'suporte_n1', 'Problema de Login / Senha / Acesso'),
    ('duvida-de-plano', 'reason', 'suporte_n1', 'Dúvidas funcionais sobre recursos do plano'),
    ('erro-tecnico', 'reason', 'engenharia', 'Bug no aplicativo ou erro 500'),
    ('app-fora-do-ar', 'reason', 'engenharia', 'Indisponibilidade do app'),
    ('reembolso', 'reason', 'Gabi', 'Solicitação de estorno / reembolso'),
    ('meus-dados-lgpd', 'reason', 'Mariana', 'Remoção ou solicitação LGPD'),
    ('pessoa-consultada', 'reason', 'Mariana', 'Questionamento sobre pessoa consultada'),
    ('advogado-ou-autoridade', 'reason', 'Mariana', 'Notificação judicial ou autoridade'),
    ('relatorio-contestado', 'workflow', 'suporte_n1', 'Cliente contestou dados no relatório'),
    ('falso-negativo', 'workflow', 'suporte_n1', 'Indício de falso negativo')
ON CONFLICT (label_name) DO UPDATE 
SET label_category = EXCLUDED.label_category, destiny_area = EXCLUDED.destiny_area;

-- 5. Tabela de Relatórios Semanais & Notas Qualitativas (RS-12, RS-14)
CREATE TABLE IF NOT EXISTS public.suporteapp_weekly_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    week_start DATE NOT NULL,
    week_end DATE NOT NULL,
    contested_count INT NOT NULL DEFAULT 0,
    false_negative_count INT NOT NULL DEFAULT 0,
    qualitative_notes JSONB,
    created_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_suporteapp_weekly_reports_range UNIQUE (week_start, week_end)
);

-- 6. Tabela de Log de Atividades e Rastreabilidade Completa ("QUEM FEZ" E "O QUE FEZ")
CREATE TABLE IF NOT EXISTS public.suporteapp_activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID REFERENCES public.suporteapp_tickets(id) ON DELETE CASCADE,
    chatwoot_conversation_id BIGINT NOT NULL,
    chatwoot_message_id BIGINT,
    action_type TEXT NOT NULL,
    action_description TEXT NOT NULL,
    actor_type TEXT NOT NULL CHECK (actor_type IN ('agent', 'customer', 'bot', 'system')),
    actor_id TEXT,
    actor_name TEXT,
    actor_email TEXT,
    previous_state JSONB DEFAULT '{}'::jsonb,
    new_state JSONB DEFAULT '{}'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    aplicacao TEXT NOT NULL DEFAULT 'n8n',
    n8n_workflow TEXT,
    n8n_execution TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_suporteapp_act_logs_ticket ON public.suporteapp_activity_logs(ticket_id);
CREATE INDEX IF NOT EXISTS idx_suporteapp_act_logs_conv ON public.suporteapp_activity_logs(chatwoot_conversation_id);
