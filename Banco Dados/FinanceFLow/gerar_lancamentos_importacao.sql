 CREATE OR REPLACE FUNCTION contab.gerar_lancamentos_importacao(
    p_diario_id BIGINT,
    p_empresa_id BIGINT
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_diario contab.diario%ROWTYPE;
    v_valor NUMERIC(14,2);
    v_lote_id BIGINT;

    v_tipo TEXT;
    v_importacao_id TEXT;

    v_conta_banco_id BIGINT;
    v_conta_contrapartida_id BIGINT;
BEGIN
    v_lote_id := nextval('contab.lote_id_seq');

    SELECT *
    INTO v_diario
    FROM contab.diario
    WHERE id = p_diario_id
      AND empresa_id = p_empresa_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Diário % não encontrado para empresa %.', p_diario_id, p_empresa_id;
    END IF;

    IF v_diario.valor_total IS NULL OR v_diario.valor_total = 0 THEN
        RAISE EXCEPTION 'Diário % sem valor_total válido.', p_diario_id;
    END IF;

    --v_importacao_id := NULLIF(v_diario.outros ->> 'importacao_id', '');
    v_tipo := NULLIF(v_diario.outros ->> 'tipo', '');

    -- conta banco/caixa vem do JSON outros
    v_conta_banco_id :=
        NULLIF(v_diario.outros ->> 'conta_contabil_id', '')::BIGINT;

    -- contrapartida: tenta categoria_id/conta_contrapartida_id se existir no JSON
    v_conta_contrapartida_id := v_diario.contabil_id;
   --   COALESCE(
    --       NULLIF(v_diario.outros ->> 'conta_contrapartida_id', '')::BIGINT,
    --    NULLIF(v_diario.outros ->> 'categoria_contabil_id', '')::BIGINT
   --  );

    --IF v_importacao_id IS NULL THEN
    --    RAISE EXCEPTION 'Diário % não é de importação.', p_diario_id;
   -- END IF;

    IF v_tipo NOT IN ('entrada', 'saida') THEN
        RAISE EXCEPTION 'Tipo inválido no diário %. Tipo recebido: %', p_diario_id, v_tipo;
    END IF;

    IF v_conta_banco_id IS NULL THEN
        RAISE EXCEPTION 'Diário % sem conta bancária em outros.conta_contabil_id.', p_diario_id;
    END IF;

    IF v_conta_contrapartida_id IS NULL THEN
        PERFORM contab.gerar_lancamentos_por_diario(p_diario_id, p_empresa_id);
        RETURN;
    END IF;

    v_valor := ABS(v_diario.valor_total);

    DELETE FROM contab.lancamentos
    WHERE diario_id = p_diario_id
      AND empresa_id = p_empresa_id;

    IF v_tipo = 'entrada' THEN

        INSERT INTO contab.lancamentos (
            empresa_id, diario_id, data_mov, conta_id,
            historico, debito, credito, lote_id
        )
        VALUES (
            p_empresa_id, v_diario.id, v_diario.data_mov, v_conta_banco_id,
            v_diario.historico, v_valor, 0, v_lote_id
        );

        INSERT INTO contab.lancamentos (
            empresa_id, diario_id, data_mov, conta_id,
            historico, debito, credito, lote_id
        )
        VALUES (
            p_empresa_id, v_diario.id, v_diario.data_mov, v_conta_contrapartida_id,
            v_diario.historico, 0, v_valor, v_lote_id
        );

    ELSE

        INSERT INTO contab.lancamentos (
            empresa_id, diario_id, data_mov, conta_id,
            historico, debito, credito, lote_id
        )
        VALUES (
            p_empresa_id, v_diario.id, v_diario.data_mov, v_conta_contrapartida_id,
            v_diario.historico, v_valor, 0, v_lote_id
        );

        INSERT INTO contab.lancamentos (
            empresa_id, diario_id, data_mov, conta_id,
            historico, debito, credito, lote_id
        )
        VALUES (
            p_empresa_id, v_diario.id, v_diario.data_mov, v_conta_banco_id,
            v_diario.historico, 0, v_valor, v_lote_id
        );

    END IF;
END;
$$;