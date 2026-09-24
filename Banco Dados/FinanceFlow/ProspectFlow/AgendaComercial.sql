-- AGENDA COMERCIAL DO PROSPECTFLOW
-- Independente da cadência automática.

CREATE TABLE IF NOT EXISTS prospect.tarefas (
    id              BIGSERIAL PRIMARY KEY,
    empresa_id      BIGINT NOT NULL,
    lead_id         BIGINT NOT NULL REFERENCES prospect.leads(id) ON DELETE CASCADE,
    tipo            TEXT NOT NULL,
    descricao       TEXT,
    agendada_para   TIMESTAMPTZ NOT NULL,
    status          TEXT NOT NULL DEFAULT 'PENDENTE',
    concluida_em    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT tarefas_tipo_check CHECK (
        tipo IN (
            'LIGAR',
            'ENVIAR_MENSAGEM',
            'ENVIAR_PROPOSTA',
            'COBRAR_RESPOSTA',
            'VISITAR',
            'OUTRO'
        )
    ),
    CONSTRAINT tarefas_status_check CHECK (
        status IN ('PENDENTE', 'CONCLUIDA', 'CANCELADA')
    )
);

CREATE INDEX IF NOT EXISTS idx_tarefas_empresa_status_data
    ON prospect.tarefas (empresa_id, status, agendada_para);

CREATE INDEX IF NOT EXISTS idx_tarefas_empresa_lead_status_data
    ON prospect.tarefas (empresa_id, lead_id, status, agendada_para);


CREATE OR REPLACE FUNCTION prospect.fn_salvar_tarefa(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead_id       BIGINT := NULLIF(p_payload->>'lead_id', '')::BIGINT;
    v_tipo          TEXT := UPPER(COALESCE(NULLIF(p_payload->>'tipo', ''), 'OUTRO'));
    v_descricao     TEXT := NULLIF(BTRIM(COALESCE(p_payload->>'descricao', '')), '');
    v_agendada_para TIMESTAMPTZ := NULLIF(p_payload->>'agendada_para', '')::TIMESTAMPTZ;
    v_tarefa        prospect.tarefas%ROWTYPE;
    v_nome_lead     TEXT;
BEGIN
    IF v_lead_id IS NULL THEN
        RAISE EXCEPTION 'lead_id obrigatorio';
    END IF;

    IF v_agendada_para IS NULL THEN
        RAISE EXCEPTION 'agendada_para obrigatorio';
    END IF;

    IF v_tipo NOT IN (
        'LIGAR', 'ENVIAR_MENSAGEM', 'ENVIAR_PROPOSTA',
        'COBRAR_RESPOSTA', 'VISITAR', 'OUTRO'
    ) THEN
        RAISE EXCEPTION 'tipo de tarefa invalido: %', v_tipo;
    END IF;

    SELECT COALESCE(NULLIF(l.empresa_nome, ''), l.nome)
      INTO v_nome_lead
      FROM prospect.leads AS l
     WHERE l.id = v_lead_id
       AND l.empresa_id = p_empresa_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lead nao encontrado para esta empresa';
    END IF;

    INSERT INTO prospect.tarefas (
        empresa_id,
        lead_id,
        tipo,
        descricao,
        agendada_para
    ) VALUES (
        p_empresa_id,
        v_lead_id,
        v_tipo,
        v_descricao,
        v_agendada_para
    )
    RETURNING * INTO v_tarefa;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'tarefa', TO_JSONB(v_tarefa) || JSONB_BUILD_OBJECT('lead_nome', v_nome_lead)
    );
END;
$$;


CREATE OR REPLACE FUNCTION prospect.fn_listar_tarefas(
    p_empresa_id BIGINT,
    p_payload    JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_filtro TEXT := UPPER(COALESCE(NULLIF(p_payload->>'filtro', ''), 'HOJE'));
    v_busca  TEXT := LOWER(BTRIM(COALESCE(p_payload->>'busca', '')));
    v_hoje   DATE := COALESCE(
        NULLIF(p_payload->>'data', '')::DATE,
        (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE
    );
    v_dados  JSONB;
    v_resumo JSONB;
BEGIN
    SELECT COALESCE(
        JSONB_AGG(TO_JSONB(q) ORDER BY q.agendada_para, q.lead_nome),
        '[]'::JSONB
    )
      INTO v_dados
      FROM (
        SELECT
            t.*,
            l.nome,
            l.empresa_nome,
            COALESCE(NULLIF(l.empresa_nome, ''), l.nome) AS lead_nome,
            l.telefone,
            l.canal_preferido,
            l.etapa_comercial
        FROM prospect.tarefas AS t
        JOIN prospect.leads AS l
          ON l.id = t.lead_id
         AND l.empresa_id = t.empresa_id
        WHERE t.empresa_id = p_empresa_id
          AND (
              v_busca = ''
              OR LOWER(COALESCE(l.nome, '')) LIKE '%' || v_busca || '%'
              OR LOWER(COALESCE(l.empresa_nome, '')) LIKE '%' || v_busca || '%'
              OR LOWER(COALESCE(t.descricao, '')) LIKE '%' || v_busca || '%'
          )
          AND CASE v_filtro
              WHEN 'ATRASADAS' THEN
                  t.status = 'PENDENTE'
                  AND t.agendada_para < NOW()
              WHEN 'HOJE' THEN
                  t.status = 'PENDENTE'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE = v_hoje
              WHEN 'PROXIMOS_7' THEN
                  t.status = 'PENDENTE'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE > v_hoje
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE <= v_hoje + 7
              WHEN 'PROXIMOS_30' THEN
                  t.status = 'PENDENTE'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE > v_hoje
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE <= v_hoje + 30
              WHEN 'CONCLUIDAS' THEN t.status = 'CONCLUIDA'
              WHEN 'PENDENTES' THEN t.status = 'PENDENTE'
              ELSE TRUE
          END
      ) AS q;

    SELECT JSONB_BUILD_OBJECT(
        'atrasadas', COUNT(*) FILTER (
            WHERE status = 'PENDENTE' AND agendada_para < NOW()
        ),
        'hoje', COUNT(*) FILTER (
            WHERE status = 'PENDENTE'
              AND (agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE = v_hoje
        ),
        'proximos_7', COUNT(*) FILTER (
            WHERE status = 'PENDENTE'
              AND (agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE > v_hoje
              AND (agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE <= v_hoje + 7
        ),
        'proximos_30', COUNT(*) FILTER (
            WHERE status = 'PENDENTE'
              AND (agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE > v_hoje
              AND (agendada_para AT TIME ZONE 'America/Sao_Paulo')::DATE <= v_hoje + 30
        ),
        'pendentes', COUNT(*) FILTER (WHERE status = 'PENDENTE'),
        'concluidas', COUNT(*) FILTER (WHERE status = 'CONCLUIDA')
    )
      INTO v_resumo
      FROM prospect.tarefas
     WHERE empresa_id = p_empresa_id;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'dados', v_dados,
        'resumo', v_resumo
    );
END;
$$;


CREATE OR REPLACE FUNCTION prospect.fn_concluir_tarefa(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_tarefa_id BIGINT := NULLIF(p_payload->>'tarefa_id', '')::BIGINT;
    v_tarefa    prospect.tarefas%ROWTYPE;
BEGIN
    UPDATE prospect.tarefas
       SET status = 'CONCLUIDA',
           concluida_em = NOW(),
           updated_at = NOW()
     WHERE id = v_tarefa_id
       AND empresa_id = p_empresa_id
       AND status = 'PENDENTE'
    RETURNING * INTO v_tarefa;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'tarefa pendente nao encontrada';
    END IF;

    RETURN JSONB_BUILD_OBJECT('ok', TRUE, 'tarefa', TO_JSONB(v_tarefa));
END;
$$;


CREATE OR REPLACE FUNCTION prospect.fn_adiar_tarefa(
    p_empresa_id BIGINT,
    p_payload    JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_tarefa_id      BIGINT := NULLIF(p_payload->>'tarefa_id', '')::BIGINT;
    v_agendada_para  TIMESTAMPTZ := NULLIF(p_payload->>'agendada_para', '')::TIMESTAMPTZ;
    v_tarefa         prospect.tarefas%ROWTYPE;
BEGIN
    IF v_agendada_para IS NULL THEN
        RAISE EXCEPTION 'nova data obrigatoria';
    END IF;

    UPDATE prospect.tarefas
       SET agendada_para = v_agendada_para,
           updated_at = NOW()
     WHERE id = v_tarefa_id
       AND empresa_id = p_empresa_id
       AND status = 'PENDENTE'
    RETURNING * INTO v_tarefa;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'tarefa pendente nao encontrada';
    END IF;

    RETURN JSONB_BUILD_OBJECT('ok', TRUE, 'tarefa', TO_JSONB(v_tarefa));
END;
$$;


-- ADICIONE ESTES CASES DENTRO DA FUNCAO public.prospectflow_api,
-- junto das outras acoes existentes:
--
-- WHEN 'SALVAR_TAREFA' THEN
--     RETURN prospect.fn_salvar_tarefa(p_empresa_id, p_payload);
-- WHEN 'LISTAR_TAREFAS' THEN
--     RETURN prospect.fn_listar_tarefas(p_empresa_id, p_payload);
-- WHEN 'CONCLUIR_TAREFA' THEN
--     RETURN prospect.fn_concluir_tarefa(p_empresa_id, p_payload);
-- WHEN 'ADIAR_TAREFA' THEN
--     RETURN prospect.fn_adiar_tarefa(p_empresa_id, p_payload);

