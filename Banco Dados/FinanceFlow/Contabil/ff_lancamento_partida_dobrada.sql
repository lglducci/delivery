 CREATE OR REPLACE FUNCTION contab.ff_lancamento_partida_dobrada (
    p_empresa_id        BIGINT,
    p_conta_debito_id   BIGINT,
    p_conta_credito_id  BIGINT,
    p_valor             NUMERIC(14,2),
    p_historico         TEXT,
    p_data_lanc         DATE,
    p_lembrete          BOOLEAN,
    p_data_vencimento   DATE,
    p_lote_id           BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_lote_id BIGINT;
    v_importacao_id BIGINT;
BEGIN
    IF p_valor <= 0 THEN
        RAISE EXCEPTION 'Valor deve ser maior que zero';
    END IF;

    IF p_conta_debito_id = p_conta_credito_id THEN
        RAISE EXCEPTION 'Conta débito e crédito não podem ser a mesma';
    END IF;

    v_lote_id := nextval('contab.lote_id_seq');

    IF COALESCE(p_lote_id, 0) > 0 THEN
        v_importacao_id := p_lote_id;
    ELSE
        v_importacao_id := NULL;
    END IF;

    INSERT INTO contab.lancamentos (
        empresa_id,
        diario_id,
        data_mov,
        conta_id,
        debito,
        credito,
        historico,
        criado_em,
        lote_id,
        importacao_id,
        origem
    ) VALUES (
        p_empresa_id,
        0,
        p_data_lanc,
        p_conta_debito_id,
        p_valor,
        0,
        p_historico,
        NOW(),
        v_lote_id,
        v_importacao_id,
        'CONTABIL'
    );

    INSERT INTO contab.lancamentos (
        empresa_id,
        diario_id,
        data_mov,
        conta_id,
        debito,
        credito,
        historico,
        criado_em,
        lote_id,
        importacao_id,
        origem
    ) VALUES (
        p_empresa_id,
        0,
        p_data_lanc,
        p_conta_credito_id,
        0,
        p_valor,
        p_historico,
        NOW(),
        v_lote_id,
        v_importacao_id,
        'CONTABIL'
    );

    IF p_lembrete = TRUE THEN
        IF p_data_vencimento IS NULL THEN
            RAISE EXCEPTION 'Data de vencimento é obrigatória quando lembrete estiver ativo';
        END IF;

        INSERT INTO contab.lembretes (
            empresa_id,
            lote_id,
            tipo,
            descricao,
            valor,
            data_vencimento
        ) VALUES (
            p_empresa_id,
            v_lote_id,
            'Lembrete',
            p_historico,
            p_valor,
            p_data_vencimento
        );
    END IF;
END;
$$;