CREATE OR REPLACE FUNCTION public.fn_executar_titulos_selecionados(
    p_empresa_id bigint,
    p_conta_id bigint,
    p_itens jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_pagar_ids json;
    v_receber_ids json;
    v_fatura_ids json;

    v_qtd_pagar int := 0;
    v_qtd_receber int := 0;
    v_qtd_fatura int := 0;
BEGIN

    -- CONTAS A PAGAR
    SELECT COALESCE(json_agg(DISTINCT (x->>'origem_id')::bigint), '[]'::json)
    INTO v_pagar_ids
    FROM jsonb_array_elements(p_itens) x
    WHERE x->>'origem_tabela' = 'contas_a_pagar';

    SELECT json_array_length(v_pagar_ids) INTO v_qtd_pagar;

    IF v_qtd_pagar > 0 THEN
        PERFORM public.ff_pagar_contas(
            p_empresa_id,
            v_pagar_ids,
            p_conta_id
        );
    END IF;


    -- CONTAS A RECEBER
    SELECT COALESCE(json_agg(DISTINCT (x->>'origem_id')::bigint), '[]'::json)
    INTO v_receber_ids
    FROM jsonb_array_elements(p_itens) x
    WHERE x->>'origem_tabela' = 'contas_a_receber';

    SELECT json_array_length(v_receber_ids) INTO v_qtd_receber;

    IF v_qtd_receber > 0 THEN
        PERFORM public.ff_receber_contas(
            p_empresa_id,
            v_receber_ids,
            p_conta_id
        );
    END IF;


    -- FATURAS DE CARTÃO
    SELECT COALESCE(json_agg(DISTINCT (x->>'origem_id')::bigint), '[]'::json)
    INTO v_fatura_ids
    FROM jsonb_array_elements(p_itens) x
    WHERE x->>'origem_tabela' = 'cartoes_faturas';

    SELECT json_array_length(v_fatura_ids) INTO v_qtd_fatura;

    IF v_qtd_fatura > 0 THEN
        PERFORM public.ff_registrar_pagamento_faturas(
            p_empresa_id,
            p_conta_id,
            v_fatura_ids
        );
    END IF;


    RETURN jsonb_build_object(
        'ok', true,
        'message', 'Títulos executados com sucesso',
        'empresa_id', p_empresa_id,
        'conta_id', p_conta_id,
        'pagar', v_qtd_pagar,
        'receber', v_qtd_receber,
        'faturas', v_qtd_fatura
    );

END;
$$;