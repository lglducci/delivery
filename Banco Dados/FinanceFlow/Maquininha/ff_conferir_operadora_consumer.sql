 CREATE OR REPLACE FUNCTION public.ff_conferir_operadora_consumer(
    p_empresa_id BIGINT,
    p_conta_financeira_id BIGINT,
    p_operadora TEXT,
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
    -- 1. VALIDAÇÕES
    ------------------------------------------------------------------

    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'Empresa não informada.';
    END IF;

    IF p_data_inicio IS NULL OR p_data_fim IS NULL THEN
        RAISE EXCEPTION
            'Informe data inicial e data final para a conferência.';
    END IF;

    IF p_data_inicio > p_data_fim THEN
        RAISE EXCEPTION
            'Data inicial não pode ser maior que a data final.';
    END IF;

    IF NULLIF(TRIM(p_operadora), '') IS NULL THEN
        RAISE EXCEPTION 'Operadora não informada.';
    END IF;


    ------------------------------------------------------------------
    -- 2. MOVIMENTOS DA OPERADORA
    ------------------------------------------------------------------

    WITH movimentos AS (

        SELECT
            om.id AS operadora_movimento_id,
            om.importacao_id,
            om.empresa_id,

            oi.operadora,

            om.tipo_movimento,

            om.data_movimento::date
                AS data_movimento,

            om.data_prevista_pagamento::date
                AS data_prevista_pagamento,

            om.forma_pagamento,
            om.bandeira,
            om.modalidade,

            om.status
                AS status_operadora,

            om.parcelas,

            COALESCE(om.valor_bruto, 0)::numeric(14,2)
                AS valor_bruto,

            COALESCE(om.valor_taxa, 0)::numeric(14,2)
                AS valor_taxa,

            COALESCE(om.valor_liquido, 0)::numeric(14,2)
                AS valor_liquido,

            om.autorizacao,
            om.comprovante_venda,
            om.transacao_origem,

            om.chave_registro,
            om.chave_match_operadora,

            COALESCE(
                NULLIF(TRIM(om.status_processamento), ''),
                'ABERTO'
            ) AS status_processamento,

            om.processado_em,
            om.processamento_erro

        FROM public.operadora_movimentos om

        JOIN public.operadora_importacoes oi
          ON oi.id = om.importacao_id

        WHERE om.empresa_id = p_empresa_id
          AND oi.empresa_id = p_empresa_id

          AND UPPER(oi.operadora)
              = UPPER(p_operadora)

          AND om.data_movimento::date
              BETWEEN p_data_inicio
                  AND p_data_fim
    ),


    ------------------------------------------------------------------
    -- 3. CLASSIFICA O QUE O FINANCEFLOW DEVE FAZER
    ------------------------------------------------------------------

    diagnostico AS (

        SELECT
            m.*,


            ----------------------------------------------------------
            -- MOVIMENTO PODE SER PROCESSADO?
            ----------------------------------------------------------

            CASE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) IN (
                    'NEGADA',
                    'NEGADO'
                )
                THEN FALSE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) LIKE '%EXPIR%'
                THEN FALSE

                WHEN m.status_processamento = 'PROCESSADO'
                THEN FALSE

                ELSE TRUE

            END AS acao_necessaria,


            ----------------------------------------------------------
            -- SITUAÇÃO PARA A UI
            ----------------------------------------------------------

            CASE

                WHEN m.status_processamento = 'PROCESSADO'
                THEN 'REALIZADO'

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) IN (
                    'NEGADA',
                    'NEGADO'
                )
                THEN 'NAO_PROCESSAVEL'

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) LIKE '%EXPIR%'
                THEN 'NAO_PROCESSAVEL'

                ELSE 'PENDENTE'

            END AS situacao,


            ----------------------------------------------------------
            -- GERAR VENDA
            ----------------------------------------------------------
            --
            -- Neste novo fluxo a operadora é a origem da venda.
            ----------------------------------------------------------

            CASE

                WHEN m.status_processamento = 'PROCESSADO'
                THEN FALSE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) IN ('NEGADA', 'NEGADO')
                THEN FALSE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) LIKE '%EXPIR%'
                THEN FALSE

                ELSE TRUE

            END AS gerar_venda,


            ----------------------------------------------------------
            -- GERAR TAXA
            ----------------------------------------------------------

            CASE

                WHEN m.status_processamento = 'PROCESSADO'
                THEN FALSE

                WHEN COALESCE(m.valor_taxa, 0) = 0
                THEN FALSE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) IN ('NEGADA', 'NEGADO')
                THEN FALSE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) LIKE '%EXPIR%'
                THEN FALSE

                ELSE TRUE

            END AS gerar_taxa,


            ----------------------------------------------------------
            -- ENVIAR LÍQUIDO PARA TRANSITÓRIA
            ----------------------------------------------------------

            CASE

                WHEN m.status_processamento = 'PROCESSADO'
                THEN FALSE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) IN ('NEGADA', 'NEGADO')
                THEN FALSE

                WHEN UPPER(
                    COALESCE(m.status_operadora, '')
                ) LIKE '%EXPIR%'
                THEN FALSE

                WHEN COALESCE(m.valor_liquido, 0) = 0
                THEN FALSE

                ELSE TRUE

            END AS enviar_transitoria

        FROM movimentos m
    ),


    ------------------------------------------------------------------
    -- 4. TEXTO PARA A UI
    ------------------------------------------------------------------

    resultado AS (

        SELECT
            d.*,

            CASE

                WHEN d.situacao = 'REALIZADO'
                THEN 'Processamento realizado'

                WHEN d.situacao = 'NAO_PROCESSAVEL'
                THEN 'Nenhuma ação'

                ELSE 'Processar'

            END AS acao,


            CASE

                WHEN d.situacao = 'REALIZADO'
                THEN
                    'Movimento já processado pelo FinanceFlow.'

                WHEN UPPER(
                    COALESCE(d.status_operadora, '')
                ) IN ('NEGADA', 'NEGADO')
                THEN
                    'Transação negada pela operadora. Nenhum lançamento será gerado.'

                WHEN UPPER(
                    COALESCE(d.status_operadora, '')
                ) LIKE '%EXPIR%'
                THEN
                    'Transação não liquidável. Nenhum lançamento será gerado.'

                WHEN d.gerar_taxa
                THEN
                    'Venda pendente. Serão reconhecidos a venda, a taxa da operadora e o valor líquido em trânsito.'

                ELSE
                    'Venda pendente. Será reconhecida a venda e o valor líquido em trânsito.'

            END AS mensagem

        FROM diagnostico d
    )


    ------------------------------------------------------------------
    -- 5. JSON
    ------------------------------------------------------------------

    SELECT JSONB_BUILD_OBJECT(

        'ok',
        TRUE,

        'empresa_id',
        p_empresa_id,

        'operadora',
        UPPER(p_operadora),

        /*
          Mantido temporariamente para não quebrar a UI/webhook.
          Não participa mais da conferência.
        */
        'conta_financeira_id',
        p_conta_financeira_id,

        'data_inicio',
        p_data_inicio,

        'data_fim',
        p_data_fim,


        --------------------------------------------------------------
        -- RESUMO
        --------------------------------------------------------------

        'resumo',
        JSONB_BUILD_OBJECT(

            'total',
            COUNT(*),

            'pendentes',
            COUNT(*) FILTER (
                WHERE situacao = 'PENDENTE'
            ),

            'realizados',
            COUNT(*) FILTER (
                WHERE situacao = 'REALIZADO'
            ),

            'nao_processaveis',
            COUNT(*) FILTER (
                WHERE situacao = 'NAO_PROCESSAVEL'
            ),

            'com_taxa',
            COUNT(*) FILTER (
                WHERE situacao = 'PENDENTE'
                  AND gerar_taxa = TRUE
            ),

            'sem_taxa',
            COUNT(*) FILTER (
                WHERE situacao = 'PENDENTE'
                  AND gerar_taxa = FALSE
            ),

           'total_bruto',
                COALESCE(
                    SUM(valor_bruto)
                        FILTER (
                            WHERE situacao <> 'NAO_PROCESSAVEL'
                        ),
                    0
                ),

                'total_taxas',
                COALESCE(
                    SUM(valor_taxa)
                        FILTER (
                            WHERE situacao <> 'NAO_PROCESSAVEL'
                        ),
                    0
                ),

                'total_liquido',
                COALESCE(
                    SUM(valor_liquido)
                        FILTER (
                            WHERE situacao <> 'NAO_PROCESSAVEL'
                        ),
                    0
                ),

                'rejeitado_bruto',
                COALESCE(
                    SUM(valor_bruto)
                        FILTER (
                            WHERE situacao = 'NAO_PROCESSAVEL'
                        ),
                    0
                ),

                'rejeitado_taxas',
                COALESCE(
                    SUM(valor_taxa)
                        FILTER (
                            WHERE situacao = 'NAO_PROCESSAVEL'
                        ),
                    0
                ),

                'rejeitado_liquido',
                COALESCE(
                    SUM(valor_liquido)
                        FILTER (
                            WHERE situacao = 'NAO_PROCESSAVEL'
                        ),
                    0
                ),
            ----------------------------------------------------------
            -- VALORES QUE AINDA SERÃO PROCESSADOS
            ----------------------------------------------------------

            'pendente_bruto',
            COALESCE(
                SUM(valor_bruto)
                    FILTER (
                        WHERE situacao = 'PENDENTE'
                    ),
                0
            ),

            'pendente_taxas',
            COALESCE(
                SUM(valor_taxa)
                    FILTER (
                        WHERE situacao = 'PENDENTE'
                    ),
                0
            ),

            'pendente_liquido',
            COALESCE(
                SUM(valor_liquido)
                    FILTER (
                        WHERE situacao = 'PENDENTE'
                    ),
                0
            )

        ),


        --------------------------------------------------------------
        -- ITENS
        --------------------------------------------------------------

        'itens',
        COALESCE(

            JSONB_AGG(

                JSONB_BUILD_OBJECT(

                    'operadora_movimento_id',
                    operadora_movimento_id,

                    'importacao_id',
                    importacao_id,

                    'situacao',
                    situacao,

                    'status_processamento',
                    status_processamento,

                    'acao_necessaria',
                    acao_necessaria,

                    'acao',
                    acao,

                    'mensagem',
                    mensagem,

                    'processado_em',
                    processado_em,

                    'processamento_erro',
                    processamento_erro,


                    --------------------------------------------------
                    -- DADOS DA OPERAÇÃO
                    --------------------------------------------------

                    'data',
                    data_movimento,

                    'data_prevista_pagamento',
                    data_prevista_pagamento,

                    'tipo_movimento',
                    tipo_movimento,

                    'forma',
                    forma_pagamento,

                    'bandeira',
                    bandeira,

                    'modalidade',
                    modalidade,

                    'status_operadora',
                    status_operadora,

                    'parcelas',
                    parcelas,

                    'valor_bruto',
                    valor_bruto,

                    'valor_taxa',
                    valor_taxa,

                    'valor_liquido',
                    valor_liquido,

                    'autorizacao',
                    autorizacao,

                    'comprovante_venda',
                    comprovante_venda,

                    'transacao_origem',
                    transacao_origem,

                    'chave_registro',
                    chave_registro,

                    'chave_match_operadora',
                    chave_match_operadora,


                    --------------------------------------------------
                    -- O QUE O BOTÃO FARÁ
                    --------------------------------------------------

                    'acoes',
                    JSONB_BUILD_OBJECT(

                        'gerar_venda',
                        gerar_venda,

                        'gerar_taxa',
                        gerar_taxa,

                        'enviar_transitoria',
                        enviar_transitoria

                    )

                )

                ORDER BY
                    data_movimento,
                    operadora_movimento_id
            ),

            '[]'::JSONB
        )

    )

    INTO v_resultado

    FROM resultado;


    ------------------------------------------------------------------
    -- 6. RETORNO
    ------------------------------------------------------------------

    RETURN v_resultado;

END;
$$;