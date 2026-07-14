CREATE OR REPLACE FUNCTION contab.ff_corrigir_pernas_modelos_sistema(
  p_empresa_id BIGINT
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- começa zerando tudo para os modelos do sistema
  UPDATE contab.modelos_linhas ml
  SET perna_fixa = false
  FROM contab.modelos m
  WHERE m.id = ml.modelo_id
    AND m.empresa_id = p_empresa_id
    AND ml.empresa_id = p_empresa_id
    AND m.codigo IN (
      'RECEITA_VISTA',
      'DESPESA_VISTA',
      'CRIA_PAGAR_DESPESA',
      'PAGAMENTO_PAGAR',
      'CRIA_RECEBER_RECEITA',
      'RECEBER_CARTAO',
      'RECEBIMENTO_RECEBER',
      'CRIA_CARTAO_COMPRA',
      'PAGAMENTO_CARTAO'
    );

  -- crédito fixo
  UPDATE contab.modelos_linhas ml
  SET perna_fixa = true
  FROM contab.modelos m
  WHERE m.id = ml.modelo_id
    AND m.empresa_id = p_empresa_id
    AND ml.empresa_id = p_empresa_id
    AND ml.dc = 'C'
    AND m.codigo IN (
      'CRIA_PAGAR_DESPESA',
      'RECEBIMENTO_RECEBER',
      'CRIA_CARTAO_COMPRA',
     'DESPESA_VISTA'
    );

  -- débito fixo
  UPDATE contab.modelos_linhas ml
  SET perna_fixa = true
  FROM contab.modelos m
  WHERE m.id = ml.modelo_id
    AND m.empresa_id = p_empresa_id
    AND ml.empresa_id = p_empresa_id
    AND ml.dc = 'D'
    AND m.codigo IN (
  'RECEITA_VISTA', 
  'CRIA_RECEBER_RECEITA',
  'RECEBER_CARTAO',
  'PAGAMENTO_PAGAR',
  'PAGAMENTO_CARTAO'
);


 
END;
$$;