-- L3 Contato da Conversa (2026-10-02)
-- 1) suporteapp_contacts: company_id (empresa nativa do Chatwoot), blocked, whatsapp_username.
-- 2) suporteapp_chatwoot_companies: espelho das empresas do Chatwoot (RLS, sem anon) + RPC de sincronização.
-- 3) suporteapp_sync_contacts v2 (mesma assinatura): grava os 3 campos novos e mantém contact_name/contact_email
--    do snapshot. A lógica de fusão de pessoas/identificadores NÃO muda.
-- 4) Preenchimento único de contact_name/contact_email do snapshot a partir dos contatos.
-- Segurança: contatos e empresas são PII/dado comercial — RLS ligada, REVOKE para anon/authenticated, só service_role.

ALTER TABLE public.suporteapp_contacts
  ADD COLUMN IF NOT EXISTS company_id        bigint,
  ADD COLUMN IF NOT EXISTS blocked           boolean,
  ADD COLUMN IF NOT EXISTS whatsapp_username text;
COMMENT ON COLUMN public.suporteapp_contacts.company_id IS 'company_id do contato no Chatwoot (empresa nativa; ver suporteapp_chatwoot_companies). Sem FK de propósito: o contato pode chegar antes da empresa ser sincronizada (6 h).';

CREATE TABLE IF NOT EXISTS public.suporteapp_chatwoot_companies (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  chatwoot_account_id  integer NOT NULL DEFAULT 88,
  chatwoot_company_id  bigint  NOT NULL,
  name                 text,
  domain               text,
  description          text,
  contacts_count       integer,
  custom_attributes    jsonb   NOT NULL DEFAULT '{}'::jsonb,
  chatwoot_created_at  timestamptz,
  active               boolean NOT NULL DEFAULT true,
  last_synced_at       timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  aplicacao            text,
  n8n_workflow         text,
  n8n_execution        text,
  CONSTRAINT suporteapp_chatwoot_companies_n8n_audit_chk
    CHECK (aplicacao <> 'n8n' OR (n8n_workflow IS NOT NULL AND n8n_execution IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uidx_suporteapp_chatwoot_companies
  ON public.suporteapp_chatwoot_companies (chatwoot_account_id, chatwoot_company_id);
ALTER TABLE public.suporteapp_chatwoot_companies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.suporteapp_chatwoot_companies FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.suporteapp_chatwoot_companies IS
  'Espelho das empresas (organizações) do Chatwoot. active=false quando some do Chatwoot; nunca apaga. Sem acesso anon.';

-- sincronização das empresas: lista completa (todas as páginas). Lista vazia NUNCA desativa nada.
CREATE OR REPLACE FUNCTION public.suporteapp_sync_chatwoot_companies(
  p_items jsonb, p_n8n_workflow text, p_n8n_execution text, p_chatwoot_account_id integer DEFAULT 88)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_recebidas int := 0; v_desativadas int := 0; v_ids bigint[];
BEGIN
  SELECT COALESCE(array_agg(DISTINCT (e ->> 'id')::bigint), ARRAY[]::bigint[]) INTO v_ids
    FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb)) e WHERE e ->> 'id' IS NOT NULL;
  v_recebidas := COALESCE(array_length(v_ids, 1), 0);
  IF v_recebidas = 0 THEN
    RETURN jsonb_build_object('recebidas', 0, 'desativadas', 0, 'aviso', 'lista vazia: nada alterado');
  END IF;

  INSERT INTO public.suporteapp_chatwoot_companies AS c
    (chatwoot_account_id, chatwoot_company_id, name, domain, description, contacts_count, custom_attributes,
     chatwoot_created_at, active, last_synced_at, aplicacao, n8n_workflow, n8n_execution)
  SELECT p_chatwoot_account_id, x.id, x.name, x.domain, x.description, x.contacts_count,
         COALESCE(x.custom_attributes, '{}'::jsonb), CASE WHEN x.created_at IS NULL THEN NULL ELSE to_timestamp(x.created_at) END,
         true, now(), 'n8n', p_n8n_workflow, p_n8n_execution
    FROM jsonb_to_recordset(p_items) AS x(id bigint, name text, domain text, description text, contacts_count integer,
                                          custom_attributes jsonb, created_at bigint)
   WHERE x.id IS NOT NULL
  ON CONFLICT (chatwoot_account_id, chatwoot_company_id) DO UPDATE SET
    name = EXCLUDED.name, domain = EXCLUDED.domain, description = EXCLUDED.description,
    contacts_count = EXCLUDED.contacts_count, custom_attributes = EXCLUDED.custom_attributes,
    chatwoot_created_at = COALESCE(EXCLUDED.chatwoot_created_at, c.chatwoot_created_at),
    active = true, last_synced_at = now(), updated_at = now(),
    aplicacao = 'n8n', n8n_workflow = EXCLUDED.n8n_workflow, n8n_execution = EXCLUDED.n8n_execution;

  UPDATE public.suporteapp_chatwoot_companies
     SET active = false, updated_at = now(), aplicacao = 'n8n', n8n_workflow = p_n8n_workflow, n8n_execution = p_n8n_execution
   WHERE chatwoot_account_id = p_chatwoot_account_id AND active AND NOT (chatwoot_company_id = ANY(v_ids));
  GET DIAGNOSTICS v_desativadas = ROW_COUNT;

  RETURN jsonb_build_object('recebidas', v_recebidas, 'desativadas', v_desativadas);
END;
$function$;

REVOKE ALL ON FUNCTION public.suporteapp_sync_chatwoot_companies(jsonb, text, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.suporteapp_sync_chatwoot_companies(jsonb, text, text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.suporteapp_sync_contacts(p_items jsonb, p_n8n_workflow text, p_n8n_execution text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  it record; cid bigint; c_id uuid; c_person uuid; was_new boolean;
  email_n text; phone_k text; ig text; bsu text; ident text;
  ids jsonb; iv record; matched uuid[]; survivor uuid; o uuid; cnt int; prof uuid; pn int;
  ca_email text; other uuid; a uuid; b uuid;
  v_checked int := 0; v_new_contacts int := 0; v_new_persons int := 0; v_merged int := 0; v_sugg int := 0;
BEGIN
  FOR it IN
    SELECT * FROM jsonb_to_recordset(COALESCE(p_items, '[]'::jsonb))
      AS x(conv bigint, inbox integer, channel text, at timestamptz, contact jsonb, conv_ca jsonb)
  LOOP
    v_checked := v_checked + 1;
    cid := NULLIF(it.contact ->> 'id', '')::bigint;
    IF cid IS NULL THEN CONTINUE; END IF;

    email_n := public.suporteapp_norm_email(it.contact ->> 'email');
    phone_k := public.suporteapp_norm_phone(it.contact ->> 'phone');
    ig      := lower(NULLIF(btrim(it.contact -> 'aa' ->> 'social_instagram_user_name'), ''));
    bsu     := NULLIF(btrim(it.contact ->> 'bsuid'), '');
    ident   := NULLIF(btrim(it.contact ->> 'identifier'), '');

    INSERT INTO public.suporteapp_contacts AS c
      (chatwoot_contact_id, name, email, phone, phone_key, identifier, instagram_username, bsuid,
       additional_attributes, channels, inbox_ids, first_seen_at, last_seen_at, aplicacao, n8n_workflow, n8n_execution,
       company_id, blocked, whatsapp_username)
    VALUES (cid, NULLIF(it.contact ->> 'name', ''), email_n, NULLIF(it.contact ->> 'phone', ''), phone_k, ident, ig, bsu,
            COALESCE(it.contact -> 'aa', '{}'::jsonb),
            CASE WHEN it.channel IS NULL THEN '{}' ELSE ARRAY[it.channel] END,
            CASE WHEN it.inbox IS NULL THEN '{}' ELSE ARRAY[it.inbox] END,
            COALESCE(it.at, now()), COALESCE(it.at, now()), 'n8n', p_n8n_workflow, p_n8n_execution,
            NULLIF(it.contact ->> 'company_id', '')::bigint, (it.contact ->> 'blocked')::boolean,
            NULLIF(it.contact ->> 'whatsapp_username', ''))
    ON CONFLICT (chatwoot_contact_id) DO UPDATE SET
      name = COALESCE(EXCLUDED.name, c.name),
      email = COALESCE(EXCLUDED.email, c.email),
      phone = COALESCE(EXCLUDED.phone, c.phone),
      phone_key = COALESCE(EXCLUDED.phone_key, c.phone_key),
      identifier = COALESCE(EXCLUDED.identifier, c.identifier),
      instagram_username = COALESCE(EXCLUDED.instagram_username, c.instagram_username),
      bsuid = COALESCE(EXCLUDED.bsuid, c.bsuid),
      -- L3 (2026-10-02): retrato completo do contato — chave presente (mesmo null) grava/limpa; chave ausente preserva
      company_id = CASE WHEN it.contact ? 'company_id' THEN EXCLUDED.company_id ELSE c.company_id END,
      blocked = CASE WHEN it.contact ? 'blocked' THEN EXCLUDED.blocked ELSE c.blocked END,
      whatsapp_username = CASE WHEN it.contact ? 'whatsapp_username' THEN EXCLUDED.whatsapp_username ELSE c.whatsapp_username END,
      additional_attributes = CASE WHEN EXCLUDED.additional_attributes = '{}'::jsonb THEN c.additional_attributes ELSE EXCLUDED.additional_attributes END,
      channels = (SELECT COALESCE(array_agg(DISTINCT z), '{}') FROM unnest(c.channels || EXCLUDED.channels) z),
      inbox_ids = (SELECT COALESCE(array_agg(DISTINCT z), '{}') FROM unnest(c.inbox_ids || EXCLUDED.inbox_ids) z),
      first_seen_at = LEAST(c.first_seen_at, EXCLUDED.first_seen_at),
      last_seen_at = GREATEST(c.last_seen_at, EXCLUDED.last_seen_at),
      updated_at = now(), aplicacao = 'n8n', n8n_workflow = EXCLUDED.n8n_workflow, n8n_execution = EXCLUDED.n8n_execution
    RETURNING c.id, c.person_id, (xmax = 0) INTO c_id, c_person, was_new;
    IF was_new THEN v_new_contacts := v_new_contacts + 1; END IF;

    -- L3: além do vínculo conversa->contato, mantém nome/e-mail do contato no snapshot (cópia de conveniência)
    UPDATE public.suporteapp_conversation_snapshot
       SET chatwoot_contact_id = cid,
           contact_name = COALESCE(NULLIF(it.contact ->> 'name', ''), contact_name),
           contact_email = COALESCE(NULLIF(it.contact ->> 'email', ''), contact_email)
     WHERE chatwoot_conversation_id = it.conv
       AND (chatwoot_contact_id IS DISTINCT FROM cid
            OR contact_name IS DISTINCT FROM COALESCE(NULLIF(it.contact ->> 'name', ''), contact_name)
            OR contact_email IS DISTINCT FROM COALESCE(NULLIF(it.contact ->> 'email', ''), contact_email));

    -- identificadores de confiança alta (campos do próprio contato)
    ids := jsonb_build_array(
      jsonb_build_object('k','email','v',email_n), jsonb_build_object('k','phone','v',phone_k),
      jsonb_build_object('k','instagram','v',ig),  jsonb_build_object('k','bsuid','v',bsu),
      jsonb_build_object('k','identifier','v',ident));
    matched := ARRAY[]::uuid[];
    FOR iv IN SELECT e ->> 'k' AS k, e ->> 'v' AS v FROM jsonb_array_elements(ids) e WHERE e ->> 'v' IS NOT NULL LOOP
      INSERT INTO public.suporteapp_contact_identifiers (contact_id, kind, value, confidence, source)
      VALUES (c_id, iv.k, iv.v, 'alta', 'contato') ON CONFLICT (contact_id, kind, value) DO NOTHING;

      SELECT count(DISTINCT i.contact_id) INTO cnt FROM public.suporteapp_contact_identifiers i
       WHERE i.kind = iv.k AND i.value = iv.v AND i.confidence = 'alta';
      IF cnt >= 5 THEN CONTINUE; END IF;                                   -- ambíguo: não funde
      matched := matched || ARRAY(
        SELECT DISTINCT c2.person_id FROM public.suporteapp_contact_identifiers i
          JOIN public.suporteapp_contacts c2 ON c2.id = i.contact_id
         WHERE i.kind = iv.k AND i.value = iv.v AND i.confidence = 'alta'
           AND c2.id <> c_id AND c2.person_id IS NOT NULL);
    END LOOP;
    IF c_person IS NOT NULL THEN matched := matched || c_person; END IF;

    IF array_length(matched, 1) IS NULL THEN
      INSERT INTO public.suporteapp_persons (display_name, aplicacao, n8n_workflow, n8n_execution)
      VALUES (NULLIF(it.contact ->> 'name', ''), 'n8n', p_n8n_workflow, p_n8n_execution) RETURNING id INTO survivor;
      v_new_persons := v_new_persons + 1;
    ELSE
      SELECT p.id INTO survivor FROM public.suporteapp_persons p WHERE p.id = ANY(matched) ORDER BY p.created_at, p.id LIMIT 1;
      FOR o IN SELECT DISTINCT m FROM unnest(matched) m WHERE m <> survivor LOOP
        PERFORM public.suporteapp_merge_persons(survivor, o, 'identificador_forte_em_comum');
        v_merged := v_merged + 1;
      END LOOP;
    END IF;
    UPDATE public.suporteapp_contacts SET person_id = survivor WHERE id = c_id AND person_id IS DISTINCT FROM survivor;
    UPDATE public.suporteapp_persons SET display_name = COALESCE(display_name, NULLIF(it.contact ->> 'name', '')), updated_at = now()
     WHERE id = survivor AND display_name IS NULL;

    -- vínculo com o usuário Plinq (perfil): e-mail ou telefone, só se houver exatamente 1 perfil
    IF email_n IS NOT NULL THEN
      SELECT count(*), min(pr.id::text)::uuid INTO pn, prof FROM public.profiles pr WHERE lower(pr.email) = email_n;
      IF pn = 1 THEN UPDATE public.suporteapp_persons SET plinq_user_id = COALESCE(plinq_user_id, prof) WHERE id = survivor; END IF;
    END IF;
    IF phone_k IS NOT NULL THEN
      SELECT count(*), min(pr.id::text)::uuid INTO pn, prof FROM public.profiles pr
       WHERE public.suporteapp_norm_phone(pr.phone) = phone_k;
      IF pn = 1 THEN UPDATE public.suporteapp_persons SET plinq_user_id = COALESCE(plinq_user_id, prof) WHERE id = survivor; END IF;
    END IF;

    -- confiança média: e-mails citados nos atributos da conversa -> só SUGESTÃO, nunca fusão automática
    FOR ca_email IN
      SELECT DISTINCT e FROM (VALUES (public.suporteapp_norm_email(it.conv_ca ->> 'email_da_compra')),
                                     (public.suporteapp_norm_email(it.conv_ca ->> 'emailperfil'))) v(e) WHERE e IS NOT NULL
    LOOP
      INSERT INTO public.suporteapp_contact_identifiers (contact_id, kind, value, confidence, source)
      VALUES (c_id, 'email', ca_email, 'media', 'atributo_da_conversa') ON CONFLICT (contact_id, kind, value) DO NOTHING;
      FOR other IN
        SELECT DISTINCT c2.person_id FROM public.suporteapp_contact_identifiers i
          JOIN public.suporteapp_contacts c2 ON c2.id = i.contact_id
         WHERE i.kind = 'email' AND i.value = ca_email AND i.confidence = 'alta' AND c2.person_id <> survivor
      LOOP
        a := LEAST(survivor, other); b := GREATEST(survivor, other);
        INSERT INTO public.suporteapp_person_link_suggestions (person_a, person_b, reason, evidence)
        VALUES (a, b, 'email_em_atributo_da_conversa', jsonb_build_object('email', ca_email, 'conversa', it.conv))
        ON CONFLICT (person_a, person_b, reason) DO NOTHING;
        IF FOUND THEN v_sugg := v_sugg + 1; END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  INSERT INTO public.suporteapp_ingestion_audit (source, messages_checked, messages_recovered, detail, aplicacao, n8n_workflow, n8n_execution)
  VALUES ('sync_contatos', v_checked, 0,
          jsonb_build_object('contatos_novos', v_new_contacts, 'pessoas_novas', v_new_persons, 'fusoes', v_merged, 'sugestoes_novas', v_sugg),
          'n8n', p_n8n_workflow, p_n8n_execution);
  RETURN jsonb_build_object('checked', v_checked, 'contatos_novos', v_new_contacts, 'pessoas_novas', v_new_persons,
                            'fusoes', v_merged, 'sugestoes_novas', v_sugg);
END $function$;

-- preenchimento único: nome/e-mail do contato no snapshot onde faltam (dado local, sem API)
UPDATE public.suporteapp_conversation_snapshot s
   SET contact_name  = COALESCE(s.contact_name,  NULLIF(c.name, '')),
       contact_email = COALESCE(s.contact_email, NULLIF(c.email, ''))
  FROM public.suporteapp_contacts c
 WHERE c.chatwoot_contact_id = s.chatwoot_contact_id
   AND ((s.contact_name IS NULL AND NULLIF(c.name, '') IS NOT NULL)
     OR (s.contact_email IS NULL AND NULLIF(c.email, '') IS NOT NULL));
