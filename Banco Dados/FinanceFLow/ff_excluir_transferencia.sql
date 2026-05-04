CREATE OR REPLACE FUNCTION public.ff_excluir_transferencia(
  p_empresa_id bigint,
  p_lote_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_qtd_fin int;
  v_qtd_contab int;
BEGIN



  DELETE FROM public.transacoes
  WHERE empresa_id = p_empresa_id
    AND lote_transferencia = p_lote_id;

  GET DIAGNOSTICS v_qtd_fin = ROW_COUNT;

  DELETE FROM contab.lancamentos
  WHERE empresa_id = p_empresa_id
    AND (lote_id = p_lote_id   OR importacao_id = p_lote_id);

  GET DIAGNOSTICS v_qtd_contab = ROW_COUNT;

 

  RETURN jsonb_build_object(
    'ok', true,
    'mensagem', 'Transferência excluída com sucesso',
    'lote_id', p_lote_id,
    'transacoes_excluidas', v_qtd_fin,
    'lancamentos_contabeis_excluidos', v_qtd_contab
  );
END;
$$;