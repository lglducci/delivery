-- ============================================================
-- AGENDA COMPLETA DE UM PROSPECT
-- ============================================================

CREATE OR REPLACE FUNCTION prospect.fn_lead_agenda(
    p_empresa_id BIGINT,
    p_lead_id    BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_lead   JSONB;
    v_dados  JSONB;
    v_resumo JSONB;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id obrigatorio';
    END IF;

    IF p_lead_id IS NULL THEN
        RAISE EXCEPTION 'lead_id obrigatorio';
    END IF;

    SELECT JSONB_BUILD_OBJECT(
        'id', l.id,
        'nome', l.nome,
        'empresa_nome', l.empresa_nome,
        'telefone', l.telefone,
        'canal_preferido', l.canal_preferido,
        'etapa_comercial', l.etapa_comercial,
        'status', l.status
    )
    INTO v_lead
    FROM prospect.leads AS l
    WHERE l.id = p_lead_id
      AND l.empresa_id = p_empresa_id;

    IF v_lead IS NULL THEN
        RAISE EXCEPTION 'lead nao encontrado para esta empresa';
    END IF;

    SELECT COALESCE(
        JSONB_AGG(
            TO_JSONB(q)
            ORDER BY q.agendada_para asc, q.id asc 
        ),
        '[]'::JSONB
    )
    INTO v_dados
    FROM (
        SELECT
            t.id,
            t.lead_id,
            t.tipo,
            t.descricao,
            t.agendada_para,
            t.status,
            t.concluida_em,
            t.created_at,
            t.updated_at
        FROM prospect.tarefas AS t
        WHERE t.empresa_id = p_empresa_id
          AND t.lead_id = p_lead_id
    ) AS q;

    SELECT JSONB_BUILD_OBJECT(
        'total', COUNT(*),
        'pendentes', COUNT(*) FILTER (
            WHERE status = 'PENDENTE'
        ),
        'concluidas', COUNT(*) FILTER (
            WHERE status = 'CONCLUIDA'
        ),
        'canceladas', COUNT(*) FILTER (
            WHERE status = 'CANCELADA'
        ),
        'atrasadas', COUNT(*) FILTER (
            WHERE status = 'PENDENTE'
              AND agendada_para < NOW()
        ),
        'proxima_acao', MIN(agendada_para) FILTER (
            WHERE status = 'PENDENTE'
              AND agendada_para >= NOW()
        )
    )
    INTO v_resumo
    FROM prospect.tarefas
    WHERE empresa_id = p_empresa_id
      AND lead_id = p_lead_id;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'lead', v_lead,
        'dados', v_dados,
        'resumo', v_resumo
    );
END;
$$;

COMMENT ON FUNCTION prospect.fn_lead_agenda(BIGINT, BIGINT) IS
'Lista todo o histórico de tarefas e agendamentos de um prospect.';


-- ============================================================
-- TESTE DIRETO
-- Troque o segundo parâmetro pelo ID do lead.
-- ============================================================

-- SELECT prospect.fn_lead_agenda(1, 123);


-- ============================================================
-- AÇÃO PARA INCLUIR NA public.prospectflow_api
-- Adicione antes do ELSE.
-- ============================================================

/*
WHEN 'LEAD_AGENDA' THEN
    RETURN prospect.fn_lead_agenda(
        p_empresa_id,
        NULLIF(p_payload->>'lead_id', '')::BIGINT
    );
*/


-- ============================================================
-- TESTE PELA API CENTRAL
-- ============================================================

-- SELECT public.prospectflow_api(
--     1,
--     'LEAD_AGENDA',
--     '{"lead_id":123}'::JSONB
-- );