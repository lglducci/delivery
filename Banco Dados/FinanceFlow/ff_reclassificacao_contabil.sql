DROP FUNCTION IF EXISTS public.ff_reclassificacao_contabil(
  bigint,
  bigint,
  bigint,
  text,
  date
);

CREATE OR REPLACE FUNCTION public.ff_reclassificacao_contabil(
  p_id bigint,
  p_empresa_id bigint,
  p_contabil_id bigint,
  p_tipo_operacao text,
  p_data_movimento date
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_qtd integer := 0;
  v_ultimo_dia_processado date;
  v_data_reprocessar_de date;
BEGIN
  IF p_id IS NULL
     OR p_empresa_id IS NULL
     OR p_contabil_id IS NULL
     OR p_tipo_operacao IS NULL
     OR p_data_movimento IS NULL THEN

    RETURN jsonb_build_object(
      'ok', false,
      'erro', 'Parâmetros obrigatórios: id, empresa_id, contabil_id, tipo_operacao, data_movimento'
    );
  END IF;

 
/*

    SELECT cf.ultimo_dia_processado,
  COALESCE(cf.data_reprocessar_de, cf.ultimo_dia_processado)
INTO
  v_ultimo_dia_processado,
  v_data_reprocessar_de
FROM contab.controle_fechamento cf
WHERE cf.empresa_id = p_empresa_id;



 IF v_ultimo_dia_processado IS NOT NULL
   AND p_data_movimento < v_data_reprocessar_de THEN

    RETURN jsonb_build_object(
      'ok', false,
      'bloqueado', true,
      'erro', 'Este movimento já está dentro de um período contabilmente processado. Não é permitido alterar a conta contábil.',
      'data_movimento', p_data_movimento,
      'data_reprocessar_de', v_data_reprocessar_de,
      'ultimo_dia_processado', v_ultimo_dia_processado
    );
  END IF;
*/


  IF p_tipo_operacao = 'conta_pagar' THEN

    UPDATE public.contas_a_pagar
    SET contabil_id = p_contabil_id
    WHERE id = p_id
      AND empresa_id = p_empresa_id;

    GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ELSIF p_tipo_operacao = 'conta_receber' THEN

    UPDATE public.contas_a_receber
    SET contabil_id = p_contabil_id
    WHERE id = p_id
      AND empresa_id = p_empresa_id;

    GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ELSIF p_tipo_operacao = 'cartao_compra' THEN

    UPDATE public.cartoes_compras
    SET conta_contabil_id = p_contabil_id
    WHERE id = p_id
      AND empresa_id = p_empresa_id;

    GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ELSIF p_tipo_operacao = 'transacao' THEN

    UPDATE public.transacoes
    SET contabil_id = p_contabil_id
    WHERE id = p_id
      AND empresa_id = p_empresa_id;

    GET DIAGNOSTICS v_qtd = ROW_COUNT;

  ELSIF p_tipo_operacao = 'fatura_cartao' THEN

    RETURN jsonb_build_object(
      'ok', false,
      'erro', 'Fatura de cartão não permite reclassificação contábil direta.'
    );

  ELSE

    RETURN jsonb_build_object(
      'ok', false,
      'erro', 'Tipo de operação inválido: ' || p_tipo_operacao
    );

  END IF;


  PERFORM contab.marcar_reprocessamento(
     p_empresa_id,
    p_data_movimento
  );


  IF v_qtd = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'erro', 'Nenhum registro atualizado.',
      'id', p_id,
      'empresa_id', p_empresa_id,
      'tipo_operacao', p_tipo_operacao
    );
  END IF;

   RETURN jsonb_build_object(
  'ok', true,
  'bloqueado', false,
  'mensagem', 'Conta contábil atualizada com sucesso.',
  'id', p_id,
  'empresa_id', p_empresa_id,
  'contabil_id', p_contabil_id,
  'tipo_operacao', p_tipo_operacao,
  'data_movimento', p_data_movimento,
  'ultimo_dia_processado', v_ultimo_dia_processado,
  'data_reprocessar_de', v_data_reprocessar_de
);

END;
$$;