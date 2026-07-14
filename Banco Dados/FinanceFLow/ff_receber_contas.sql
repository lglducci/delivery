  CREATE OR REPLACE FUNCTION ff_receber_contas(
  p_empresa_id BIGINT,
  p_lista_ids JSON,
  p_conta_id BIGINT 
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_id BIGINT;
  v_modelo_codigo TEXT; 
  v_contabil_id BIGINT;
   v_classificacao TEXT;
  v_forma_recebimento TEXT;
  v_tipo_evento TEXT;
BEGIN

  SELECT cf.contabil_id
    INTO v_contabil_id
  FROM contas_financeiras cf
  WHERE cf.empresa_id = p_empresa_id
    AND cf.id = p_conta_id;

  IF v_contabil_id IS NULL THEN
    RAISE EXCEPTION 'Conta financeira % sem contabil_id.', p_conta_id;
  END IF;

  

  FOR v_id IN SELECT json_array_elements_text(p_lista_ids)::BIGINT LOOP

    SELECT c.classificacao,
          c.forma_recebimento
    INTO v_classificacao,
        v_forma_recebimento
    FROM contas_a_receber c
    WHERE c.id = v_id
      AND c.empresa_id = p_empresa_id 
  AND c.status = 'aberto';
 


 IF v_forma_recebimento = 'aprazo' THEN
    v_tipo_evento := 'aprazo';

ELSIF v_forma_recebimento = 'cartao_credito' THEN
    v_tipo_evento := 'cartao_recebimento';
    v_classificacao := 'baixa_ativo';

END IF;


    v_modelo_codigo := contab.ff_get_modelo_evento(
    p_empresa_id,
     v_classificacao,
      v_tipo_evento
  );


    INSERT INTO transacoes(
      empresa_id,
      conta_id,
      categoria_id,
      tipo,
      valor,
      data_movimento,
      descricao,
      receber_id,
      evento_codigo,
      origem,
      classificacao,
      contabil_id
    )
    SELECT 
      c.empresa_id,
      p_conta_id,
      NULL,
      'entrada',
      c.valor,
      CURRENT_DATE,
      c.descricao,
      c.id,
      v_modelo_codigo,
      'Recebimento',
      c.classificacao,
      v_contabil_id
    FROM contas_a_receber c 
    WHERE c.id = v_id
      AND c.empresa_id = p_empresa_id
      AND c.status = 'aberto';

    UPDATE contas_a_receber
    SET 
      status = 'recebido',
      data_recebimento = CURRENT_DATE
    WHERE id = v_id 
      AND empresa_id = p_empresa_id
      AND status = 'aberto';

  END LOOP;

  PERFORM contab.marcar_reprocessamento(p_empresa_id, CURRENT_DATE);

  RETURN 'Contas recebidas com sucesso';
END;
$$;