CREATE OR REPLACE FUNCTION public.fn_inserir_divergencias_financeiro(
    p_empresa_id bigint,
    p_conta_financeira_id bigint,
    p_lote_conciliacao_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_data_ini date;
    v_data_fim date;

    v_qtd_inseridos integer := 0;
    v_total_entradas numeric(14,2) := 0;
    v_total_saidas numeric(14,2) := 0;

    v_detalhes jsonb := '[]'::jsonb;
BEGIN
    ------------------------------------------------------------------
    -- 1) VALIDA O LOTE E OBTÉM O PERÍODO
    ------------------------------------------------------------------
    SELECT
        l.data_ini,
        l.data_fim
    INTO
        v_data_ini,
        v_data_fim
    FROM public.lote_conciliacao l
    WHERE l.id = p_lote_conciliacao_id
      AND l.empresa_id = p_empresa_id
      AND l.conta_financeira_id = p_conta_financeira_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message',
            'Lote de conciliação não encontrado para a empresa e conta informadas'
        );
    END IF;

    IF v_data_ini IS NULL OR v_data_fim IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message',
            'O lote de conciliação não possui período definido'
        );
    END IF;

    ------------------------------------------------------------------
    -- 2) REMOVE DIVERGÊNCIAS ANTERIORES DO MESMO LOTE
    --
    -- Permite executar novamente a função sem duplicar registros.
    ------------------------------------------------------------------
    DELETE FROM public.conciliacao_financeira c
    WHERE c.empresa_id = p_empresa_id
      AND c.conta_financeira_id = p_conta_financeira_id
      AND c.lote_conciliacao_id = p_lote_conciliacao_id
      AND c.tipo_evento = 'divergencia_financeiro'
      AND c.importar = false;

    ------------------------------------------------------------------
    -- 3) INSERE TRANSAÇÕES DO SISTEMA QUE NÃO APARECERAM NO EXTRATO
    ------------------------------------------------------------------
    WITH transacoes_sobrando AS (
        SELECT
            t.id AS transacao_id,
            t.empresa_id,
            t.conta_id,
            t.categoria_id,
            t.tipo,
            t.valor,
            t.descricao,
            t.data_movimento,
            t.origem,
            t.pagar_id,
            t.receber_id,
            t.fatura_id,
            t.evento_codigo,
            t.origem_id,
            t.tipo_evento,
            t.classificacao,
            t.forma_pagamento,
            t.importacao_id,
            t.contabil_id
        FROM public.transacoes t
        WHERE t.empresa_id = p_empresa_id
          AND t.conta_id = p_conta_financeira_id
          AND t.data_movimento BETWEEN v_data_ini AND v_data_fim

          --------------------------------------------------------------
          -- NÃO TRAZ TRANSAÇÃO QUE JÁ FOI VINCULADA AO EXTRATO
          --------------------------------------------------------------
          AND NOT EXISTS (
              SELECT 1
              FROM public.conciliacao_financeira c
              WHERE c.empresa_id = t.empresa_id
                AND c.conta_financeira_id = t.conta_id
                AND c.transacao_id = t.id
          )

          --------------------------------------------------------------
          -- NÃO TRAZ O PRÓPRIO LANÇAMENTO DE ESTORNO
          --
          -- O estorno aponta para a transação original por origem_id.
          --------------------------------------------------------------
          AND t.origem_id IS NULL

          --------------------------------------------------------------
          -- NÃO TRAZ A TRANSAÇÃO ORIGINAL QUE JÁ FOI ESTORNADA
          --------------------------------------------------------------
          AND NOT EXISTS (
              SELECT 1
              FROM public.transacoes est
              WHERE est.empresa_id = t.empresa_id
                AND est.origem_id = t.id
          )

          --------------------------------------------------------------
          -- PROTEÇÃO ADICIONAL POR CÓDIGO/NOME DO EVENTO
          --------------------------------------------------------------
          AND upper(COALESCE(t.evento_codigo, ''))
              NOT LIKE 'ESTORNO%'

          AND upper(COALESCE(t.tipo_evento::text, ''))
              NOT LIKE 'ESTORNO%'
    ),
    inseridos AS (
        INSERT INTO public.conciliacao_financeira (
            empresa_id,
            conta_financeira_id,
            data_mov,
            historico,
            valor,
            tipo,
            forma,
            classificacao,
            categoria_id,
            tipo_evento,
            transacao_id,
            pagar_id,
            receber_id,
            fatura_id,
            match_score,
            match_criterio,
            lote_conciliacao_id,
            chave_importacao,
            importar,
            status_conciliacao,
            mensagem_conciliacao,
            conta_id
        )
        SELECT
            t.empresa_id,
            t.conta_id,
            t.data_movimento,

            COALESCE(
                NULLIF(trim(t.descricao), ''),
                'Lançamento do sistema sem descrição'
            ),

            CASE
                WHEN t.tipo = 'saida' THEN -abs(t.valor)
                ELSE abs(t.valor)
            END,

            t.tipo,
            COALESCE(t.forma_pagamento, 'avista'),
            t.classificacao,
            t.categoria_id,

            'divergencia_financeiro',
            t.transacao_id,
            t.pagar_id,
            t.receber_id,
            t.fatura_id,

            0,

            concat(
                'divergencia_financeiro',
                '; transacao_id=', t.transacao_id,
                '; origem=', COALESCE(t.origem, ''),
                '; tipo_evento_original=', COALESCE(t.tipo_evento::text, ''),
                '; pagar_id=', COALESCE(t.pagar_id::text, ''),
                '; receber_id=', COALESCE(t.receber_id::text, ''),
                '; fatura_id=', COALESCE(t.fatura_id::text, ''),
                '; data=', t.data_movimento,
                '; valor=', t.valor
            ),

            p_lote_conciliacao_id,

            md5(
                'DIVERGENCIA_FINANCEIRO|' ||
                p_empresa_id::text || '|' ||
                p_conta_financeira_id::text || '|' ||
                t.transacao_id::text || '|' ||
                p_lote_conciliacao_id::text
            ),

            false,
            'pendente',

            CASE
                WHEN t.pagar_id IS NOT NULL THEN
                    'Pagamento existe no sistema, mas não foi encontrado no extrato'

                WHEN t.receber_id IS NOT NULL THEN
                    'Recebimento existe no sistema, mas não foi encontrado no extrato'

                WHEN t.fatura_id IS NOT NULL THEN
                    'Pagamento de fatura existe no sistema, mas não foi encontrado no extrato'

                ELSE
                    'Lançamento existe no sistema, mas não foi encontrado no extrato'
            END,

            t.contabil_id

        FROM transacoes_sobrando t

        RETURNING
            id,
            transacao_id,
            data_mov,
            historico,
            valor,
            tipo,
            pagar_id,
            receber_id,
            fatura_id,
            mensagem_conciliacao
    )
    SELECT
        COUNT(*)::integer,
        COALESCE(
            SUM(
                CASE
                    WHEN tipo = 'entrada' THEN abs(valor)
                    ELSE 0
                END
            ),
            0
        )::numeric(14,2),
        COALESCE(
            SUM(
                CASE
                    WHEN tipo = 'saida' THEN abs(valor)
                    ELSE 0
                END
            ),
            0
        )::numeric(14,2),
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'conciliacao_financeira_id', id,
                    'transacao_id', transacao_id,
                    'data', data_mov,
                    'historico', historico,
                    'valor', valor,
                    'tipo', tipo,
                    'pagar_id', pagar_id,
                    'receber_id', receber_id,
                    'fatura_id', fatura_id,
                    'mensagem', mensagem_conciliacao
                )
                ORDER BY data_mov, id
            ),
            '[]'::jsonb
        )
    INTO
        v_qtd_inseridos,
        v_total_entradas,
        v_total_saidas,
        v_detalhes
    FROM inseridos;

    ------------------------------------------------------------------
    -- 4) RETORNO
    ------------------------------------------------------------------
    RETURN jsonb_build_object(
        'ok', true,
        'empresa_id', p_empresa_id,
        'conta_financeira_id', p_conta_financeira_id,
        'lote_conciliacao_id', p_lote_conciliacao_id,

        'periodo', jsonb_build_object(
            'data_ini', v_data_ini,
            'data_fim', v_data_fim
        ),

        'resumo', jsonb_build_object(
            'divergencias_inseridas', v_qtd_inseridos,
            'total_entradas', v_total_entradas,
            'total_saidas', v_total_saidas,
            'saldo_liquido',
                v_total_entradas - v_total_saidas
        ),

        'detalhes', v_detalhes
    );
END;
$$;