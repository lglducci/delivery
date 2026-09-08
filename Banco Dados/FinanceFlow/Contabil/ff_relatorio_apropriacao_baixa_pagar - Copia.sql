 CREATE OR REPLACE FUNCTION contab.ff_relatorio_apropriacao_baixa_pagar(
    p_empresa_id BIGINT,
    p_data_ini DATE,
    p_data_fim DATE
)
RETURNS TABLE (
    chave_divida       TEXT,
    tipo_divida        TEXT,

    pagar_id           BIGINT,
    pagar_lote_id      BIGINT,

    parcela_num        BIGINT,
    parcelas           BIGINT,

    etapa              TEXT,
    data_apropriacao   DATE,
    data_movimento     DATE,
    vencimento         DATE,

    conta_debito       TEXT,
    conta_credito      TEXT,

    valor_total        NUMERIC,
    descricao          TEXT,
    status_conta       TEXT,

    diario_id          BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN

    ------------------------------------------------------------------
    -- VALIDAÇÕES
    ------------------------------------------------------------------
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'O parâmetro p_empresa_id é obrigatório.';
    END IF;

    IF p_data_ini IS NULL OR p_data_fim IS NULL THEN
        RAISE EXCEPTION 'As datas inicial e final são obrigatórias.';
    END IF;

    IF p_data_ini > p_data_fim THEN
        RAISE EXCEPTION
            'A data inicial (%) não pode ser maior que a data final (%).',
            p_data_ini,
            p_data_fim;
    END IF;


    RETURN QUERY

    WITH movimentos_diario AS (
        SELECT
            d.id AS diario_id,
            d.empresa_id,
            d.pagar_id,
            d.transacao_id,
            d.data_mov::DATE AS data_mov,
            d.valor_total,
            d.modelo_codigo,

            MAX(
                CASE
                    WHEN l.debito > 0
                    THEN c.codigo || ' - ' || c.nome
                END
            )::TEXT AS conta_debito,

            MAX(
                CASE
                    WHEN l.credito > 0
                    THEN c.codigo || ' - ' || c.nome
                END
            )::TEXT AS conta_credito

        FROM contab.diario d

        JOIN contab.lancamentos l
          ON l.empresa_id = d.empresa_id
         AND l.diario_id = d.id

        JOIN contab.contas c
          ON c.empresa_id = l.empresa_id
         AND c.id = l.conta_id

        WHERE d.empresa_id = p_empresa_id

        GROUP BY
            d.id,
            d.empresa_id,
            d.pagar_id,
            d.transacao_id,
            d.data_mov,
            d.valor_total,
            d.modelo_codigo
    ),

    ------------------------------------------------------------------
    -- CONTAS DE FORNECEDORES DA EMPRESA
    --
    -- Não existe conta fixa.
    --
    -- A conta é identificada observando qual conta recebeu crédito
    -- nas apropriações automáticas de contas a pagar.
    --
    -- A busca considera todo o histórico da empresa, não somente
    -- o período solicitado.
    ------------------------------------------------------------------
    contas_fornecedores AS (
        SELECT DISTINCT
            l.conta_id::BIGINT AS conta_id

        FROM contab.diario d

        JOIN contab.lancamentos l
          ON l.empresa_id = d.empresa_id
         AND l.diario_id = d.id

        WHERE d.empresa_id = p_empresa_id

          AND d.modelo_codigo IN (
              'CRIAR_PAGAR_CUSTO',
              'CRIA_PAGAR_DESPESA'
          )

          AND COALESCE(l.credito, 0) > 0
    ),

    ------------------------------------------------------------------
    -- APROPRIAÇÕES
    --
    -- O lote da conta a pagar é obtido por:
    --
    -- diario.pagar_id
    --      ↓
    -- contas_a_pagar.id
    --      ↓
    -- contas_a_pagar.lote_id
    --
    -- contab.diario.lote_id NÃO É USADO.
    ------------------------------------------------------------------
    apropriacoes_raw AS (
        SELECT
            md.empresa_id,
            md.diario_id,
            md.pagar_id,

            cp.lote_id::BIGINT AS pagar_lote_id,

            CASE
                WHEN COALESCE(cp.parcelas, 1) > 1
                 AND cp.lote_id IS NOT NULL
                THEN 'L-' || cp.lote_id::TEXT

                ELSE 'P-' || cp.id::TEXT
            END::TEXT AS chave_divida,

            CASE
                WHEN COALESCE(cp.parcelas, 1) > 1
                 AND cp.lote_id IS NOT NULL
                THEN 'PARCELADA'

                ELSE 'SIMPLES'
            END::TEXT AS tipo_divida,

            md.data_mov AS data_apropriacao,
            md.valor_total AS valor_apropriado,

            md.conta_debito,
            md.conta_credito,

            cp.fornecedor_id,
            cp.descricao::TEXT AS descricao,
            COALESCE(cp.parcelas, 1)::BIGINT AS parcelas

        FROM movimentos_diario md

        JOIN public.contas_a_pagar cp
          ON cp.empresa_id = md.empresa_id
         AND cp.id = md.pagar_id

        WHERE md.modelo_codigo IN (
            'CRIAR_PAGAR_CUSTO',
            'CRIA_PAGAR_DESPESA'
        )
    ),

    ------------------------------------------------------------------
    -- UMA APROPRIAÇÃO POR DÍVIDA
    ------------------------------------------------------------------
    apropriacoes AS (
        SELECT DISTINCT ON (
            ar.empresa_id,
            ar.chave_divida
        )
            ar.empresa_id,
            ar.chave_divida,
            ar.tipo_divida,

            ar.pagar_id,
            ar.pagar_lote_id,

            ar.data_apropriacao,
            ar.valor_apropriado,

            ar.conta_debito,
            ar.conta_credito,

            ar.diario_id,
            ar.fornecedor_id,
            ar.descricao,
            ar.parcelas

        FROM apropriacoes_raw ar

        ORDER BY
            ar.empresa_id,
            ar.chave_divida,
            ar.data_apropriacao,
            ar.diario_id
    ),

    ------------------------------------------------------------------
    -- BAIXAS AUTOMÁTICAS
    ------------------------------------------------------------------
    baixas AS (
        SELECT
            md.empresa_id,
            t.pagar_id,

            md.diario_id,
            md.data_mov AS data_baixa,
            md.valor_total AS valor_baixado,

            md.conta_debito,
            md.conta_credito

        FROM movimentos_diario md

        JOIN public.transacoes t
          ON t.empresa_id = md.empresa_id
         AND t.id = md.transacao_id

        WHERE t.pagar_id IS NOT NULL

          AND md.modelo_codigo IN (
              'PAGAR_CUSTO',
              'PAGAMENTO_PAGAR'
          )
    ),

    ------------------------------------------------------------------
    -- GRUPOS QUE DEVEM APARECER NO PERÍODO
    ------------------------------------------------------------------
    grupos_periodo AS (

        --------------------------------------------------------------
        -- CONTA SIMPLES
        --------------------------------------------------------------
        SELECT
            a.empresa_id,
            a.chave_divida,
            a.tipo_divida,
            a.data_apropriacao AS data_ordenacao

        FROM apropriacoes a

        WHERE a.tipo_divida = 'SIMPLES'
          AND a.data_apropriacao
              BETWEEN p_data_ini AND p_data_fim


        UNION ALL


        --------------------------------------------------------------
        -- CONTA PARCELADA
        --------------------------------------------------------------
        SELECT
            cp.empresa_id,

            ('L-' || cp.lote_id::TEXT)::TEXT AS chave_divida,

            'PARCELADA'::TEXT AS tipo_divida,

            MIN(cp.vencimento::DATE) AS data_ordenacao

        FROM public.contas_a_pagar cp

        WHERE cp.empresa_id = p_empresa_id
          AND cp.lote_id IS NOT NULL
          AND COALESCE(cp.parcelas, 1) > 1

          AND cp.vencimento::DATE
              BETWEEN p_data_ini AND p_data_fim

        GROUP BY
            cp.empresa_id,
            cp.lote_id
    ),

    ------------------------------------------------------------------
    -- PARCELAS QUE SERÃO EXIBIDAS
    ------------------------------------------------------------------
    parcelas_exibir AS (

        --------------------------------------------------------------
        -- CONTA SIMPLES
        --------------------------------------------------------------
        SELECT
            cp.empresa_id,

            ('P-' || cp.id::TEXT)::TEXT AS chave_divida,

            cp.id::BIGINT AS pagar_id,
            cp.lote_id::BIGINT AS pagar_lote_id,

            COALESCE(cp.parcela_num, 1)::BIGINT AS parcela_num,
            COALESCE(cp.parcelas, 1)::BIGINT AS parcelas,

            cp.descricao::TEXT AS descricao,
            cp.valor AS valor_parcela,
            cp.vencimento::DATE AS vencimento,
            cp.status::TEXT AS status_conta

        FROM public.contas_a_pagar cp

        JOIN grupos_periodo gp
          ON gp.empresa_id = cp.empresa_id
         AND gp.chave_divida = 'P-' || cp.id::TEXT

        WHERE gp.tipo_divida = 'SIMPLES'


        UNION ALL


        --------------------------------------------------------------
        -- CONTA PARCELADA
        --------------------------------------------------------------
        SELECT
            cp.empresa_id,

            ('L-' || cp.lote_id::TEXT)::TEXT AS chave_divida,

            cp.id::BIGINT AS pagar_id,
            cp.lote_id::BIGINT AS pagar_lote_id,

            COALESCE(cp.parcela_num, 1)::BIGINT AS parcela_num,
            COALESCE(cp.parcelas, 1)::BIGINT AS parcelas,

            cp.descricao::TEXT AS descricao,
            cp.valor AS valor_parcela,
            cp.vencimento::DATE AS vencimento,
            cp.status::TEXT AS status_conta

        FROM public.contas_a_pagar cp

        JOIN grupos_periodo gp
          ON gp.empresa_id = cp.empresa_id
         AND gp.chave_divida = 'L-' || cp.lote_id::TEXT

        WHERE gp.tipo_divida = 'PARCELADA'

          AND cp.vencimento::DATE
              BETWEEN p_data_ini AND p_data_fim
    ),

    ------------------------------------------------------------------
    -- LINHAS AUTOMÁTICAS DO RELATÓRIO
    ------------------------------------------------------------------
    linhas AS (

        --------------------------------------------------------------
        -- PRIMEIRA LINHA DO GRUPO: APROPRIAÇÃO
        --------------------------------------------------------------
        SELECT
            gp.empresa_id,
            gp.chave_divida,
            gp.tipo_divida,
            gp.data_ordenacao,

            1::INTEGER AS ordem,
            0::BIGINT AS parcela_ordenacao,

            a.pagar_id::BIGINT AS pagar_id,
            a.pagar_lote_id::BIGINT AS pagar_lote_id,

            NULL::BIGINT AS parcela_num,
            a.parcelas::BIGINT AS parcelas,

            'APROPRIACAO'::TEXT AS etapa,

            a.data_apropriacao::DATE AS data_apropriacao,
            a.data_apropriacao::DATE AS data_movimento,
            NULL::DATE AS vencimento,

            a.conta_debito::TEXT AS conta_debito,
            a.conta_credito::TEXT AS conta_credito,

            a.valor_apropriado::NUMERIC AS valor_total,

            a.descricao::TEXT AS descricao,
            NULL::TEXT AS status_conta,

            a.diario_id::BIGINT AS diario_id

        FROM grupos_periodo gp

        JOIN apropriacoes a
          ON a.empresa_id = gp.empresa_id
         AND a.chave_divida = gp.chave_divida


        UNION ALL


        --------------------------------------------------------------
        -- LINHAS DAS PARCELAS: BAIXA OU NÃO PAGO
        --------------------------------------------------------------
        SELECT
            gp.empresa_id,
            gp.chave_divida,
            gp.tipo_divida,
            gp.data_ordenacao,

            2::INTEGER AS ordem,
            pe.parcela_num::BIGINT AS parcela_ordenacao,

            pe.pagar_id::BIGINT AS pagar_id,
            pe.pagar_lote_id::BIGINT AS pagar_lote_id,

            pe.parcela_num::BIGINT AS parcela_num,
            pe.parcelas::BIGINT AS parcelas,

            CASE
                WHEN b.diario_id IS NULL
                THEN 'NAO_PAGO'
                ELSE 'BAIXA'
            END::TEXT AS etapa,

            a.data_apropriacao::DATE AS data_apropriacao,
            b.data_baixa::DATE AS data_movimento,
            pe.vencimento::DATE AS vencimento,

            b.conta_debito::TEXT AS conta_debito,
            b.conta_credito::TEXT AS conta_credito,

            CASE
                WHEN b.diario_id IS NULL
                THEN pe.valor_parcela
                ELSE b.valor_baixado
            END::NUMERIC AS valor_total,

            pe.descricao::TEXT AS descricao,
            pe.status_conta::TEXT AS status_conta,

            b.diario_id::BIGINT AS diario_id

        FROM grupos_periodo gp

        JOIN parcelas_exibir pe
          ON pe.empresa_id = gp.empresa_id
         AND pe.chave_divida = gp.chave_divida

        JOIN apropriacoes a
          ON a.empresa_id = gp.empresa_id
         AND a.chave_divida = gp.chave_divida

        LEFT JOIN baixas b
          ON b.empresa_id = pe.empresa_id
         AND b.pagar_id = pe.pagar_id
    ),

    ------------------------------------------------------------------
    -- MOVIMENTO MANUAL NA CONTA DE FORNECEDORES
    --
    -- Uma linha por diário e por conta de fornecedor movimentada.
    --
    -- Crédito em fornecedor:
    --     APROPRIACAO_MANUAL
    --
    -- Débito em fornecedor:
    --     BAIXA_MANUAL
    ------------------------------------------------------------------
     ------------------------------------------------------------------
    -- MOVIMENTOS MANUAIS NA CONTA DE FORNECEDORES
    --
    -- Os lançamentos manuais podem possuir diario_id = 0.
    -- Por isso, são encontrados diretamente em contab.lancamentos
    -- e agrupados pelo lote_id.
    ------------------------------------------------------------------
    manual_fornecedor AS (
        SELECT
            l.empresa_id,

            l.lote_id::BIGINT AS lote_manual_id,

            MIN(l.data_mov)::DATE AS data_movimento,

            MAX(
                NULLIF(TRIM(l.historico), '')
            )::TEXT AS historico,

            l.conta_id::BIGINT AS conta_fornecedor_id,

            (
                c.codigo || ' - ' || c.nome
            )::TEXT AS conta_fornecedor,

            SUM(
                COALESCE(l.debito, 0)
            )::NUMERIC AS fornecedor_debito,

            SUM(
                COALESCE(l.credito, 0)
            )::NUMERIC AS fornecedor_credito

        FROM contab.lancamentos l

        JOIN contas_fornecedores cf
          ON cf.conta_id = l.conta_id

        JOIN contab.contas c
          ON c.empresa_id = l.empresa_id
         AND c.id = l.conta_id

        WHERE l.empresa_id = p_empresa_id

          AND l.data_mov::DATE
              BETWEEN p_data_ini AND p_data_fim

          ------------------------------------------------------------
          -- Somente lançamentos contábeis manuais.
          ------------------------------------------------------------
          AND UPPER(
                TRIM(
                    COALESCE(l.origem, '')
                )
              ) = 'CONTABIL'

          ------------------------------------------------------------
          -- O lote é a ligação entre as pernas do lançamento manual.
          ------------------------------------------------------------
          AND l.lote_id IS NOT NULL

        GROUP BY
            l.empresa_id,
            l.lote_id,
            l.conta_id,
            c.codigo,
            c.nome

        HAVING
            SUM(COALESCE(l.debito, 0))
            <>
            SUM(COALESCE(l.credito, 0))
    ),

    ------------------------------------------------------------------
    -- CONTRAPARTIDAS DOS LANÇAMENTOS MANUAIS
    --
    -- Busca todas as outras contas presentes no mesmo lote.
    ------------------------------------------------------------------
    manual_com_contrapartida AS (
        SELECT
            mf.empresa_id,
            mf.lote_manual_id,
            mf.data_movimento,
            mf.historico,

            mf.conta_fornecedor_id,
            mf.conta_fornecedor,

            mf.fornecedor_debito,
            mf.fornecedor_credito,

            STRING_AGG(
                DISTINCT
                CASE
                    WHEN COALESCE(lc.debito, 0) > 0
                    THEN cc.codigo || ' - ' || cc.nome
                END,
                ' / '
            ) FILTER (
                WHERE COALESCE(lc.debito, 0) > 0
            )::TEXT AS contas_debito_contrapartida,

            STRING_AGG(
                DISTINCT
                CASE
                    WHEN COALESCE(lc.credito, 0) > 0
                    THEN cc.codigo || ' - ' || cc.nome
                END,
                ' / '
            ) FILTER (
                WHERE COALESCE(lc.credito, 0) > 0
            )::TEXT AS contas_credito_contrapartida

        FROM manual_fornecedor mf

        LEFT JOIN contab.lancamentos lc
          ON lc.empresa_id = mf.empresa_id
         AND lc.lote_id = mf.lote_manual_id
         AND lc.conta_id <> mf.conta_fornecedor_id

        LEFT JOIN contab.contas cc
          ON cc.empresa_id = lc.empresa_id
         AND cc.id = lc.conta_id

        GROUP BY
            mf.empresa_id,
            mf.lote_manual_id,
            mf.data_movimento,
            mf.historico,
            mf.conta_fornecedor_id,
            mf.conta_fornecedor,
            mf.fornecedor_debito,
            mf.fornecedor_credito
    ),

    ------------------------------------------------------------------
    -- LINHAS MANUAIS
    --
    -- Crédito em fornecedores:
    --     APROPRIACAO_MANUAL
    --
    -- Débito em fornecedores:
    --     BAIXA_MANUAL
    ------------------------------------------------------------------
    linhas_manuais AS (
        SELECT
            mc.empresa_id,

            (
                'M-' ||
                mc.lote_manual_id::TEXT ||
                '-C' ||
                mc.conta_fornecedor_id::TEXT
            )::TEXT AS chave_divida,

            'MANUAL'::TEXT AS tipo_divida,

            mc.data_movimento::DATE AS data_ordenacao,

            1::INTEGER AS ordem,
            0::BIGINT AS parcela_ordenacao,

            NULL::BIGINT AS pagar_id,
            NULL::BIGINT AS pagar_lote_id,

            NULL::BIGINT AS parcela_num,
            NULL::BIGINT AS parcelas,

            CASE
                WHEN mc.fornecedor_credito >
                     mc.fornecedor_debito
                THEN 'APROPRIACAO_MANUAL'

                WHEN mc.fornecedor_debito >
                     mc.fornecedor_credito
                THEN 'BAIXA_MANUAL'

                ELSE 'MANUAL'
            END::TEXT AS etapa,

            CASE
                WHEN mc.fornecedor_credito >
                     mc.fornecedor_debito
                THEN mc.data_movimento

                ELSE NULL::DATE
            END::DATE AS data_apropriacao,

            mc.data_movimento::DATE AS data_movimento,

            NULL::DATE AS vencimento,

            ----------------------------------------------------------
            -- Montagem da conta de débito.
            ----------------------------------------------------------
            CASE
                WHEN mc.fornecedor_debito >
                     mc.fornecedor_credito
                THEN mc.conta_fornecedor

                ELSE mc.contas_debito_contrapartida
            END::TEXT AS conta_debito,

            ----------------------------------------------------------
            -- Montagem da conta de crédito.
            ----------------------------------------------------------
            CASE
                WHEN mc.fornecedor_credito >
                     mc.fornecedor_debito
                THEN mc.conta_fornecedor

                ELSE mc.contas_credito_contrapartida
            END::TEXT AS conta_credito,

            ABS(
                mc.fornecedor_credito -
                mc.fornecedor_debito
            )::NUMERIC AS valor_total,

            COALESCE(
                NULLIF(TRIM(mc.historico), ''),
                'Lançamento contábil manual'
            )::TEXT AS descricao,

            'manual'::TEXT AS status_conta,

            ----------------------------------------------------------
            -- Não inventamos um diario_id.
            -- O identificador real do manual é o lote_manual_id.
            ----------------------------------------------------------
            NULL::BIGINT AS diario_id

        FROM manual_com_contrapartida mc
    ),

    ------------------------------------------------------------------
    -- RESULTADO COMPLETO
    --
    -- Bloco 1: contas a pagar automáticas.
    -- Bloco 2: movimentos manuais.
    ------------------------------------------------------------------
    resultado AS (

        SELECT
            1::INTEGER AS bloco_ordenacao,
            l.empresa_id,
            l.chave_divida,
            l.tipo_divida,
            l.data_ordenacao,
            l.ordem,
            l.parcela_ordenacao,
            l.pagar_id,
            l.pagar_lote_id,
            l.parcela_num,
            l.parcelas,
            l.etapa,
            l.data_apropriacao,
            l.data_movimento,
            l.vencimento,
            l.conta_debito,
            l.conta_credito,
            l.valor_total,
            l.descricao,
            l.status_conta,
            l.diario_id

        FROM linhas l


        UNION ALL


        SELECT
            2::INTEGER AS bloco_ordenacao,
            lm.empresa_id,
            lm.chave_divida,
            lm.tipo_divida,
            lm.data_ordenacao,
            lm.ordem,
            lm.parcela_ordenacao,
            lm.pagar_id,
            lm.pagar_lote_id,
            lm.parcela_num,
            lm.parcelas,
            lm.etapa,
            lm.data_apropriacao,
            lm.data_movimento,
            lm.vencimento,
            lm.conta_debito,
            lm.conta_credito,
            lm.valor_total,
            lm.descricao,
            lm.status_conta,
            lm.diario_id

        FROM linhas_manuais lm
    )

    ------------------------------------------------------------------
    -- RETORNO
    ------------------------------------------------------------------
    SELECT
        r.chave_divida,
        r.tipo_divida,

        r.pagar_id,
        r.pagar_lote_id,

        r.parcela_num,
        r.parcelas,

        r.etapa,
        r.data_apropriacao,
        r.data_movimento,
        r.vencimento,

        r.conta_debito,
        r.conta_credito,

        r.valor_total,
        r.descricao,
        r.status_conta,

        r.diario_id

    FROM resultado r

    ORDER BY
        r.bloco_ordenacao,
        r.data_ordenacao,
        r.chave_divida,
        r.ordem,
        r.parcela_ordenacao,
        r.data_movimento NULLS LAST,
        r.diario_id NULLS LAST;

END;
$$;