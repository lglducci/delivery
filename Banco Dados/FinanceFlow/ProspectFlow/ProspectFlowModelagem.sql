 -- ============================================================================
-- ProspectFlow - Modelagem MVP
-- PostgreSQL / Supabase
--
-- Escopo propositalmente pequeno:
--   1. prospect.leads
--   2. prospect.interacoes
--   3. prospect.mensagens
--   4. Uma funcao publica para o n8n: public.prospectflow_api(...)
--
-- O frontend usa somente um webhook chamado: prospectflow
-- ============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS prospect;

-- ----------------------------------------------------------------------------
-- TABELAS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS prospect.leads (
    id                        BIGSERIAL PRIMARY KEY,
    empresa_id                BIGINT NOT NULL,
    tipo_lead                 TEXT NOT NULL DEFAULT 'PJ'
                              CHECK (tipo_lead IN ('PF', 'PJ')),
    nome                      TEXT NOT NULL,
    empresa_nome              TEXT,
    segmento                  TEXT,
    cidade                    TEXT,
    telefone                  TEXT,
    instagram                 TEXT,
    email                     TEXT,
    canal_preferido           TEXT NOT NULL DEFAULT 'WHATSAPP'
                              CHECK (canal_preferido IN ('WHATSAPP', 'INSTAGRAM', 'EMAIL', 'TELEFONE')),
    origem                    TEXT,
    observacoes               TEXT,
    status                    TEXT NOT NULL DEFAULT 'NOVO'
                              CHECK (status IN (
                                  'NOVO',
                                  'EM_CADENCIA',
                                  'AGUARDANDO_MINHA_RESPOSTA',
                                  'AGUARDANDO_CLIENTE',
                                  'CONVERTIDO',
                                  'ENCERRADO',
                                  'BLOQUEADO'
                              )),
    ultima_cadencia_enviada   SMALLINT NOT NULL DEFAULT 0
                              CHECK (ultima_cadencia_enviada >= 0),
    ultimo_contato_em         TIMESTAMPTZ,
    proximo_contato_em        DATE DEFAULT CURRENT_DATE,
    nao_contatar              BOOLEAN NOT NULL DEFAULT FALSE,
    nao_contatar_em           TIMESTAMPTZ,
    motivo_bloqueio           TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Mantem instalações existentes compatíveis com o novo ciclo de conversa.
ALTER TABLE prospect.leads
    DROP CONSTRAINT IF EXISTS leads_status_check;

ALTER TABLE prospect.leads
ADD COLUMN IF NOT EXISTS etapa_comercial TEXT NOT NULL DEFAULT 'NOVO';

UPDATE prospect.leads
   SET status = 'AGUARDANDO_MINHA_RESPOSTA'
 WHERE status = 'RESPONDEU';

ALTER TABLE prospect.leads
    ADD CONSTRAINT leads_status_check
    CHECK (status IN (
        'NOVO',
        'EM_CADENCIA',
        'AGUARDANDO_MINHA_RESPOSTA',
        'AGUARDANDO_CLIENTE',
        'CONVERTIDO',
        'ENCERRADO',
        'BLOQUEADO'
    ));

    

CREATE TABLE IF NOT EXISTS prospect.mensagens (
    id                        BIGSERIAL PRIMARY KEY,
    empresa_id                BIGINT NOT NULL,
    ordem                     SMALLINT NOT NULL CHECK (ordem > 0),
    nome                      TEXT NOT NULL,
    dias_apos_anterior        SMALLINT NOT NULL DEFAULT 0
                              CHECK (dias_apos_anterior >= 0),
    texto                     TEXT NOT NULL CHECK (BTRIM(texto) <> ''),
    ativo                     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_prospect_mensagens_empresa_ordem UNIQUE (empresa_id, ordem)
);





CREATE TABLE IF NOT EXISTS prospect.interacoes (
    id                        BIGSERIAL PRIMARY KEY,
    empresa_id                BIGINT NOT NULL,
    lead_id                   BIGINT NOT NULL
                              REFERENCES prospect.leads(id) ON DELETE CASCADE,
    tipo                      TEXT NOT NULL
                              CHECK (tipo IN (
                                  'ENVIO',
                                  'RESPOSTA',
                                  'ANOTACAO',
                                  'BLOQUEIO',
                                  'CONVERSAO'
                              )),
    canal                     TEXT
                              CHECK (canal IS NULL OR canal IN (
                                  'WHATSAPP',
                                  'INSTAGRAM',
                                  'EMAIL',
                                  'TELEFONE',
                                  'OUTRO'
                              )),
    mensagem_id               BIGINT
                              REFERENCES prospect.mensagens(id) ON DELETE SET NULL,
    cadencia_ordem            SMALLINT,
    mensagem                  TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


ALTER TABLE prospect.interacoes
ADD COLUMN IF NOT EXISTS automatica BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS classificacao TEXT;

CREATE INDEX IF NOT EXISTS ix_prospect_leads_empresa_status
    ON prospect.leads (empresa_id, status);

CREATE INDEX IF NOT EXISTS ix_prospect_leads_empresa_proximo_contato
    ON prospect.leads (empresa_id, proximo_contato_em)
    WHERE nao_contatar = FALSE;

CREATE INDEX IF NOT EXISTS ix_prospect_leads_empresa_nome
    ON prospect.leads (empresa_id, LOWER(nome));

CREATE INDEX IF NOT EXISTS ix_prospect_interacoes_lead_data
    ON prospect.interacoes (empresa_id, lead_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_prospect_mensagens_empresa_ativas
    ON prospect.mensagens (empresa_id, ordem)
    WHERE ativo = TRUE;


ALTER TABLE prospect.interacoes
ADD COLUMN IF NOT EXISTS evolution_message_id text,
ADD COLUMN IF NOT EXISTS status_entrega text,
ADD COLUMN IF NOT EXISTS enviada_em timestamptz,
ADD COLUMN IF NOT EXISTS entregue_em timestamptz,
ADD COLUMN IF NOT EXISTS lida_em timestamptz,
ADD COLUMN IF NOT EXISTS erro_envio text;


CREATE INDEX IF NOT EXISTS idx_interacoes_evolution_message
ON prospect.interacoes (
  empresa_id,
  evolution_message_id
)
WHERE evolution_message_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- UPDATED_AT
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prospect.fn_atualizar_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prospect_leads_updated_at ON prospect.leads;
CREATE TRIGGER trg_prospect_leads_updated_at
BEFORE UPDATE ON prospect.leads
FOR EACH ROW EXECUTE PROCEDURE prospect.fn_atualizar_updated_at();

DROP TRIGGER IF EXISTS trg_prospect_mensagens_updated_at ON prospect.mensagens;
CREATE TRIGGER trg_prospect_mensagens_updated_at
BEFORE UPDATE ON prospect.mensagens
FOR EACH ROW EXECUTE PROCEDURE prospect.fn_atualizar_updated_at();

-- ----------------------------------------------------------------------------
-- HELPERS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prospect.fn_renderizar_mensagem(
    p_texto TEXT,
    p_lead  prospect.leads
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_texto TEXT := COALESCE(p_texto, '');
BEGIN
    v_texto := REPLACE(v_texto, '{{nome}}', COALESCE(p_lead.nome, ''));
    v_texto := REPLACE(v_texto, '{{empresa}}', COALESCE(p_lead.empresa_nome, p_lead.nome, ''));
    v_texto := REPLACE(v_texto, '{{segmento}}', COALESCE(p_lead.segmento, ''));
    v_texto := REPLACE(v_texto, '{{cidade}}', COALESCE(p_lead.cidade, ''));
    RETURN v_texto;
END;
$$;

CREATE OR REPLACE FUNCTION prospect.fn_criar_mensagens_padrao(
    p_empresa_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_inseridas INTEGER;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id e obrigatorio';
    END IF;

    INSERT INTO prospect.mensagens (
        empresa_id,
        ordem,
        nome,
        dias_apos_anterior,
        texto
    )
    VALUES
        (
            p_empresa_id,
            1,
            'Primeiro contato',
            0,
            'Ola, {{nome}}! Tudo bem? Conheci {{empresa}} e acredito que posso ajudar. Posso te explicar rapidamente como funciona?'
        ),
        (
            p_empresa_id,
            2,
            'Segundo contato',
            3,
            'Ola, {{nome}}! Passando para saber se conseguiu ver minha mensagem anterior. Se fizer sentido, posso te mostrar de forma bem objetiva.'
        ),
        (
            p_empresa_id,
            3,
            'Apresentar beneficio',
            7,
            'Ola, {{nome}}! A ideia e ajudar {{empresa}} a ter mais controle e reduzir trabalho manual. Posso te enviar um resumo sem compromisso?'
        ),
        (
            p_empresa_id,
            4,
            'Ultima tentativa',
            14,
            'Ola, {{nome}}! Esta e minha ultima mensagem para nao ser inconveniente. Caso queira conversar no futuro, fico a disposicao.'
        )
    ON CONFLICT (empresa_id, ordem) DO NOTHING;

    GET DIAGNOSTICS v_inseridas = ROW_COUNT;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'mensagens_inseridas', v_inseridas
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- LEADS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION prospect.fn_salvar_lead(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_id   BIGINT := NULLIF(p_payload->>'id', '')::BIGINT;
    v_lead prospect.leads%ROWTYPE;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id e obrigatorio';
    END IF;

    IF BTRIM(COALESCE(p_payload->>'nome', '')) = '' THEN
        RAISE EXCEPTION 'nome do lead e obrigatorio';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO prospect.leads (
            empresa_id,
            tipo_lead,
            nome,
            empresa_nome,
            segmento,
            cidade,
            telefone,
            instagram,
            email,
            canal_preferido,
            origem,
            observacoes,
            proximo_contato_em
        )
        VALUES (
            p_empresa_id,
            COALESCE(NULLIF(UPPER(p_payload->>'tipo_lead'), ''), 'PJ'),
            BTRIM(p_payload->>'nome'),
            NULLIF(BTRIM(p_payload->>'empresa_nome'), ''),
            NULLIF(BTRIM(p_payload->>'segmento'), ''),
            NULLIF(BTRIM(p_payload->>'cidade'), ''),
            NULLIF(BTRIM(p_payload->>'telefone'), ''),
            NULLIF(BTRIM(p_payload->>'instagram'), ''),
            NULLIF(BTRIM(p_payload->>'email'), ''),
            COALESCE(NULLIF(UPPER(p_payload->>'canal_preferido'), ''), 'WHATSAPP'),
            NULLIF(BTRIM(p_payload->>'origem'), ''),
            NULLIF(BTRIM(p_payload->>'observacoes'), ''),
            COALESCE(NULLIF(p_payload->>'proximo_contato_em', '')::DATE, CURRENT_DATE)
        )
        RETURNING * INTO v_lead;
    ELSE
        UPDATE prospect.leads AS l
           SET tipo_lead       = COALESCE(NULLIF(UPPER(p_payload->>'tipo_lead'), ''), l.tipo_lead),
               nome            = BTRIM(p_payload->>'nome'),
               empresa_nome    = NULLIF(BTRIM(p_payload->>'empresa_nome'), ''),
               segmento        = NULLIF(BTRIM(p_payload->>'segmento'), ''),
               cidade          = NULLIF(BTRIM(p_payload->>'cidade'), ''),
               telefone        = NULLIF(BTRIM(p_payload->>'telefone'), ''),
               instagram       = NULLIF(BTRIM(p_payload->>'instagram'), ''),
               email           = NULLIF(BTRIM(p_payload->>'email'), ''),
               canal_preferido = COALESCE(NULLIF(UPPER(p_payload->>'canal_preferido'), ''), l.canal_preferido),
               origem          = NULLIF(BTRIM(p_payload->>'origem'), ''),
               observacoes     = NULLIF(BTRIM(p_payload->>'observacoes'), '')
         WHERE l.id = v_id
           AND l.empresa_id = p_empresa_id
        RETURNING l.* INTO v_lead;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'lead nao encontrado para esta empresa';
        END IF;
    END IF;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'lead', TO_JSONB(v_lead)
    );
END;
$$; 


-- 1) Cria a nova versao da listagem com filtro comercial independente.
-- A assinatura recebe um quinto parametro: p_etapa_comercial.

CREATE OR REPLACE FUNCTION prospect.fn_listar_leads(
    p_empresa_id       BIGINT,
    p_filtro           TEXT DEFAULT 'HOJE',
    p_busca            TEXT DEFAULT NULL,
    p_data             DATE DEFAULT CURRENT_DATE,
    p_etapa_comercial  TEXT DEFAULT 'TODAS'
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_filtro TEXT := UPPER(COALESCE(NULLIF(BTRIM(p_filtro), ''), 'HOJE'));
    v_busca  TEXT := LOWER(BTRIM(COALESCE(p_busca, '')));
    v_etapa  TEXT := UPPER(COALESCE(NULLIF(BTRIM(p_etapa_comercial), ''), 'TODAS'));
    v_dados  JSONB;
    v_resumo JSONB;
BEGIN
    IF v_etapa NOT IN (
        'TODAS',
        'NOVO',
        'CONTATADO',
         'ENCAMINHADO',
        'QUALIFICADO',
        'REUNIAO',
        'PROPOSTA',
        'NEGOCIACAO',
        'GANHO',
        'PERDIDO'
    ) THEN
        RAISE EXCEPTION 'etapa comercial invalida: %', p_etapa_comercial;
    END IF;

    SELECT COALESCE(
        JSONB_AGG(
            TO_JSONB(q)
            ORDER BY
                (q.etapa_comercial = 'NOVO') DESC,
                (q.status = 'AGUARDANDO_MINHA_RESPOSTA') DESC,
                q.proximo_contato_em NULLS LAST,
                q.nome
        ),
        '[]'::JSONB
    )
    INTO v_dados
    FROM (
        SELECT
            l.*,
            m.id AS proxima_mensagem_id,
            m.ordem AS proxima_cadencia,
            m.nome AS proxima_mensagem_nome,
            m.dias_apos_anterior,
            prospect.fn_renderizar_mensagem(m.texto, l) AS mensagem_pronta,
            ui.tipo AS ultima_interacao_tipo,
            ui.mensagem AS ultima_interacao_mensagem,
            ui.created_at AS ultima_interacao_em
        FROM prospect.leads AS l
        LEFT JOIN LATERAL (
            SELECT msg.*
            FROM prospect.mensagens AS msg
            WHERE msg.empresa_id = l.empresa_id
              AND msg.ativo = TRUE
              AND l.status IN ('NOVO', 'EM_CADENCIA')
              AND msg.ordem > l.ultima_cadencia_enviada
            ORDER BY msg.ordem
            LIMIT 1
        ) AS m ON TRUE
        LEFT JOIN LATERAL (
            SELECT i.tipo, i.mensagem, i.created_at
            FROM prospect.interacoes AS i
            WHERE i.empresa_id = l.empresa_id
              AND i.lead_id = l.id
            ORDER BY i.created_at DESC, i.id DESC
            LIMIT 1
        ) AS ui ON TRUE
        WHERE l.empresa_id = p_empresa_id
          AND (
              v_busca = ''
              OR LOWER(COALESCE(l.nome, '')) LIKE '%' || v_busca || '%'
              OR LOWER(COALESCE(l.empresa_nome, '')) LIKE '%' || v_busca || '%'
              OR LOWER(COALESCE(l.telefone, '')) LIKE '%' || v_busca || '%'
              OR LOWER(COALESCE(l.instagram, '')) LIKE '%' || v_busca || '%'
          )
          -- Este filtro e independente do estado da conversa.
          AND (
              v_etapa = 'TODAS'
              OR l.etapa_comercial = v_etapa
          )
          AND CASE v_filtro
              WHEN 'HOJE' THEN
                  l.nao_contatar = FALSE
                  AND (
                      l.status = 'AGUARDANDO_MINHA_RESPOSTA'
                      OR (
                          l.status IN ('EM_CADENCIA', 'AGUARDANDO_CLIENTE')
                          AND l.proximo_contato_em IS NOT NULL
                          AND l.proximo_contato_em <= p_data
                      )
                  )
              WHEN 'NAO_LIDO' THEN l.lido = FALSE
              WHEN 'NOVO' THEN l.etapa_comercial = 'NOVO' AND l.nao_contatar = FALSE
              WHEN 'CONVERSA' THEN l.status IN ('AGUARDANDO_MINHA_RESPOSTA', 'AGUARDANDO_CLIENTE')
              WHEN 'RESPONDEU' THEN l.status = 'AGUARDANDO_MINHA_RESPOSTA'
              WHEN 'AGUARDANDO_MINHA_RESPOSTA' THEN l.status = 'AGUARDANDO_MINHA_RESPOSTA'
              WHEN 'AGUARDANDO_CLIENTE' THEN l.status = 'AGUARDANDO_CLIENTE'
              WHEN 'CONVERTIDO' THEN l.status = 'CONVERTIDO'
              WHEN 'BLOQUEADO' THEN l.nao_contatar = TRUE OR l.status = 'BLOQUEADO'
              WHEN 'ENCERRADO' THEN l.status = 'ENCERRADO'
              ELSE TRUE
          END
    ) AS q;

    SELECT JSONB_BUILD_OBJECT(
        'total', COUNT(*),
        'novos', COUNT(*) FILTER (
            WHERE etapa_comercial = 'NOVO' AND nao_contatar = FALSE
        ),
        'nao_lidos', COUNT(*) FILTER (WHERE lido = FALSE),
        'para_hoje', COUNT(*) FILTER (
            WHERE nao_contatar = FALSE
              AND (
                  status = 'AGUARDANDO_MINHA_RESPOSTA'
                  OR (
                      status IN ('EM_CADENCIA', 'AGUARDANDO_CLIENTE')
                      AND proximo_contato_em IS NOT NULL
                      AND proximo_contato_em <= p_data
                  )
              )
        ),
        'responderam', COUNT(*) FILTER (WHERE status = 'AGUARDANDO_MINHA_RESPOSTA'),
        'aguardando_minha_resposta', COUNT(*) FILTER (WHERE status = 'AGUARDANDO_MINHA_RESPOSTA'),
        'aguardando_cliente', COUNT(*) FILTER (WHERE status = 'AGUARDANDO_CLIENTE'),
        'em_conversa', COUNT(*) FILTER (WHERE status IN ('AGUARDANDO_MINHA_RESPOSTA', 'AGUARDANDO_CLIENTE')),
        'convertidos', COUNT(*) FILTER (WHERE status = 'CONVERTIDO'),
        'bloqueados', COUNT(*) FILTER (WHERE nao_contatar = TRUE OR status = 'BLOQUEADO'),
        'etapas', JSONB_BUILD_OBJECT(
            'novo', COUNT(*) FILTER (WHERE etapa_comercial = 'NOVO'),
            'contatado', COUNT(*) FILTER (WHERE etapa_comercial = 'CONTATADO'),
            'qualificado', COUNT(*) FILTER (WHERE etapa_comercial = 'QUALIFICADO'),
            'reuniao', COUNT(*) FILTER (WHERE etapa_comercial = 'REUNIAO'),
            'proposta', COUNT(*) FILTER (WHERE etapa_comercial = 'PROPOSTA'),
            'negociacao', COUNT(*) FILTER (WHERE etapa_comercial = 'NEGOCIACAO'),
            'ganho', COUNT(*) FILTER (WHERE etapa_comercial = 'GANHO'),
            'perdido', COUNT(*) FILTER (WHERE etapa_comercial = 'PERDIDO')
        )
    )
    INTO v_resumo
    FROM prospect.leads
    WHERE empresa_id = p_empresa_id;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'dados', v_dados,
        'resumo', v_resumo,
        'filtros', JSONB_BUILD_OBJECT(
            'fila', v_filtro,
            'etapa_comercial', v_etapa
        )
    );
END;
$$;

-- 2) Na funcao public.prospectflow_api, substitua SOMENTE o bloco
-- WHEN 'LISTAR_LEADS' pelo bloco abaixo:

/*
WHEN 'LISTAR_LEADS' THEN
    RETURN prospect.fn_listar_leads(
        p_empresa_id,
        COALESCE(p_payload->>'filtro', 'HOJE'),
        p_payload->>'busca',
        COALESCE(NULLIF(p_payload->>'data', '')::DATE, CURRENT_DATE),
        COALESCE(p_payload->>'etapa_comercial', 'TODAS')
    );
*/

-- 3) Depois de substituir o bloco acima e recriar prospectflow_api,
-- a assinatura antiga pode ser removida:
-- DROP FUNCTION IF EXISTS prospect.fn_listar_leads(BIGINT, TEXT, TEXT, DATE);





-- ----------------------------------------------------------------------------
-- ACOES DA CADENCIA
-- ----------------------------------------------------------------------------
 
 
 
CREATE OR REPLACE FUNCTION prospect.fn_registrar_envio(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead                 prospect.leads%ROWTYPE;
    v_mensagem             prospect.mensagens%ROWTYPE;
    v_proxima              prospect.mensagens%ROWTYPE;
    v_lead_id              BIGINT := NULLIF(p_payload->>'lead_id', '')::BIGINT;
    v_mensagem_id          BIGINT := NULLIF(p_payload->>'mensagem_id', '')::BIGINT;
    v_canal                TEXT;
    v_texto_enviado        TEXT;
    v_evolution_message_id TEXT := NULLIF(BTRIM(p_payload->>'evolution_message_id'), '');
    v_status_entrega       TEXT := UPPER(NULLIF(BTRIM(p_payload->>'status_entrega'), ''));
    v_interacao_id         BIGINT;
BEGIN
    SELECT *
      INTO v_lead
      FROM prospect.leads AS l
     WHERE l.id = v_lead_id
       AND l.empresa_id = p_empresa_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lead nao encontrado para esta empresa';
    END IF;

    IF v_lead.nao_contatar OR v_lead.status = 'BLOQUEADO' THEN
        RAISE EXCEPTION 'envio bloqueado: este lead pediu para nao ser contatado';
    END IF;

    IF v_lead.status IN (
        'AGUARDANDO_MINHA_RESPOSTA',
        'AGUARDANDO_CLIENTE',
        'CONVERTIDO',
        'ENCERRADO'
    ) THEN
        RAISE EXCEPTION 'envio bloqueado para o status atual do lead: %', v_lead.status;
    END IF;

    SELECT msg.*
      INTO v_mensagem
      FROM prospect.mensagens AS msg
     WHERE msg.empresa_id = p_empresa_id
       AND msg.ativo = TRUE
       AND msg.ordem > v_lead.ultima_cadencia_enviada
     ORDER BY msg.ordem
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'nao existe proxima mensagem ativa para este lead';
    END IF;

    IF v_mensagem_id IS NOT NULL AND v_mensagem.id <> v_mensagem_id THEN
        RAISE EXCEPTION 'a mensagem informada nao e a proxima mensagem da cadencia';
    END IF;

    v_canal := COALESCE(NULLIF(UPPER(p_payload->>'canal'), ''), v_lead.canal_preferido);
    v_texto_enviado := COALESCE(
        NULLIF(p_payload->>'mensagem', ''),
        prospect.fn_renderizar_mensagem(v_mensagem.texto, v_lead)
    );

    INSERT INTO prospect.interacoes (
        empresa_id,
        lead_id,
        tipo,
        canal,
        mensagem_id,
        cadencia_ordem,
        mensagem,
        evolution_message_id,
        status_entrega,
        enviada_em
    )
    VALUES (
        p_empresa_id,
        v_lead.id,
        'ENVIO',
        v_canal,
        v_mensagem.id,
        v_mensagem.ordem,
        v_texto_enviado,
        v_evolution_message_id,
        COALESCE(v_status_entrega, 'SERVER_ACK'),
        NOW()
    )
    RETURNING id INTO v_interacao_id;

    SELECT msg.*
      INTO v_proxima
      FROM prospect.mensagens AS msg
     WHERE msg.empresa_id = p_empresa_id
       AND msg.ativo = TRUE
       AND msg.ordem > v_mensagem.ordem
     ORDER BY msg.ordem
     LIMIT 1;

    UPDATE prospect.leads AS l
       SET ultima_cadencia_enviada = v_mensagem.ordem,
           ultimo_contato_em = NOW(),
           proximo_contato_em = CASE
               WHEN v_proxima.id IS NULL THEN NULL
               ELSE CURRENT_DATE + v_proxima.dias_apos_anterior
           END,
           status = 'EM_CADENCIA',
           etapa_comercial = CASE
               WHEN l.etapa_comercial = 'NOVO' THEN 'CONTATADO'
               ELSE l.etapa_comercial
           END
     WHERE l.id = v_lead.id
    RETURNING l.* INTO v_lead;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'interacao_id', v_interacao_id,
        'lead', TO_JSONB(v_lead),
        'cadencia_enviada', v_mensagem.ordem,
        'proxima_cadencia', v_proxima.ordem,
        'proximo_contato_em', v_lead.proximo_contato_em
    );
END;
$$; 

 

 
 
 
 
 CREATE OR REPLACE FUNCTION prospect.fn_registrar_resposta(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead    prospect.leads%ROWTYPE;
    v_lead_id BIGINT := NULLIF(p_payload->>'lead_id', '')::BIGINT;
    v_canal   TEXT;
    v_texto   TEXT := NULLIF(BTRIM(p_payload->>'mensagem'), '');
BEGIN
    SELECT *
      INTO v_lead
      FROM prospect.leads AS l
     WHERE l.id = v_lead_id
       AND l.empresa_id = p_empresa_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lead nao encontrado para esta empresa';
    END IF;

    IF v_lead.nao_contatar OR v_lead.status IN ('BLOQUEADO', 'CONVERTIDO', 'ENCERRADO') THEN
        RAISE EXCEPTION 'nao e possivel registrar resposta para o status atual do lead: %', v_lead.status;
    END IF;

    IF v_texto IS NULL THEN
        RAISE EXCEPTION 'a resposta do lead e obrigatoria';
    END IF;

    v_canal := COALESCE(NULLIF(UPPER(p_payload->>'canal'), ''), v_lead.canal_preferido);

    INSERT INTO prospect.interacoes (
        empresa_id,
        lead_id,
        tipo,
        canal,
        mensagem
    )
    VALUES (
        p_empresa_id,
        v_lead.id,
        'RESPOSTA',
        v_canal,
        v_texto
    );

    UPDATE prospect.leads AS l
       SET status = 'AGUARDANDO_MINHA_RESPOSTA',
           proximo_contato_em = NULL
     WHERE l.id = v_lead.id
    RETURNING l.* INTO v_lead;

    RETURN JSONB_BUILD_OBJECT('ok', TRUE, 'lead', TO_JSONB(v_lead));
END;
$$;
 
 
 
CREATE OR REPLACE FUNCTION prospect.fn_registrar_mensagem_conversa(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead                 prospect.leads%ROWTYPE;
    v_lead_id              BIGINT := NULLIF(p_payload->>'lead_id', '')::BIGINT;
    v_canal                TEXT;
    v_texto                TEXT := NULLIF(BTRIM(p_payload->>'mensagem'), '');
    v_evolution_message_id TEXT := NULLIF(BTRIM(p_payload->>'evolution_message_id'), '');
    v_status_entrega       TEXT := UPPER(NULLIF(BTRIM(p_payload->>'status_entrega'), ''));
    v_interacao_id         BIGINT;
BEGIN
    SELECT *
      INTO v_lead
      FROM prospect.leads AS l
     WHERE l.id = v_lead_id
       AND l.empresa_id = p_empresa_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lead nao encontrado para esta empresa';
    END IF;

    IF v_lead.nao_contatar OR v_lead.status IN ('BLOQUEADO', 'CONVERTIDO', 'ENCERRADO') THEN
        RAISE EXCEPTION 'nao e possivel responder para o status atual do lead: %', v_lead.status;
    END IF;

    IF v_lead.status NOT IN ('AGUARDANDO_MINHA_RESPOSTA', 'AGUARDANDO_CLIENTE') THEN
        RAISE EXCEPTION 'o lead ainda nao iniciou uma conversa';
    END IF;

    IF v_texto IS NULL THEN
        RAISE EXCEPTION 'a mensagem enviada e obrigatoria';
    END IF;

    v_canal := COALESCE(NULLIF(UPPER(p_payload->>'canal'), ''), v_lead.canal_preferido);

    INSERT INTO prospect.interacoes (
        empresa_id,
        lead_id,
        tipo,
        canal,
        mensagem,
        evolution_message_id,
        status_entrega,
        enviada_em
    )
    VALUES (
        p_empresa_id,
        v_lead.id,
        'ENVIO',
        v_canal,
        v_texto,
        v_evolution_message_id,
        COALESCE(v_status_entrega, 'SERVER_ACK'),
        NOW()
    )
    RETURNING id INTO v_interacao_id;

    UPDATE prospect.leads AS l
       SET status = 'AGUARDANDO_CLIENTE',
           ultimo_contato_em = NOW(),
           proximo_contato_em = NULL
     WHERE l.id = v_lead.id
    RETURNING l.* INTO v_lead;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'interacao_id', v_interacao_id,
        'lead', TO_JSONB(v_lead)
    );
END;
$$;




 
 
 CREATE OR REPLACE FUNCTION prospect.fn_bloquear_lead(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead    prospect.leads%ROWTYPE;
    v_lead_id BIGINT := NULLIF(p_payload->>'lead_id', '')::BIGINT;
    v_motivo  TEXT := COALESCE(NULLIF(p_payload->>'motivo', ''), 'Destinatario solicitou o encerramento dos contatos');
BEGIN
    UPDATE prospect.leads AS l
       SET nao_contatar = TRUE,
           nao_contatar_em = NOW(),
           motivo_bloqueio = v_motivo,
           status = 'BLOQUEADO',
           proximo_contato_em = NULL,
           etapa_comercial = 'PERDIDO'
     WHERE l.id = v_lead_id
       AND l.empresa_id = p_empresa_id
    RETURNING l.* INTO v_lead;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lead nao encontrado para esta empresa';
    END IF;

    INSERT INTO prospect.interacoes (
        empresa_id,
        lead_id,
        tipo,
        canal,
        mensagem
    )
    VALUES (
        p_empresa_id,
        v_lead.id,
        'BLOQUEIO',
        COALESCE(NULLIF(UPPER(p_payload->>'canal'), ''), v_lead.canal_preferido),
        v_motivo
    );

    RETURN JSONB_BUILD_OBJECT('ok', TRUE, 'lead', TO_JSONB(v_lead));
END;
$$;

CREATE OR REPLACE FUNCTION prospect.fn_converter_lead(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead    prospect.leads%ROWTYPE;
    v_lead_id BIGINT := NULLIF(p_payload->>'lead_id', '')::BIGINT;
BEGIN
    UPDATE prospect.leads AS l
       SET status = 'CONVERTIDO',
           proximo_contato_em = NULL
     WHERE l.id = v_lead_id
       AND l.empresa_id = p_empresa_id
       AND l.nao_contatar = FALSE
    RETURNING l.* INTO v_lead;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lead nao encontrado ou bloqueado';
    END IF;

    INSERT INTO prospect.interacoes (
        empresa_id,
        lead_id,
        tipo,
        canal,
        mensagem
    )
    VALUES (
        p_empresa_id,
        v_lead.id,
        'CONVERSAO',
        NULL,
        COALESCE(NULLIF(p_payload->>'mensagem', ''), 'Lead convertido')
    );

    RETURN JSONB_BUILD_OBJECT('ok', TRUE, 'lead', TO_JSONB(v_lead));
END;
$$;

CREATE OR REPLACE FUNCTION prospect.fn_encerrar_lead(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead    prospect.leads%ROWTYPE;
    v_lead_id BIGINT := NULLIF(p_payload->>'lead_id', '')::BIGINT;
    v_motivo  TEXT := COALESCE(NULLIF(BTRIM(p_payload->>'mensagem'), ''), 'Prospecção encerrada sem conversão');
BEGIN
    UPDATE prospect.leads AS l
       SET status = 'ENCERRADO',
           proximo_contato_em = NULL
     WHERE l.id = v_lead_id
       AND l.empresa_id = p_empresa_id
       AND l.nao_contatar = FALSE
       AND l.status NOT IN ('CONVERTIDO', 'BLOQUEADO')
    RETURNING l.* INTO v_lead;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lead nao encontrado, convertido ou bloqueado';
    END IF;

    INSERT INTO prospect.interacoes (
        empresa_id,
        lead_id,
        tipo,
        canal,
        mensagem
    )
    VALUES (
        p_empresa_id,
        v_lead.id,
        'ANOTACAO',
        NULL,
        v_motivo
    );

    RETURN JSONB_BUILD_OBJECT('ok', TRUE, 'lead', TO_JSONB(v_lead));
END;
$$;

-- ----------------------------------------------------------------------------
-- CONSULTAS E CONFIGURACAO DAS MENSAGENS
-- ----------------------------------------------------------------------------

 CREATE OR REPLACE FUNCTION prospect.fn_historico_lead(
    p_empresa_id BIGINT,
    p_lead_id BIGINT
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    SELECT JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'dados', COALESCE(
            JSONB_AGG(
                TO_JSONB(i)
                ORDER BY i.created_at ASC, i.id ASC
            ) FILTER (WHERE i.id IS NOT NULL),
            '[]'::JSONB
        )
    )
    FROM prospect.interacoes AS i
    WHERE i.empresa_id = p_empresa_id
      AND i.lead_id = p_lead_id;
$$;

CREATE OR REPLACE FUNCTION prospect.fn_listar_mensagens(
    p_empresa_id BIGINT
)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
    SELECT JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'dados', COALESCE(
            JSONB_AGG(TO_JSONB(m) ORDER BY m.ordem),
            '[]'::JSONB
        )
    )
    FROM prospect.mensagens AS m
    WHERE m.empresa_id = p_empresa_id;
$$;

CREATE OR REPLACE FUNCTION prospect.fn_salvar_mensagem(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_id       BIGINT := NULLIF(p_payload->>'id', '')::BIGINT;
    v_mensagem prospect.mensagens%ROWTYPE;
BEGIN
    IF NULLIF(p_payload->>'ordem', '')::SMALLINT IS NULL THEN
        RAISE EXCEPTION 'ordem da mensagem e obrigatoria';
    END IF;

    IF BTRIM(COALESCE(p_payload->>'nome', '')) = '' THEN
        RAISE EXCEPTION 'nome da mensagem e obrigatorio';
    END IF;

    IF BTRIM(COALESCE(p_payload->>'texto', '')) = '' THEN
        RAISE EXCEPTION 'texto da mensagem e obrigatorio';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO prospect.mensagens (
            empresa_id,
            ordem,
            nome,
            dias_apos_anterior,
            texto,
            ativo
        )
        VALUES (
            p_empresa_id,
            (p_payload->>'ordem')::SMALLINT,
            BTRIM(p_payload->>'nome'),
            COALESCE(NULLIF(p_payload->>'dias_apos_anterior', '')::SMALLINT, 0),
            p_payload->>'texto',
            COALESCE((p_payload->>'ativo')::BOOLEAN, TRUE)
        )
        RETURNING * INTO v_mensagem;
    ELSE
        UPDATE prospect.mensagens AS m
           SET ordem = (p_payload->>'ordem')::SMALLINT,
               nome = BTRIM(p_payload->>'nome'),
               dias_apos_anterior = COALESCE(NULLIF(p_payload->>'dias_apos_anterior', '')::SMALLINT, 0),
               texto = p_payload->>'texto',
               ativo = COALESCE((p_payload->>'ativo')::BOOLEAN, TRUE)
         WHERE m.id = v_id
           AND m.empresa_id = p_empresa_id
        RETURNING m.* INTO v_mensagem;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'mensagem nao encontrada para esta empresa';
        END IF;
    END IF;

    RETURN JSONB_BUILD_OBJECT('ok', TRUE, 'mensagem', TO_JSONB(v_mensagem));
END;
$$;

-- ----------------------------------------------------------------------------
-- API UNICA PARA O N8N
-- ----------------------------------------------------------------------------
 

 CREATE OR REPLACE FUNCTION public.prospectflow_api(
    p_empresa_id BIGINT,
    p_acao       TEXT,
    p_payload    JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_acao TEXT := UPPER(BTRIM(COALESCE(p_acao, '')));
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id e obrigatorio';
    END IF;

    CASE v_acao
        WHEN 'LISTAR_LEADS' THEN
            RETURN prospect.fn_listar_leads(
                p_empresa_id,
                COALESCE(p_payload->>'filtro', 'HOJE'),
                p_payload->>'busca',
                COALESCE(
                    NULLIF(p_payload->>'data', '')::DATE,
                    CURRENT_DATE
                ),
                COALESCE(
                    NULLIF(p_payload->>'etapa_comercial', ''),
                    'TODAS'
                )
            );

        WHEN 'SALVAR_LEAD' THEN
            RETURN prospect.fn_salvar_lead(
                p_empresa_id,
                p_payload
            );

        WHEN 'REGISTRAR_ENVIO' THEN
            RETURN prospect.fn_registrar_envio(
                p_empresa_id,
                p_payload
            );

        WHEN 'REGISTRAR_RESPOSTA' THEN
            RETURN prospect.fn_registrar_resposta(
                p_empresa_id,
                p_payload
            );

        WHEN 'REGISTRAR_MENSAGEM_CONVERSA' THEN
            RETURN prospect.fn_registrar_mensagem_conversa(
                p_empresa_id,
                p_payload
            );

        WHEN 'BLOQUEAR_LEAD' THEN
            RETURN prospect.fn_bloquear_lead(
                p_empresa_id,
                p_payload
            );

        WHEN 'CONVERTER_LEAD' THEN
            RETURN prospect.fn_converter_lead(
                p_empresa_id,
                p_payload
            );

        WHEN 'ENCERRAR_LEAD' THEN
            RETURN prospect.fn_encerrar_lead(
                p_empresa_id,
                p_payload
            );

        WHEN 'HISTORICO' THEN
            RETURN prospect.fn_historico_lead(
                p_empresa_id,
                NULLIF(p_payload->>'lead_id', '')::BIGINT
            );

        WHEN 'LISTAR_MENSAGENS' THEN
            RETURN prospect.fn_listar_mensagens(
                p_empresa_id
            );

        WHEN 'SALVAR_MENSAGEM' THEN
            RETURN prospect.fn_salvar_mensagem(
                p_empresa_id,
                p_payload
            );

        WHEN 'CRIAR_MENSAGENS_PADRAO' THEN
            RETURN prospect.fn_criar_mensagens_padrao(
                p_empresa_id
            );

        WHEN 'MARCAR_LIDO' THEN
            RETURN prospect.fn_marcar_lido(
                p_empresa_id,
                p_payload
            );

        WHEN 'ALTERAR_ETAPA_COMERCIAL' THEN
            RETURN prospect.fn_alterar_etapa_comercial(
                p_empresa_id,
                p_payload
            );

        WHEN 'SALVAR_TAREFA' THEN
            RETURN prospect.fn_salvar_tarefa(
                p_empresa_id,
                p_payload
            );

        WHEN 'LISTAR_TAREFAS' THEN
            RETURN prospect.fn_listar_tarefas(
                p_empresa_id,
                p_payload
            );

        WHEN 'CONCLUIR_TAREFA' THEN
            RETURN prospect.fn_concluir_tarefa(
                p_empresa_id,
                p_payload
            );

        WHEN 'ADIAR_TAREFA' THEN
            RETURN prospect.fn_adiar_tarefa(
                p_empresa_id,
                p_payload
            );

        WHEN 'ANALISE_ATIVIDADE' THEN
            RETURN public.prospectflow_analise_atividade(
                p_empresa_id,
                COALESCE(
                    NULLIF(p_payload->>'dias', '')::INTEGER,
                    30
                )
            );

        WHEN 'LEAD_AGENDA' THEN
            RETURN prospect.fn_lead_agenda(
                p_empresa_id,
                NULLIF(p_payload->>'lead_id', '')::BIGINT
            );

        WHEN 'LIGACOES_LEADS_ELEGIVEIS' THEN
            RETURN prospect.fn_ligacoes_leads_elegiveis(
                p_empresa_id,
                COALESCE(
                    NULLIF(p_payload->>'limite', '')::INTEGER,
                    12
                )
            );

        WHEN 'LIGACOES_CRIAR_FILA' THEN
            RETURN prospect.fn_ligacoes_criar_fila(
                p_empresa_id,
                COALESCE(
                    NULLIF(p_payload->>'data', '')::DATE,
                    CURRENT_DATE
                ),
                COALESCE(
                    NULLIF(p_payload->>'limite', '')::INTEGER,
                    12
                )
            );

        WHEN 'LIGACOES_LISTAR' THEN
            RETURN prospect.fn_ligacoes_listar(
                p_empresa_id,
                COALESCE(
                    NULLIF(p_payload->>'filtro', ''),
                    'A_FAZER'
                )
            );

        WHEN 'LIGACOES_ATUALIZAR' THEN
            RETURN prospect.fn_ligacoes_atualizar(
                p_empresa_id,
                NULLIF(p_payload->>'ligacao_id', '')::BIGINT,
                p_payload->>'resultado',
                p_payload->>'observacao',
                NULLIF(
                    p_payload->>'retornar_em',
                    ''
                )::TIMESTAMPTZ
            );

          WHEN 'LIGACOES_CRIAR_PARA_LEAD' THEN
            IF NULLIF(p_payload->>'lead_id', '') IS NULL THEN
                RAISE EXCEPTION 'lead_id e obrigatorio';
            END IF;

            RETURN prospect.fn_ligacoes_criar_fila(
                p_empresa_id,
                COALESCE(
                    NULLIF(p_payload->>'data', '')::DATE,
                    CURRENT_DATE
                ),
                1,
                NULLIF(p_payload->>'lead_id', '')::BIGINT
            );

 


        ELSE
            RAISE EXCEPTION 'acao invalida: %', p_acao;
    END CASE;
END;
$$;

COMMENT ON FUNCTION public.prospectflow_api(BIGINT, TEXT, JSONB) IS
'API unica do MVP ProspectFlow. O n8n deve repassar empresa_id, acao e payload.';