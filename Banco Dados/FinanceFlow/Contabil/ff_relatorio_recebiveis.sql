  CREATE OR REPLACE FUNCTION contab.ff_relatorio_recebiveis(
    p_empresa_id BIGINT,
    p_data_inicio DATE,
    p_data_fim DATE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_resultado JSONB;
BEGIN

    ------------------------------------------------------------------
    -- VALIDAÇÕES
    ------------------------------------------------------------------

    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'Empresa não informada.';
    END IF;

    IF p_data_inicio IS NULL OR p_data_fim IS NULL THEN
        RAISE EXCEPTION 'Período não informado.';
    END IF;

    IF p_data_inicio > p_data_fim THEN
        RAISE EXCEPTION
            'Data inicial não pode ser maior que a data final.';
    END IF;


    ------------------------------------------------------------------
    -- RELATÓRIO
    ------------------------------------------------------------------

    WITH lotes_contabeis AS (

        SELECT
            l.empresa_id,
            l.lote_id,
            MAX(l.modelo_id) AS modelo_id_gravado,
            MIN(l.id) AS lancamento_id,
            MIN(l.data_mov) AS data_mov,
            MAX(l.historico) AS historico,
            GREATEST(
                SUM(COALESCE(l.debito, 0)),
                SUM(COALESCE(l.credito, 0))
            )::NUMERIC(14,2) AS valor
        FROM contab.lancamentos l
        WHERE l.empresa_id = p_empresa_id
        GROUP BY l.empresa_id, l.lote_id
    ),

    eventos AS (

        SELECT
            lc.empresa_id,
            COALESCE(m_gravado.id, m_inferido.id) AS modelo_id,
            COALESCE(m_gravado.codigo, m_inferido.codigo) AS modelo_codigo,
            COALESCE(m_gravado.nome, m_inferido.nome) AS modelo_nome,
            lc.lote_id,
            lc.lancamento_id,
            lc.data_mov,
            lc.historico,
            lc.valor

        FROM lotes_contabeis lc

        LEFT JOIN contab.modelos m_gravado
            ON m_gravado.id = lc.modelo_id_gravado
           AND m_gravado.empresa_id = lc.empresa_id
           AND m_gravado.codigo IN (
               'RECEBER_CARTAO',
               'CRIA_RECEBER_RECEITA',
               'RECEBER_PIX',
               'TAXA_RECEBIVEL_CREDITO',
               'TAXA_RECEBIVEL_DEBITO',
               'TAXA_RECEBIVEL_PIX',
               'REC_CRED_TRANS',
               'REC_DEB_TRANS',
               'REC_PIX_TRANS',
               'PAGTO_RECEBIVEIS'
           )

        LEFT JOIN LATERAL (
            SELECT
                m.id,
                m.codigo,
                m.nome
            FROM contab.modelos m
            WHERE m.empresa_id = lc.empresa_id
              AND m.ativo = TRUE
              AND m.codigo IN (
                  'RECEBER_CARTAO',
                  'CRIA_RECEBER_RECEITA',
                  'RECEBER_PIX',
                  'TAXA_RECEBIVEL_CREDITO',
                  'TAXA_RECEBIVEL_DEBITO',
                  'TAXA_RECEBIVEL_PIX',
                  'REC_CRED_TRANS',
                  'REC_DEB_TRANS',
                  'REC_PIX_TRANS'
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM contab.modelos_linhas ml
                  WHERE ml.modelo_id = m.id
                    AND ml.empresa_id = lc.empresa_id
                    AND ml.perna_fixa = TRUE
                    AND NOT EXISTS (
                        SELECT 1
                        FROM contab.lancamentos lx
                        WHERE lx.empresa_id = lc.empresa_id
                          AND lx.lote_id = lc.lote_id
                          AND lx.conta_id = ml.conta_id
                          AND (
                              (ml.dc = 'D' AND COALESCE(lx.debito, 0) > 0)
                              OR
                              (ml.dc = 'C' AND COALESCE(lx.credito, 0) > 0)
                          )
                    )
              )
              AND (
                  SELECT COUNT(*)
                  FROM contab.modelos_linhas ml2
                  WHERE ml2.modelo_id = m.id
                    AND ml2.empresa_id = lc.empresa_id
                    AND ml2.perna_fixa = TRUE
              ) = (
                  SELECT COUNT(*)
                  FROM contab.lancamentos lx2
                  WHERE lx2.empresa_id = lc.empresa_id
                    AND lx2.lote_id = lc.lote_id
                    AND (
                        COALESCE(lx2.debito, 0) > 0
                        OR COALESCE(lx2.credito, 0) > 0
                    )
              )
            ORDER BY m.id
            LIMIT 1
        ) m_inferido
            ON lc.modelo_id_gravado IS NULL

        WHERE m_gravado.id IS NOT NULL
           OR m_inferido.id IS NOT NULL
    ),


    eventos_classificados AS (

        SELECT
            e.*,

            CASE

                WHEN e.modelo_codigo = 'RECEBER_CARTAO'
                    THEN 'CREDITO'

                WHEN e.modelo_codigo = 'CRIA_RECEBER_RECEITA'
                    THEN 'DEBITO'

                WHEN e.modelo_codigo = 'RECEBER_PIX'
                    THEN 'PIX'

                WHEN e.modelo_codigo = 'TAXA_RECEBIVEL_CREDITO'
                    THEN 'CREDITO'

                WHEN e.modelo_codigo = 'TAXA_RECEBIVEL_DEBITO'
                    THEN 'DEBITO'

                WHEN e.modelo_codigo = 'TAXA_RECEBIVEL_PIX'
                    THEN 'PIX'

                WHEN e.modelo_codigo = 'REC_CRED_TRANS'
                    THEN 'CREDITO'

                WHEN e.modelo_codigo = 'REC_DEB_TRANS'
                    THEN 'DEBITO'

                WHEN e.modelo_codigo = 'REC_PIX_TRANS'
                    THEN 'PIX'

                WHEN e.modelo_codigo = 'PAGTO_RECEBIVEIS'
                    THEN 'BANCO'

                ELSE 'OUTRO'

            END AS forma,


            CASE

                WHEN e.modelo_codigo IN (
                    'RECEBER_CARTAO',
                    'CRIA_RECEBER_RECEITA',
                    'RECEBER_PIX'
                )
                THEN 'RECEBIVEL_GERADO'


                WHEN e.modelo_codigo IN (
                    'TAXA_RECEBIVEL_CREDITO',
                    'TAXA_RECEBIVEL_DEBITO',
                    'TAXA_RECEBIVEL_PIX'
                )
                THEN 'TAXA'


                WHEN e.modelo_codigo IN (
                    'REC_CRED_TRANS',
                    'REC_DEB_TRANS',
                    'REC_PIX_TRANS'
                )
                THEN 'TRANSITORIA'


                WHEN e.modelo_codigo = 'PAGTO_RECEBIVEIS'
                THEN 'RECEBIDO'


                ELSE 'OUTRO'

            END AS tipo_evento_relatorio,

         /*   CASE
                WHEN e.modelo_codigo IN (
                    'REC_CRED_TRANS',
                    'REC_DEB_TRANS',
                    'REC_PIX_TRANS'
                )
                THEN e.valor

                WHEN e.modelo_codigo = 'PAGTO_RECEBIVEIS'
                THEN -e.valor

                ELSE 0
            END::NUMERIC(14,2) AS valor_assinado*/



            CASE
                WHEN e.modelo_codigo IN (
                    'REC_CRED_TRANS',
                    'REC_DEB_TRANS',
                    'REC_PIX_TRANS'
                )
                THEN e.valor

                WHEN e.modelo_codigo IN (
                    'TAXA_RECEBIVEL_CREDITO',
                    'TAXA_RECEBIVEL_DEBITO',
                    'TAXA_RECEBIVEL_PIX'
                )
                THEN -e.valor

                WHEN e.modelo_codigo = 'PAGTO_RECEBIVEIS'
                THEN -e.valor

                ELSE e.valor
            END::NUMERIC(14,2) AS valor_assinado

        FROM eventos e
    ),


    ------------------------------------------------------------------
    -- RESUMO DO PERÍODO X -> Y
    ------------------------------------------------------------------

    resumo_periodo AS (

        SELECT

            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE tipo_evento_relatorio = 'RECEBIVEL_GERADO'
                      AND data_mov BETWEEN p_data_inicio AND p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS recebiveis_brutos,


            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE tipo_evento_relatorio = 'TAXA'
                      AND data_mov BETWEEN p_data_inicio AND p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS taxas,


            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE tipo_evento_relatorio = 'TRANSITORIA'
                      AND data_mov BETWEEN p_data_inicio AND p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS enviados_transitoria,


            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE tipo_evento_relatorio = 'RECEBIDO'
                      AND data_mov BETWEEN p_data_inicio AND p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS recebido_banco

        FROM eventos_classificados
    ),


    ------------------------------------------------------------------
    -- POSIÇÃO DA TRANSITÓRIA NA DATA FINAL
    --
    -- entradas:
    -- REC_CRED_TRANS
    -- REC_DEB_TRANS
    -- REC_PIX_TRANS
    --
    -- saídas:
    -- PAGTO_RECEBIVEIS
    ------------------------------------------------------------------

    posicao AS (

        SELECT

            COALESCE(
                SUM(
                    CASE

                        WHEN tipo_evento_relatorio = 'TRANSITORIA'
                             AND data_mov <= p_data_fim
                        THEN valor

                        WHEN tipo_evento_relatorio = 'RECEBIDO'
                             AND data_mov <= p_data_fim
                        THEN -valor

                        ELSE 0

                    END
                ),
                0
            )::NUMERIC(14,2)
            AS saldo_transitoria,



            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE tipo_evento_relatorio = 'RECEBIDO'
                      AND data_mov <= p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS recebido_acumulado

        FROM eventos_classificados
    ),


    ------------------------------------------------------------------
    -- RECEBÍVEIS FUTUROS > Y
    --
    -- Aqui está justamente a parte que resolve o problema:
    -- cartão que ainda vai cair depois da data consultada.
    ------------------------------------------------------------------

    futuros AS (

        SELECT

            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE tipo_evento_relatorio = 'TRANSITORIA'
                      AND data_mov > p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS total,


            COUNT(*)
                FILTER (
                    WHERE tipo_evento_relatorio = 'TRANSITORIA'
                      AND data_mov > p_data_fim
                )
            AS quantidade,


            MIN(data_mov)
                FILTER (
                    WHERE tipo_evento_relatorio = 'TRANSITORIA'
                      AND data_mov > p_data_fim
                )
            AS primeira_data,


            MAX(data_mov)
                FILTER (
                    WHERE tipo_evento_relatorio = 'TRANSITORIA'
                      AND data_mov > p_data_fim
                )
            AS ultima_data,


            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE modelo_codigo = 'REC_CRED_TRANS'
                      AND data_mov > p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS credito,


            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE modelo_codigo = 'REC_DEB_TRANS'
                      AND data_mov > p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS debito,


            COALESCE(
                SUM(valor)
                FILTER (
                    WHERE modelo_codigo = 'REC_PIX_TRANS'
                      AND data_mov > p_data_fim
                ),
                0
            )::NUMERIC(14,2)
            AS pix

        FROM eventos_classificados
    ),


    ------------------------------------------------------------------
    -- DETALHES DO PERÍODO
    ------------------------------------------------------------------

    detalhes_periodo AS (

        SELECT COALESCE(
            JSONB_AGG(
                JSONB_BUILD_OBJECT(

                    'lancamento_id',
                    lancamento_id,

                    'lote_id',
                    lote_id,

                    'data',
                    data_mov,

                    'historico',
                    historico,

                    'modelo_codigo',
                    modelo_codigo,

                    'modelo_nome',
                    modelo_nome,

                    'tipo',
                    tipo_evento_relatorio,

                    'forma',
                    forma,

                    'valor',
                    valor,

                    'valor_assinado',
                    valor_assinado
                )
                ORDER BY
                    data_mov,
                    lancamento_id
            ),
            '[]'::JSONB
        ) AS itens

        FROM eventos_classificados

        WHERE data_mov
              BETWEEN p_data_inicio
                  AND p_data_fim
    ),


    ------------------------------------------------------------------
    -- DETALHES FUTUROS
    ------------------------------------------------------------------

    detalhes_futuros AS (

        SELECT COALESCE(
            JSONB_AGG(
                JSONB_BUILD_OBJECT(

                    'lancamento_id',
                    lancamento_id,

                    'lote_id',
                    lote_id,

                    'data_prevista',
                    data_mov,

                    'historico',
                    historico,

                    'modelo_codigo',
                    modelo_codigo,

                    'forma',
                    forma,

                    'valor',
                    valor,

                    'valor_assinado',
                    valor_assinado
                )
                ORDER BY
                    data_mov,
                    lancamento_id
            ),
            '[]'::JSONB
        ) AS itens

        FROM eventos_classificados

        WHERE tipo_evento_relatorio = 'TRANSITORIA'
          AND data_mov > p_data_fim
    )


    ------------------------------------------------------------------
    -- JSON FINAL
    ------------------------------------------------------------------

    SELECT JSONB_BUILD_OBJECT(

        'ok',
        TRUE,

        'empresa_id',
        p_empresa_id,

        'periodo',
        JSONB_BUILD_OBJECT(
            'data_inicio',
            p_data_inicio,

            'data_fim',
            p_data_fim
        ),


        --------------------------------------------------------------
        -- MOVIMENTO ENTRE X E Y
        --------------------------------------------------------------

        'resumo',
        JSONB_BUILD_OBJECT(

            'recebiveis_brutos',
            rp.recebiveis_brutos,

            'taxas',
            rp.taxas,

            'recebiveis_liquidos',
            rp.recebiveis_brutos - rp.taxas,

            'enviados_transitoria',
            rp.enviados_transitoria,

            'recebido_banco_periodo',
            rp.recebido_banco,

            'recebido_banco_ate_data_fim',
            pos.recebido_acumulado,

            'saldo_transitoria_data_fim',
            pos.saldo_transitoria,

            'recebiveis_futuros',
            fut.total
        ),


        --------------------------------------------------------------
        -- POSIÇÃO FUTURA
        --------------------------------------------------------------

        'futuros',
        JSONB_BUILD_OBJECT(

            'total',
            fut.total,

            'quantidade',
            fut.quantidade,

            'primeira_data',
            fut.primeira_data,

            'ultima_data',
            fut.ultima_data,

            'credito',
            fut.credito,

            'debito',
            fut.debito,

            'pix',
            fut.pix
        ),


        --------------------------------------------------------------
        -- DETALHAMENTO
        --------------------------------------------------------------

        'itens_periodo',
        dp.itens,

        'itens_futuros',
        df.itens

    )
    INTO v_resultado

    FROM resumo_periodo rp
    CROSS JOIN posicao pos
    CROSS JOIN futuros fut
    CROSS JOIN detalhes_periodo dp
    CROSS JOIN detalhes_futuros df;


    RETURN v_resultado;

END;
$$;