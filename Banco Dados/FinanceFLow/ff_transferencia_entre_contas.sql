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
    v_lote_id  bigint;  
    v_chave text;
    v_transferencia_id bigint;
 
BEGIN


    IF p_conta_origem_id = p_conta_destino_id THEN
        RAISE EXCEPTION 'Conta origem e destino não podem ser iguais';
    END IF;

    IF p_valor IS NULL OR p_valor <= 0 THEN
        RAISE EXCEPTION 'Valor da transferência deve ser maior que zero';
    END IF;
 
 

        v_chave :=
        p_empresa_id || '|' ||
        p_data_mov || '|' ||
        p_conta_origem_id || '|' ||
        p_conta_destino_id || '|' ||
        ROUND(ABS(p_valor), 2)::text;

        IF EXISTS (
                SELECT 1
                FROM public.transferencia_contas
                WHERE empresa_id = p_empresa_id
                    AND chave = v_chave
                ) THEN
                RETURN jsonb_build_object(
                    'ok', false,
                    'erro', 'Transferência duplicada. Já existe uma transferência igual registrada.',
                    'chave', v_chave
                );
                END IF;

    v_lote_id := nextval('contab.lote_id_seq');


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
        origem,
        lote_transferencia 
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
        'transferencia',
         v_lote_id
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
        origem , 
        lote_transferencia 
         
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
        'transferencia' ,
        v_lote_id
    )
    RETURNING id INTO v_id_entrada;

  INSERT INTO public.transferencia_contas (
  empresa_id,
  data_mov,
  origem_id,
  destino_id,
  valor,
  historico,
  lote_id,
  origem_registro,
  chave
)
VALUES (
  p_empresa_id,
  p_data_mov,
  p_conta_origem_id,
  p_conta_destino_id,
  ABS(p_valor),
  COALESCE(p_historico, 'Transferência entre contas próprias'),
  v_lote_id,
  'web',
  v_chave
)
RETURNING id INTO v_transferencia_id;

    RETURN jsonb_build_object(
        'ok', true,
        'mensagem', 'Transferência criada com sucesso',
        'transacao_saida_id', v_id_saida,
        'transacao_entrada_id', v_id_entrada,
        'conta_origem_id', p_conta_origem_id,
        'conta_destino_id', p_conta_destino_id,
        'valor', abs(p_valor),
        'lote_transferencia', v_lote_id
    );
END;
$$;