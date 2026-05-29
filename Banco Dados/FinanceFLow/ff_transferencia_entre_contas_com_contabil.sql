CREATE OR REPLACE FUNCTION public.ff_transferencia_entre_contas_com_contabil(
    p_empresa_id bigint,
    p_conta_origem_id bigint,
    p_conta_destino_id bigint,
    p_valor numeric,
    p_historico text DEFAULT NULL,
    p_data_mov date DEFAULT CURRENT_DATE,
    p_lote_id bigint DEFAULT NULL,
    p_conciliacao_id  bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_contabil_origem_id bigint;
    v_contabil_destino_id bigint;
    v_lote_transferencia  bigint;
    v_nome_origem text;
    v_nome_destino text;
    
    v_historico text;
    v_retorno_financeiro jsonb;
BEGIN
    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'Valor da transferência deve ser maior que zero';
    END IF;

    IF p_conta_origem_id = p_conta_destino_id THEN
        RAISE EXCEPTION 'Conta origem e destino não podem ser iguais';
    END IF;

    SELECT nome, contabil_id
    INTO v_nome_origem, v_contabil_origem_id
    FROM public.contas_financeiras
    WHERE id = p_conta_origem_id
      AND empresa_id = p_empresa_id;

    IF v_contabil_origem_id IS NULL THEN
        RAISE EXCEPTION 'Conta origem não possui contabil_id configurado';
    END IF;

    SELECT nome, contabil_id
    INTO v_nome_destino, v_contabil_destino_id
    FROM public.contas_financeiras
    WHERE id = p_conta_destino_id
      AND empresa_id = p_empresa_id;

    IF v_contabil_destino_id IS NULL THEN
        RAISE EXCEPTION 'Conta destino não possui contabil_id configurado';
    END IF;

    v_historico := COALESCE(
        NULLIF(trim(p_historico), ''),
        'Transferência ' || v_nome_origem || ' para ' || v_nome_destino
    );

    -- 1) cria as duas transações financeiras
    v_retorno_financeiro := public.ff_transferencia_entre_contas(
        p_empresa_id,
        p_conta_origem_id,
        p_conta_destino_id,
        abs(p_valor),
        v_historico,
        p_data_mov,
        p_conciliacao_id
    );

 v_lote_transferencia := (v_retorno_financeiro->>'lote_transferencia')::bigint;

    -- 2) cria o contábil correto
    -- Débito: conta destino
    -- Crédito: conta origem
    PERFORM contab.ff_lancamento_partida_dobrada(
        p_empresa_id,
        v_contabil_destino_id,
        v_contabil_origem_id,
        abs(p_valor),
        v_historico,
        p_data_mov,
        false,
        NULL,
        v_lote_transferencia
    );

    RETURN jsonb_build_object(
        'ok', true,
        'mensagem', 'Transferência financeira e contábil criada com sucesso',
        'conta_origem_id', p_conta_origem_id,
        'conta_origem_nome', v_nome_origem,
        'conta_destino_id', p_conta_destino_id,
        'conta_destino_nome', v_nome_destino,
        'contabil_origem_id', v_contabil_origem_id,
        'contabil_destino_id', v_contabil_destino_id,
        'valor', abs(p_valor),
        'historico', v_historico,
        'financeiro', v_retorno_financeiro
    );
END;
$$;