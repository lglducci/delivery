 CREATE OR REPLACE FUNCTION public.ff_resolver_transferencia_mesma_titularidade(
  p_empresa_id bigint,
  p_lote_id bigint,
  p_id bigint,
  p_conciliacao_id bigint,
  p_conta_origem_id bigint,
  p_conta_destino_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_chave text;
  v_valor numeric;
  v_data_mov date;
  v_historico text;
BEGIN
  IF p_conta_origem_id IS NULL OR p_conta_destino_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Informe conta origem e conta destino.');
  END IF;

  IF p_conta_origem_id = p_conta_destino_id THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Conta origem e destino não podem ser iguais.');
  END IF;

  SELECT valor, data_mov, historico
  INTO v_valor, v_data_mov, v_historico
  FROM public.conciliacao_financeira
  WHERE id = p_id
    AND empresa_id = p_empresa_id
    AND lote_conciliacao_id = p_lote_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Conciliação não encontrada para este lote.'
    );
  END IF;

 v_chave :=
  p_empresa_id || '|' ||
  v_data_mov || '|' ||
  p_conta_origem_id || '|' ||
  p_conta_destino_id || '|' ||
  ROUND(ABS(v_valor), 2)::text;

  IF EXISTS (
    SELECT 1
    FROM public.transferencia_contas
    WHERE empresa_id = p_empresa_id
      AND chave = v_chave
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Transferência duplicada. Já existe uma transferência igual registrada.',
      'chave', v_chave
    );
  END IF;

  UPDATE public.conciliacao_financeira
  SET
    conta_financeira_id = p_conta_origem_id,
    destino_id = p_conta_destino_id,
    status_conciliacao = 'ok',
    mensagem_conciliacao = 'Transferência de mesma titularidade resolvida manualmente',
    importar = true
  WHERE id = p_id
    AND empresa_id = p_empresa_id
    AND lote_conciliacao_id = p_lote_id;

  RETURN jsonb_build_object(
    'ok', true,
    'message', 'Transferência resolvida com sucesso.',
    'conciliacao_id', p_id,
    'lote_id', p_lote_id,
    'chave', v_chave
  );
END;
$$;