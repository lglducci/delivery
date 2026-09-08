 CREATE OR REPLACE FUNCTION public.ff_gravar_pluggy_cartao(
    p_empresa_id       BIGINT,
    p_conta_id         BIGINT,
    p_pluggy_item_id   UUID,
    p_pluggy_cartao_id UUID,
    p_numero_cartao    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO public.pluggy_cartoes
    (
        empresa_id,
        conta_id,
        pluggy_item_id,
        pluggy_cartao_id,
        numero_cartao
    )
    VALUES
    (
        p_empresa_id,
        p_conta_id,
        p_pluggy_item_id,
        p_pluggy_cartao_id,
        p_numero_cartao
    )
    ON CONFLICT (empresa_id, pluggy_cartao_id)
    DO UPDATE SET
        conta_id         = EXCLUDED.conta_id,
        pluggy_item_id   = EXCLUDED.pluggy_item_id,
        numero_cartao    = EXCLUDED.numero_cartao,
        atualizado_em    = NOW()
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'ok', true,
        'id', v_id,
        'empresa_id', p_empresa_id,
        'conta_id', p_conta_id,
        'pluggy_item_id', p_pluggy_item_id,
        'pluggy_cartao_id', p_pluggy_cartao_id,
        'numero_cartao', p_numero_cartao
    );
END;
$$;