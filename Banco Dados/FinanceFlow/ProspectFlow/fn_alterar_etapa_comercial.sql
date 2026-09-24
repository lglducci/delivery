CREATE OR REPLACE FUNCTION prospect.fn_alterar_etapa_comercial(
    p_empresa_id BIGINT,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead_id BIGINT :=
        NULLIF(p_payload->>'lead_id', '')::BIGINT;

    v_etapa TEXT :=
        UPPER(BTRIM(COALESCE(
            p_payload->>'etapa_comercial',
            ''
        )));

    v_lead prospect.leads%ROWTYPE;
BEGIN
    IF v_lead_id IS NULL THEN
        RAISE EXCEPTION 'lead_id é obrigatório';
    END IF;

    IF v_etapa NOT IN (
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
        RAISE EXCEPTION
            'etapa comercial inválida: %',
            v_etapa;
    END IF;

    UPDATE prospect.leads AS l
    SET etapa_comercial = v_etapa
    WHERE l.id = v_lead_id
      AND l.empresa_id = p_empresa_id
      AND l.status NOT IN (
          'CONVERTIDO',
          'ENCERRADO',
          'BLOQUEADO'
      )
      AND l.nao_contatar = FALSE
    RETURNING l.* INTO v_lead;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'lead não encontrado ou não permite alteração de etapa';
    END IF;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'lead', TO_JSONB(v_lead)
    );
END;
$$;