CREATE OR REPLACE FUNCTION prospect.fn_marcar_lido(
    p_empresa_id BIGINT,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_lead_id BIGINT :=
        NULLIF(p_payload->>'lead_id', '')::BIGINT;

    v_lead prospect.leads%ROWTYPE;
BEGIN
    IF v_lead_id IS NULL THEN
        RAISE EXCEPTION 'lead_id é obrigatório';
    END IF;

    UPDATE prospect.leads AS l
    SET lido = TRUE
    WHERE l.empresa_id = p_empresa_id
      AND l.id = v_lead_id
    RETURNING l.* INTO v_lead;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'lead não encontrado para empresa_id %',
            p_empresa_id;
    END IF;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'lead_id', v_lead.id,
        'lido', v_lead.lido
    );
END;
$$;