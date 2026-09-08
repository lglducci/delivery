CREATE OR REPLACE FUNCTION contab.ff_reclassifica_lancamento_importado(
    p_empresa_id          BIGINT,
    p_conta_financeira_id BIGINT,
    p_lote_id             BIGINT,
    p_conta_alterada_id   BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_conta_banco_id       BIGINT;
    v_diario_id            BIGINT;
    v_transacao_id         BIGINT;
    v_qtd_lancamentos      INTEGER;
    v_qtd_perna_banco      INTEGER;
    v_qtd_alterados        INTEGER;
BEGIN
    ------------------------------------------------------------
    -- Valida parâmetros
    ------------------------------------------------------------
    IF COALESCE(p_empresa_id, 0) = 0 THEN
        RAISE EXCEPTION 'Empresa não informada.';
    END IF;

    IF COALESCE(p_conta_financeira_id, 0) = 0 THEN
        RAISE EXCEPTION 'Conta financeira não informada.';
    END IF;

    IF COALESCE(p_lote_id, 0) = 0 THEN
        RAISE EXCEPTION 'Lote não informado.';
    END IF;

    IF COALESCE(p_conta_alterada_id, 0) = 0 THEN
        RAISE EXCEPTION 'Nova conta contábil não informada.';
    END IF;

    ------------------------------------------------------------
    -- Busca a conta contábil correspondente à conta financeira
    -- Ajuste o nome da tabela se não for public.contas_financeiras
    ------------------------------------------------------------
    SELECT cf.contabil_id
    INTO v_conta_banco_id
    FROM public.contas_financeiras cf
    WHERE cf.id = p_conta_financeira_id
      AND cf.empresa_id = p_empresa_id;

    IF v_conta_banco_id IS NULL THEN
        RAISE EXCEPTION
            'Conta financeira % não possui conta contábil vinculada.',
            p_conta_financeira_id;
    END IF;

    ------------------------------------------------------------
    -- Valida a nova conta contábil
    ------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM contab.contas c
        WHERE c.id = p_conta_alterada_id
          AND c.empresa_id = p_empresa_id
    ) THEN
        RAISE EXCEPTION
            'Conta contábil % não encontrada para a empresa %.',
            p_conta_alterada_id,
            p_empresa_id;
    END IF;

    IF p_conta_alterada_id = v_conta_banco_id THEN
        RAISE EXCEPTION
            'A nova conta não pode ser a própria conta bancária.';
    END IF;

    ------------------------------------------------------------
    -- Localiza diário e transação do lote
    ------------------------------------------------------------
    SELECT
        l.diario_id,
        d.transacao_id
    INTO
        v_diario_id,
        v_transacao_id
    FROM contab.lancamentos l
    JOIN contab.diario d
      ON d.id = l.diario_id
     AND d.empresa_id = p_empresa_id
    WHERE l.empresa_id = p_empresa_id
      AND l.lote_id = p_lote_id
    LIMIT 1;

    IF v_diario_id IS NULL THEN
        RAISE EXCEPTION
            'Lote % não encontrado para a empresa %.',
            p_lote_id,
            p_empresa_id;
    END IF;

    ------------------------------------------------------------
    -- O lote deve possuir duas pernas
    ------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_qtd_lancamentos
    FROM contab.lancamentos l
    WHERE l.empresa_id = p_empresa_id
      AND l.lote_id = p_lote_id
      AND l.diario_id = v_diario_id;

    IF v_qtd_lancamentos <> 2 THEN
        RAISE EXCEPTION
            'O lote % possui % lançamentos. Esperados: 2.',
            p_lote_id,
            v_qtd_lancamentos;
    END IF;

    ------------------------------------------------------------
    -- Deve existir exatamente uma perna bancária
    ------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_qtd_perna_banco
    FROM contab.lancamentos l
    WHERE l.empresa_id = p_empresa_id
      AND l.lote_id = p_lote_id
      AND l.diario_id = v_diario_id
      AND l.conta_id = v_conta_banco_id;

    IF v_qtd_perna_banco <> 1 THEN
        RAISE EXCEPTION
            'Não foi encontrada exatamente uma perna bancária no lote %. Encontradas: %.',
            p_lote_id,
            v_qtd_perna_banco;
    END IF;

    ------------------------------------------------------------
    -- Altera somente a contrapartida
    -- Não importa se está no débito ou no crédito
    ------------------------------------------------------------
    UPDATE contab.lancamentos
    SET conta_id = p_conta_alterada_id
    WHERE empresa_id = p_empresa_id
      AND lote_id = p_lote_id
      AND diario_id = v_diario_id
      AND conta_id <> v_conta_banco_id;

    GET DIAGNOSTICS v_qtd_alterados = ROW_COUNT;

    IF v_qtd_alterados <> 1 THEN
        RAISE EXCEPTION
            'Reclassificação inválida. Foram alteradas % pernas; esperado: 1.',
            v_qtd_alterados;
    END IF;

    ------------------------------------------------------------
    -- Mantém o diário atualizado para futuros reprocessamentos
    ------------------------------------------------------------
    UPDATE contab.diario
    SET contabil_id = p_conta_alterada_id
    WHERE id = v_diario_id
      AND empresa_id = p_empresa_id;

    ------------------------------------------------------------
    -- Mantém a transação atualizada para futuros reprocessamentos
    ------------------------------------------------------------
    UPDATE public.transacoes
    SET contabil_id = p_conta_alterada_id
    WHERE id = v_transacao_id
      AND empresa_id = p_empresa_id;

    RETURN jsonb_build_object(
        'ok', true,
        'message', 'Lançamento reclassificado com sucesso.',
        'empresa_id', p_empresa_id,
        'conta_financeira_id', p_conta_financeira_id,
        'conta_banco_id', v_conta_banco_id,
        'conta_alterada_id', p_conta_alterada_id,
        'lote_id', p_lote_id,
        'diario_id', v_diario_id,
        'transacao_id', v_transacao_id
    );
END;
$$;