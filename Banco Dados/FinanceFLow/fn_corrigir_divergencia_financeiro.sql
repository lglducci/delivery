CREATE OR REPLACE FUNCTION public.fn_corrigir_divergencia_financeiro(
    p_empresa_id bigint,
    p_conciliacao_id bigint,
    p_acao text,
    p_nova_data date DEFAULT NULL,
    p_nova_conta_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_acao text;

    v_transacao_id bigint;
    v_data_antiga date;
    v_data_nova date;

    v_conta_antiga_id bigint;
    v_conta_nova_id bigint;

    v_data_reprocessar date;

    v_pagar_id bigint;
    v_receber_id bigint;
    v_fatura_id bigint;
BEGIN
    ------------------------------------------------------------------
    -- 1) NORMALIZA A AÇÃO
    ------------------------------------------------------------------
    v_acao := upper(trim(COALESCE(p_acao, '')));

    IF v_acao NOT IN ('ALTERAR_DATA', 'ALTERAR_CONTA') THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Ação inválida. Use ALTERAR_DATA ou ALTERAR_CONTA.'
        );
    END IF;

    ------------------------------------------------------------------
    -- 2) LOCALIZA E TRAVA A DIVERGÊNCIA
    ------------------------------------------------------------------
    SELECT
        c.transacao_id
    INTO
        v_transacao_id
    FROM public.conciliacao_financeira c
    WHERE c.id = p_conciliacao_id
      AND c.empresa_id = p_empresa_id
      AND c.tipo_evento = 'divergencia_financeiro'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Divergência financeira não encontrada.'
        );
    END IF;

    IF v_transacao_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'A divergência não possui uma transação vinculada.'
        );
    END IF;

    ------------------------------------------------------------------
    -- 3) LOCALIZA E TRAVA A TRANSAÇÃO
    ------------------------------------------------------------------
    SELECT
        t.data_movimento,
        t.conta_id,
        t.pagar_id,
        t.receber_id,
        t.fatura_id
    INTO
        v_data_antiga,
        v_conta_antiga_id,
        v_pagar_id,
        v_receber_id,
        v_fatura_id
    FROM public.transacoes t
    WHERE t.id = v_transacao_id
      AND t.empresa_id = p_empresa_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Transação vinculada à divergência não foi encontrada.'
        );
    END IF;

    ------------------------------------------------------------------
    -- 4) ALTERAR DATA
    ------------------------------------------------------------------
    IF v_acao = 'ALTERAR_DATA' THEN

        IF p_nova_data IS NULL THEN
            RETURN jsonb_build_object(
                'ok', false,
                'message', 'Informe a nova data do lançamento.'
            );
        END IF;

        IF p_nova_data = v_data_antiga THEN
            RETURN jsonb_build_object(
                'ok', false,
                'message', 'A nova data é igual à data atual da transação.'
            );
        END IF;

        v_data_nova := p_nova_data;

        -- Deve reprocessar desde a menor data:
        -- desfaz na antiga e refaz na nova.
        v_data_reprocessar := LEAST(v_data_antiga, v_data_nova);

        UPDATE public.transacoes
           SET data_movimento = v_data_nova
         WHERE id = v_transacao_id
           AND empresa_id = p_empresa_id;

        PERFORM contab.marcar_reprocessamento(
            p_empresa_id,
            v_data_reprocessar
        );

    ------------------------------------------------------------------
    -- 5) ALTERAR CONTA FINANCEIRA
    ------------------------------------------------------------------
    ELSIF v_acao = 'ALTERAR_CONTA' THEN

        IF p_nova_conta_id IS NULL THEN
            RETURN jsonb_build_object(
                'ok', false,
                'message', 'Informe a nova conta financeira.'
            );
        END IF;

        IF p_nova_conta_id = v_conta_antiga_id THEN
            RETURN jsonb_build_object(
                'ok', false,
                'message', 'A nova conta é igual à conta atual da transação.'
            );
        END IF;

        ------------------------------------------------------------------
        -- Confere se a nova conta pertence à empresa
        ------------------------------------------------------------------
        IF NOT EXISTS (
            SELECT 1
            FROM public.contas_financeiras cf
            WHERE cf.id = p_nova_conta_id
              AND cf.empresa_id = p_empresa_id
        ) THEN
            RETURN jsonb_build_object(
                'ok', false,
                'message', 'Nova conta financeira não encontrada para esta empresa.'
            );
        END IF;

        v_conta_nova_id := p_nova_conta_id;
        v_data_reprocessar := v_data_antiga;

        UPDATE public.transacoes
           SET conta_id = v_conta_nova_id
         WHERE id = v_transacao_id
           AND empresa_id = p_empresa_id;

        -- A data não mudou, mas a perna contábil do banco mudou.
        PERFORM contab.marcar_reprocessamento(
            p_empresa_id,
            v_data_reprocessar
        );

    END IF;

    ------------------------------------------------------------------
    -- 6) REMOVE A LINHA TÉCNICA DA DIVERGÊNCIA
    --
    -- A transação foi corrigida. Essa linha não veio do extrato;
    -- foi criada apenas para o usuário resolver o problema.
    ------------------------------------------------------------------
    DELETE FROM public.conciliacao_financeira
    WHERE id = p_conciliacao_id
      AND empresa_id = p_empresa_id
      AND tipo_evento = 'divergencia_financeiro'
      AND transacao_id = v_transacao_id;

    ------------------------------------------------------------------
    -- 7) RETORNO
    ------------------------------------------------------------------
    RETURN jsonb_build_object(
        'ok', true,
        'message',
            CASE
                WHEN v_acao = 'ALTERAR_DATA' THEN
                    'Data da transação alterada e reprocessamento contábil marcado.'
                ELSE
                    'Conta financeira alterada e reprocessamento contábil marcado.'
            END,

        'acao', v_acao,
        'conciliacao_id', p_conciliacao_id,
        'transacao_id', v_transacao_id,

        'data_antiga', v_data_antiga,
        'data_nova',
            CASE
                WHEN v_acao = 'ALTERAR_DATA'
                    THEN v_data_nova
                ELSE v_data_antiga
            END,

        'conta_antiga_id', v_conta_antiga_id,
        'conta_nova_id',
            CASE
                WHEN v_acao = 'ALTERAR_CONTA'
                    THEN v_conta_nova_id
                ELSE v_conta_antiga_id
            END,

        'data_reprocessar_de', v_data_reprocessar,

        'vinculos', jsonb_build_object(
            'pagar_id', v_pagar_id,
            'receber_id', v_receber_id,
            'fatura_id', v_fatura_id
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', SQLERRM,
            'acao', v_acao,
            'conciliacao_id', p_conciliacao_id,
            'transacao_id', v_transacao_id
        );
END;
$$;