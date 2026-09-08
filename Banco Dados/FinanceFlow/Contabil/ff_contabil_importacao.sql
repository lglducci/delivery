 DROP FUNCTION IF EXISTS contab.ff_contabil_importacao(
    BIGINT,
    BIGINT,
    DATE,
    DATE
);

CREATE OR REPLACE FUNCTION contab.ff_contabil_importacao(
    p_empresa_id BIGINT,
    p_conta_id BIGINT,
    p_data_inicio DATE,
    p_data_fim DATE
)
RETURNS TABLE (
    data_mov DATE,
    transacao_id BIGINT,
    diario_id BIGINT,
    lote_id BIGINT,

    conta_debito_codigo TEXT,
    conta_debito_nome TEXT,

    conta_credito_codigo TEXT,
    conta_credito_nome TEXT,

    valor NUMERIC,
    historico TEXT,
    modelo_codigo TEXT,

    origem_registro TEXT
)
LANGUAGE sql
AS $$
    WITH conta_selecionada AS (
        SELECT cf.contabil_id
        FROM public.contas_financeiras cf
        WHERE cf.id = p_conta_id
          AND cf.empresa_id = p_empresa_id
        LIMIT 1
    ),

    /*
        Lotes contábeis manuais que movimentaram a conta contábil
        vinculada à conta financeira selecionada.
    */
    lotes_manuais AS (
        SELECT DISTINCT l.lote_id
        FROM contab.lancamentos l

        JOIN conta_selecionada cs
            ON cs.contabil_id = l.conta_id

        WHERE l.empresa_id = p_empresa_id
          AND UPPER(COALESCE(l.origem, '')) = 'CONTABIL'
          AND l.data_mov BETWEEN p_data_inicio AND p_data_fim
          AND l.lote_id IS NOT NULL
    ),

   /*
    Movimentos gerados por transações/importações.

    Retorna um registro para cada lote contábil que realmente
    movimentou a conta contábil vinculada à conta financeira.
*/
movimentos_importacao AS (
    SELECT
        l.data_mov::DATE AS data_mov,

        t.id::BIGINT AS transacao_id,
        d.id::BIGINT AS diario_id,
        l.lote_id::BIGINT AS lote_id,

        MAX(
            CASE
                WHEN COALESCE(l.debito, 0) > 0
                THEN c.codigo
            END
        )::TEXT AS conta_debito_codigo,

        MAX(
            CASE
                WHEN COALESCE(l.debito, 0) > 0
                THEN c.nome
            END
        )::TEXT AS conta_debito_nome,

        MAX(
            CASE
                WHEN COALESCE(l.credito, 0) > 0
                THEN c.codigo
            END
        )::TEXT AS conta_credito_codigo,

        MAX(
            CASE
                WHEN COALESCE(l.credito, 0) > 0
                THEN c.nome
            END
        )::TEXT AS conta_credito_nome,

        MAX(
            CASE
                WHEN COALESCE(l.debito, 0) > 0
                THEN l.debito

                WHEN COALESCE(l.credito, 0) > 0
                THEN l.credito
            END
        )::NUMERIC AS valor,

        MAX(l.historico)::TEXT AS historico,

        d.modelo_codigo::TEXT AS modelo_codigo,

        'IMPORTACAO'::TEXT AS origem_registro

    FROM public.transacoes t

    JOIN contab.diario d
      ON d.transacao_id = t.id
     AND d.empresa_id = p_empresa_id

    JOIN contab.lancamentos l
      ON l.diario_id = d.id
     AND l.empresa_id = p_empresa_id

    JOIN contab.contas c
      ON c.id = l.conta_id
     AND c.empresa_id = p_empresa_id

    WHERE t.empresa_id = p_empresa_id

      /*
          Não usa t.conta_id, porque a transação pode estar vinculada
          à outra conta financeira, embora o lançamento contábil
          movimente a conta selecionada.
      */
      AND EXISTS (
          SELECT 1
          FROM contab.lancamentos l_conta

          JOIN conta_selecionada cs
            ON cs.contabil_id = l_conta.conta_id

          WHERE l_conta.empresa_id = p_empresa_id
            AND l_conta.diario_id = d.id
            AND l_conta.lote_id = l.lote_id
      )

      AND l.origem IS NULL

      AND l.data_mov
          BETWEEN p_data_inicio AND p_data_fim

    GROUP BY
        l.data_mov,
        t.id,
        d.id,
        l.lote_id,
        d.modelo_codigo
),
    /*
        Movimentos lançados diretamente no contábil.

        O lote entra nesta consulta quando pelo menos uma das pernas
        movimentou o contabil_id da conta financeira selecionada.
        Depois são buscadas todas as pernas desse lote.
    */
    movimentos_manuais AS (
        SELECT
            l.data_mov::DATE AS data_mov,

            MAX(d.transacao_id)::BIGINT AS transacao_id,
            MAX(l.diario_id)::BIGINT AS diario_id,

            l.lote_id::BIGINT AS lote_id,

            MAX(
                CASE
                    WHEN COALESCE(l.debito, 0) > 0
                    THEN c.codigo
                END
            )::TEXT AS conta_debito_codigo,

            MAX(
                CASE
                    WHEN COALESCE(l.debito, 0) > 0
                    THEN c.nome
                END
            )::TEXT AS conta_debito_nome,

            MAX(
                CASE
                    WHEN COALESCE(l.credito, 0) > 0
                    THEN c.codigo
                END
            )::TEXT AS conta_credito_codigo,

            MAX(
                CASE
                    WHEN COALESCE(l.credito, 0) > 0
                    THEN c.nome
                END
            )::TEXT AS conta_credito_nome,

            MAX(
                CASE
                    WHEN COALESCE(l.debito, 0) > 0
                    THEN l.debito

                    WHEN COALESCE(l.credito, 0) > 0
                    THEN l.credito
                END
            )::NUMERIC AS valor,

            MAX(l.historico)::TEXT AS historico,

            COALESCE(
                MAX(d.modelo_codigo),
                'CONTABIL'
            )::TEXT AS modelo_codigo,

            'MANUAL'::TEXT AS origem_registro

        FROM contab.lancamentos l

        JOIN lotes_manuais lm
            ON lm.lote_id = l.lote_id

        JOIN contab.contas c
            ON c.id = l.conta_id
           AND c.empresa_id = p_empresa_id

        LEFT JOIN contab.diario d
            ON d.id = l.diario_id
           AND d.empresa_id = p_empresa_id

        WHERE l.empresa_id = p_empresa_id
          AND l.data_mov
              BETWEEN p_data_inicio AND p_data_fim

        GROUP BY
            l.data_mov,
            l.lote_id
    )

    SELECT *
    FROM (
        SELECT *
        FROM movimentos_importacao

        UNION ALL

        SELECT *
        FROM movimentos_manuais
    ) movimentos

    ORDER BY
        movimentos.data_mov,
        movimentos.valor,
        movimentos.lote_id;
$$;