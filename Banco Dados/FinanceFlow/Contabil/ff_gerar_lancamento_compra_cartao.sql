CREATE OR REPLACE FUNCTION contab.ff_gerar_lancamento_compra_cartao(
    p_diario_id  BIGINT,
    p_empresa_id BIGINT
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_diario           contab.diario%ROWTYPE;
    v_modelo           contab.modelos%ROWTYPE;
    v_valor            NUMERIC(14,2);

    v_conta_debito_id  BIGINT; -- NÃO fixa (compra)
    v_conta_credito_id BIGINT; -- FIXA (passivo cartão)
BEGIN
    -- 1) DIÁRIO (SÓ COMPRA_CARTAO)
    SELECT *
      INTO v_diario
      FROM contab.diario
     WHERE id = p_diario_id
       AND empresa_id = p_empresa_id
       AND modelo_codigo = 'COMPRA_CARTAO'; -- ajuste se no seu banco tiver acento

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Diário % não encontrado ou não é COMPRA_CARTAO.', p_diario_id;
    END IF;

    v_valor := v_diario.valor_total;
    IF v_valor IS NULL OR v_valor <= 0 THEN
      RAISE EXCEPTION 'Valor inválido no diário %.', p_diario_id;
    END IF;

    -- 2) MODELO PELO CÓDIGO
    SELECT *
      INTO v_modelo
      FROM contab.modelos
     WHERE empresa_id = p_empresa_id
       AND ativo = TRUE
       AND codigo = v_diario.modelo_codigo;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Modelo % não encontrado.', v_diario.modelo_codigo;
    END IF;

    -- 3) CONTA FIXA (CRÉDITO) = dc='C'
    SELECT ml.conta_id
      INTO v_conta_credito_id
      FROM contab.modelos_linhas ml
     WHERE ml.empresa_id = p_empresa_id
       AND ml.modelo_id = v_modelo.id
       AND ml.dc = 'C'
     LIMIT 1;

    IF v_conta_credito_id IS NULL THEN
      RAISE EXCEPTION 'Modelo % sem conta fixa (C).', v_modelo.codigo;
    END IF;

    -- 4) CONTA NÃO FIXA (DÉBITO) = vem do OUTROS.conta_contabil_id
    v_conta_debito_id :=
      NULLIF(TRIM(v_diario.outros ->> 'conta_contabil_id'), '')::BIGINT;

    -- fallback: se não veio no OUTROS, usa a linha D do modelo
    IF v_conta_debito_id IS NULL THEN
      SELECT ml.conta_id
        INTO v_conta_debito_id
        FROM contab.modelos_linhas ml
       WHERE ml.empresa_id = p_empresa_id
         AND ml.modelo_id = v_modelo.id
         AND ml.dc = 'D'
       LIMIT 1;

      IF v_conta_debito_id IS NULL THEN
        RAISE EXCEPTION 'Modelo % sem conta D (fallback).', v_modelo.codigo;
      END IF;
    END IF;

    -- 5) INSERT (CRIAR PASSIVO DO CARTÃO)
    INSERT INTO contab.lancamentos
      (empresa_id, diario_id, data_mov, conta_id, historico, debito, credito, modelo_id)
    VALUES
      (p_empresa_id, v_diario.id, v_diario.data_mov, v_conta_debito_id,  v_diario.historico, v_valor, 0,      v_modelo.id),
      (p_empresa_id, v_diario.id, v_diario.data_mov, v_conta_credito_id, v_diario.historico, 0,      v_valor, v_modelo.id);

END;
$$;
