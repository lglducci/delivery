 CREATE OR REPLACE FUNCTION public.ff_conciliar_importacao_cartao(
    p_empresa_id BIGINT,
    p_importacao_id BIGINT,
    p_data_referencia DATE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_cartao_id BIGINT;
    v_qtd_processadas INTEGER := 0;
BEGIN
    IF p_data_referencia IS NULL THEN
        RAISE EXCEPTION 'Informe a data de referência da fatura.';
    END IF;

    SELECT ci.cartao_id
      INTO v_cartao_id
    FROM public.cartao_importacoes ci
    WHERE ci.id = p_importacao_id
      AND ci.empresa_id = p_empresa_id;

    IF v_cartao_id IS NULL THEN
        RAISE EXCEPTION
        'Importação % não encontrada para empresa %.',
        p_importacao_id,
        p_empresa_id;
    END IF;

    SELECT COUNT(*)
      INTO v_qtd_processadas
    FROM public.cartao_importacoes ci
    WHERE ci.empresa_id = p_empresa_id
      AND ci.cartao_id = v_cartao_id
      AND ci.status IN ('processado', 'conciliado');

    -- PRIMEIRA IMPORTAÇÃO = IMPLANTAÇÃO
    IF v_qtd_processadas = 0 THEN
        RETURN public.ff_conciliar_importacao_cartao_implantacao(
            p_empresa_id,
            p_importacao_id,
            p_data_referencia
        );
    END IF;

   IF v_qtd_processadas > 0 THEN
            -- IMPORTAÇÕES NORMAIS
            RETURN public.ff_conciliar_importacao_cartao_normal(
                p_empresa_id,
                p_importacao_id,
                p_data_referencia
            );

      END IF;

END;
$$;