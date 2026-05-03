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
  v_qtd_transf int;
  v_qtd_conc int;
BEGIN
  IF p_conta_origem_id IS NULL OR p_conta_destino_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Informe conta origem e conta destino.');
  END IF;

  IF p_conta_origem_id = p_conta_destino_id THEN
    RETURN jsonb_build_object('ok', false, 'message', 'Conta origem e destino não podem ser iguais.');
  END IF;

  UPDATE public.transferencia_mesma_titularidade_pendente
  SET
    conta_origem_id = p_conta_origem_id,
    conta_destino_id = p_conta_destino_id,
    status = 'resolvido',
    executado_em = now()
  WHERE id = p_id
    AND empresa_id = p_empresa_id
    AND lote_conciliacao_id = p_lote_id
    AND conciliacao_id = p_conciliacao_id;

  GET DIAGNOSTICS v_qtd_transf = ROW_COUNT;

  UPDATE public.conciliacao_financeira
  SET
    status_conciliacao = 'ok',
    mensagem_conciliacao = 'Transferência de mesma titularidade resolvida manualmente',
    importar = false,
    lote_conciliacao_id = p_lote_id
  WHERE id = p_conciliacao_id
    AND empresa_id = p_empresa_id;

  GET DIAGNOSTICS v_qtd_conc = ROW_COUNT;

  IF v_qtd_transf = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Transferência não encontrada para este lote/conciliação.'
    );
  END IF;

  IF v_qtd_conc = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'message', 'Conciliação não encontrada.'
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'message', 'Transferência resolvida com sucesso.',
    'transferencia_id', p_id,
    'conciliacao_id', p_conciliacao_id,
    'lote_id', p_lote_id
  );
END;
$$;