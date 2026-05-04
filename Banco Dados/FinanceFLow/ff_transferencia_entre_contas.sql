CREATE OR REPLACE FUNCTION public.ff_transferencia_entre_contas(
    p_empresa_id bigint,
    p_conta_origem_id bigint,
    p_conta_destino_id bigint,
    p_valor numeric,
    p_historico text,
    p_data_mov date
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_saida bigint;
    v_id_entrada bigint;
BEGIN
    IF p_conta_origem_id = p_conta_destino_id THEN
        RAISE EXCEPTION 'Conta origem e destino não podem ser iguais';
    END IF;

    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'Valor da transferência deve ser maior que zero';
    END IF;

    -- 1) Saída da conta origem
    INSERT INTO public.transacoes (
        empresa_id,
        conta_id,
        descricao,
        valor,
        tipo,
        data_movimento,
        classificacao,
        forma_pagamento,
        tipo_evento,
        origem
    )
    VALUES (
        p_empresa_id,
        p_conta_origem_id,
        COALESCE(p_historico, 'Transferência entre contas próprias'),
        abs(p_valor),
        'saida',
        p_data_mov,
        'despesa',
        'transferencia',
        'financeiro',
        'transferencia'
    )
    RETURNING id INTO v_id_saida;

    -- 2) Entrada na conta destino
    INSERT INTO public.transacoes (
        empresa_id,
        conta_id,
        descricao,
        valor,
        tipo,
        data_movimento,
        classificacao,
        forma_pagamento,
        tipo_evento,
        origem 
    )
    VALUES (
        p_empresa_id,
        p_conta_destino_id,
        COALESCE(p_historico, 'Transferência entre contas próprias'),
        abs(p_valor),
        'entrada',
        p_data_mov,
        'receita',
        'transferencia',
        'financeiro',
        'transferencia' 
    )
    RETURNING id INTO v_id_entrada;

    -- vincula a saída com a entrada
   --- UPDATE public.transacoes
   -- SET origem_id = v_id_entrada
    --WHERE id = v_id_saida;

    RETURN jsonb_build_object(
        'ok', true,
        'mensagem', 'Transferência criada com sucesso',
        'transacao_saida_id', v_id_saida,
        'transacao_entrada_id', v_id_entrada,
        'conta_origem_id', p_conta_origem_id,
        'conta_destino_id', p_conta_destino_id,
        'valor', abs(p_valor)
    );
END;
$$;