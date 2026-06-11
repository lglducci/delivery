 CREATE OR REPLACE FUNCTION contab.gerar_lancamentos_por_diario(
    p_diario_id BIGINT,
    p_empresa_id BIGINT
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_diario      contab.diario%ROWTYPE;
  v_modelo      contab.modelos%ROWTYPE;
  r_linha       contab.modelos_linhas%ROWTYPE;
  v_valor       NUMERIC(14,2);
  v_deb_count   INT := 0;
  v_cred_count  INT := 0;
  v_lote_id     BIGINT;

  v_conta_contabil_id BIGINT;
  v_conta_codigo TEXT;
  v_conta_final BIGINT;
BEGIN

  -- 1) Diário
  SELECT * INTO v_diario
  FROM contab.diario
  WHERE id = p_diario_id
    AND empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Diário % não encontrado.', p_diario_id;
  END IF;

  -- ignora tipos que não devem gerar lançamentos aqui
  IF v_diario.modelo_codigo IN ('PAGAR','RECEBER','COMPRA_CARTAO')
     OR v_diario.modelo_codigo LIKE 'ESTORNO%'
  THEN
    RAISE NOTICE 'Diário % ignorado. modelo_codigo=%',
      p_diario_id,
      v_diario.modelo_codigo;
    RETURN;
  END IF;

  IF v_diario.valor_total IS NULL OR v_diario.valor_total = 0 THEN
    RAISE NOTICE 'Diário % ignorado: valor_total nulo ou zero.', p_diario_id;
    RETURN;
  END IF;

  v_lote_id := nextval('contab.lote_id_seq');
  v_valor := v_diario.valor_total;

  v_conta_contabil_id :=
      NULLIF(v_diario.outros ->> 'conta_contabil_id', '')::BIGINT;

  -- 2) Modelo
  SELECT * INTO v_modelo
  FROM contab.modelos
  WHERE codigo = v_diario.modelo_codigo
    AND empresa_id = p_empresa_id
    AND ativo = TRUE;

  IF NOT FOUND THEN
    RAISE NOTICE 'Diário % ignorado: modelo % não encontrado ou inativo.',
      p_diario_id,
      v_diario.modelo_codigo;
    RETURN;
  END IF;

  -- 3) Limpa lançamentos anteriores
  DELETE FROM contab.lancamentos
  WHERE diario_id = p_diario_id
    AND empresa_id = p_empresa_id;

  -- 4) Loop linhas modelo
  FOR r_linha IN
    SELECT *
    FROM contab.modelos_linhas
    WHERE modelo_id = v_modelo.id
      AND empresa_id = p_empresa_id
    ORDER BY ordem
  LOOP

    IF r_linha.dc NOT IN ('D','C') THEN
      RAISE NOTICE 'Linha modelo ignorada: dc inválido. modelo=%, dc=%',
        v_modelo.codigo,
        r_linha.dc;
      CONTINUE;
    END IF;

    v_conta_final := r_linha.conta_id;

    SELECT codigo
    INTO v_conta_codigo
    FROM contab.contas
    WHERE id = r_linha.conta_id;

    IF v_conta_contabil_id IS NOT NULL
       AND v_conta_codigo LIKE '1.1.1%'
       AND COALESCE(r_linha.perna_fixa, true) = true
       AND r_linha.conta_id <> v_conta_contabil_id
    THEN
       v_conta_final := v_conta_contabil_id;
    END IF;

    IF v_diario.contabil_id IS NOT NULL
       AND COALESCE(r_linha.perna_fixa, true) = false
       AND r_linha.conta_id <> v_diario.contabil_id
    THEN
       v_conta_final := v_diario.contabil_id;
    END IF;

    INSERT INTO contab.lancamentos (
      empresa_id,
      diario_id,
      data_mov,
      conta_id,
      historico,
      debito,
      credito,
      modelo_id,
      lote_id
    )
    VALUES (
      p_empresa_id,
      v_diario.id,
      v_diario.data_mov,
      v_conta_final,
      v_diario.historico,
      CASE WHEN r_linha.dc = 'D' THEN v_valor ELSE 0 END,
      CASE WHEN r_linha.dc = 'C' THEN v_valor ELSE 0 END,
      v_modelo.id,
      v_lote_id
    );

    IF r_linha.dc = 'D' THEN
      v_deb_count := v_deb_count + 1;
    ELSE
      v_cred_count := v_cred_count + 1;
    END IF;

  END LOOP;

  -- 5) Validação final
  IF v_deb_count = 0 OR v_cred_count = 0 THEN
    RAISE NOTICE 'Diário % ignorado: modelo % sem débito/crédito suficiente.',
      p_diario_id,
      v_modelo.codigo;
    RETURN;
  END IF;

END;
$$;