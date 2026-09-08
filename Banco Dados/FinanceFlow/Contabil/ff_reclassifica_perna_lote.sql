DROP FUNCTION IF EXISTS contab.ff_reclassifica_perna_lote(
    BIGINT,
    BIGINT,
    TEXT,
    BIGINT
);

CREATE OR REPLACE FUNCTION contab.ff_reclassifica_perna_lote(
    p_empresa_id        BIGINT,
    p_lote_id           BIGINT,
    p_tipo              TEXT,
    p_nova_conta_id     BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
AS
$$
DECLARE
    v_tipo              TEXT;
    v_diario_id         BIGINT;
    v_lancamento_id     BIGINT;
    v_conta_anterior_id BIGINT;
    v_qtd_encontrada    INTEGER;
    v_qtd_alterada      INTEGER;
BEGIN
    v_tipo := UPPER(TRIM(COALESCE(p_tipo, '')));

    IF COALESCE(p_empresa_id, 0) = 0 THEN
        RAISE EXCEPTION 'Empresa não informada.';
    END IF;

    IF COALESCE(p_lote_id, 0) = 0 THEN
        RAISE EXCEPTION 'Lote não informado.';
    END IF;

    IF v_tipo NOT IN ('D', 'C') THEN
        RAISE EXCEPTION
            'Tipo inválido. Informe D para débito ou C para crédito.';
    END IF;

    IF COALESCE(p_nova_conta_id, 0) = 0 THEN
        RAISE EXCEPTION 'Nova conta contábil não informada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM contab.contas c
        WHERE c.id = p_nova_conta_id
          AND c.empresa_id = p_empresa_id
    ) THEN
        RAISE EXCEPTION
            'Conta contábil % não encontrada para a empresa %.',
            p_nova_conta_id,
            p_empresa_id;
    END IF;

    SELECT COUNT(*)
    INTO v_qtd_encontrada
    FROM contab.lancamentos l
    WHERE l.empresa_id = p_empresa_id
      AND l.lote_id = p_lote_id
      AND (
            (
                v_tipo = 'D'
                AND l.debito > 0
                AND l.credito = 0
            )
            OR
            (
                v_tipo = 'C'
                AND l.credito > 0
                AND l.debito = 0
            )
      );

    IF v_qtd_encontrada = 0 THEN
        RAISE EXCEPTION
            'Nenhuma perna % encontrada no lote %.',
            v_tipo,
            p_lote_id;
    END IF;

    IF v_qtd_encontrada > 1 THEN
        RAISE EXCEPTION
            'Foram encontradas % pernas do tipo % no lote %. Esperado: 1.',
            v_qtd_encontrada,
            v_tipo,
            p_lote_id;
    END IF;

    SELECT
        l.id,
        l.diario_id,
        l.conta_id
    INTO
        v_lancamento_id,
        v_diario_id,
        v_conta_anterior_id
    FROM contab.lancamentos l
    WHERE l.empresa_id = p_empresa_id
      AND l.lote_id = p_lote_id
      AND (
            (
                v_tipo = 'D'
                AND l.debito > 0
                AND l.credito = 0
            )
            OR
            (
                v_tipo = 'C'
                AND l.credito > 0
                AND l.debito = 0
            )
      )
    LIMIT 1;

    IF v_conta_anterior_id = p_nova_conta_id THEN
        RAISE EXCEPTION
            'A nova conta é igual à conta atual do lançamento.';
    END IF;

    UPDATE contab.lancamentos
    SET conta_id = p_nova_conta_id
    WHERE id = v_lancamento_id
      AND empresa_id = p_empresa_id
      AND lote_id = p_lote_id;

    GET DIAGNOSTICS v_qtd_alterada = ROW_COUNT;

    IF v_qtd_alterada <> 1 THEN
        RAISE EXCEPTION
            'Reclassificação inválida. Registros alterados: %.',
            v_qtd_alterada;
    END IF;

    RETURN jsonb_build_object(
        'ok', TRUE,
        'message', 'Lançamento reclassificado com sucesso.',
        'empresa_id', p_empresa_id,
        'lote_id', p_lote_id,
        'diario_id', v_diario_id,
        'lancamento_id', v_lancamento_id,
        'tipo', v_tipo,
        'conta_anterior_id', v_conta_anterior_id,
        'nova_conta_id', p_nova_conta_id
    );
END;
$$;