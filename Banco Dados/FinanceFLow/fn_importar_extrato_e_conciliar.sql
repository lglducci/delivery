 CREATE OR REPLACE FUNCTION public.fn_importar_extrato_e_conciliar(
    p_empresa_id bigint,
    p_conta_financeira_id bigint,
    p_lancamentos jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_ultimo_id bigint;
    v_ultimo_lote_conciliacao_id bigint;
BEGIN
    SELECT COALESCE(MAX(id), 0)
    INTO v_ultimo_id
    FROM public.conciliacao_financeira
    WHERE empresa_id = p_empresa_id
      AND conta_financeira_id = p_conta_financeira_id;

    PERFORM public.fn_importar_extrato(
        p_empresa_id,
        p_conta_financeira_id,
        p_lancamentos
    );

    PERFORM public.fn_importar_extrato_revisar_evento(
        p_empresa_id,
        p_conta_financeira_id 
    );

    PERFORM public.fn_conciliar_extrato_faturas_cartao(
        p_empresa_id,
        p_conta_financeira_id,
        v_ultimo_id 
    );

    PERFORM public.fn_conciliar_extrato_contas_pagar(
        p_empresa_id,
        p_conta_financeira_id,
        v_ultimo_id, null
    );

    PERFORM public.fn_conciliar_extrato_contas_receber(
        p_empresa_id,
        p_conta_financeira_id,
        v_ultimo_id, null
    );
 SELECT COALESCE(MAX(lote_conciliacao_id), 0)
INTO v_ultimo_lote_conciliacao_id
FROM public.conciliacao_financeira
WHERE empresa_id = p_empresa_id
  AND conta_financeira_id = p_conta_financeira_id
  AND COALESCE(lote_conciliacao_id, 0) > 0;
 
    RETURN jsonb_build_object(
        'ok', true,
        'id_inicial', v_ultimo_id,
        'lote_id',v_ultimo_lote_conciliacao_id
    );
END;
$$;