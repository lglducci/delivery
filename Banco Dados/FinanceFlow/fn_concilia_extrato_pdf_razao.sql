 DROP FUNCTION IF EXISTS contab.fn_concilia_extrato_pdf_razao(
    BIGINT,
    BIGINT,
    JSONB
);

 
CREATE OR REPLACE FUNCTION contab.fn_concilia_extrato_pdf_razao(
    p_empresa_id  BIGINT,
    p_conta_id    BIGINT,
    p_data_inicio DATE,
    p_data_fim    DATE
)


RETURNS JSONB
LANGUAGE plpgsql
AS
$$
DECLARE
    v_qtd_extrato          INTEGER := 0;
    v_qtd_razao            INTEGER := 0;
    v_qtd_dias             INTEGER := 0;
    v_qtd_mov_conciliado   INTEGER := 0;
    v_contabil_id          BIGINT;

    v_extrato              RECORD;
    v_razao                RECORD;

    v_id_razao             BIGINT;
    v_id_extrato           BIGINT;

    v_data_razao           DATE;
    v_data_extrato         DATE;

    v_valor_razao          NUMERIC;
    v_valor_extrato        NUMERIC;

    v_ids_razao            BIGINT[];
    v_ids_extrato          BIGINT[];
     v_data_ini   DATE;
    v_data_fim   DATE;

BEGIN


 

    ------------------------------------------------------------------
    -- LOCALIZA A CONTA CONTÁBIL VINCULADA À CONTA FINANCEIRA
    ------------------------------------------------------------------

    SELECT contabil_id
      INTO v_contabil_id
    FROM contas_financeiras
    WHERE empresa_id = p_empresa_id
      AND id         = p_conta_id;

    IF v_contabil_id IS NULL THEN
        RAISE EXCEPTION
            'Conta financeira % não possui conta contábil vinculada',
            p_conta_id;
    END IF;

   IF p_data_inicio IS NULL OR p_data_fim IS NULL THEN
    RAISE EXCEPTION 'Informe a data inicial e a data final';
END IF;

IF p_data_inicio > p_data_fim THEN
    RAISE EXCEPTION
        'Período inválido: data inicial % maior que a data final %',
        p_data_inicio,
        p_data_fim;
END IF;

v_data_ini := p_data_inicio;
v_data_fim := p_data_fim;

------------------------------------------------------------------
-- LIMPA SOMENTE A CONCILIAÇÃO ATUAL
------------------------------------------------------------------

DELETE FROM contab.conciliacao_tmp
WHERE empresa_id = p_empresa_id
  AND conta_id = p_conta_id;

------------------------------------------------------------------
-- CARREGA O EXTRATO SEM DUPLICAR MOVIMENTOS ENTRE LOTES
--
-- A mesma movimentacao pode existir em dois lotes quando um extrato
-- com periodo maior e importado depois. Mantemos apenas uma ocorrencia
-- equivalente entre os lotes, priorizando o lote mais antigo.
--
-- A numeracao ocorrencia_no_lote preserva movimentos legitimamente
-- repetidos dentro do mesmo extrato (mesma data, valor e historico).
------------------------------------------------------------------

WITH filtrado AS
(
    SELECT
        cf.*,

        CASE
            WHEN UPPER(TRIM(COALESCE(cf.tipo, ''))) IN
                 ('C', 'CREDITO', 'CRÉDITO', 'ENTRADA')
                THEN 'C'

            WHEN UPPER(TRIM(COALESCE(cf.tipo, ''))) IN
                 ('D', 'DEBITO', 'DÉBITO', 'SAIDA', 'SAÍDA')
                THEN 'D'

            WHEN cf.valor >= 0
                THEN 'C'

            ELSE 'D'
        END AS tipo_conciliacao,

        REGEXP_REPLACE(
            UPPER(TRIM(COALESCE(cf.historico, ''))),
            '[[:space:]]+',
            ' ',
            'g'
        ) AS historico_chave

    FROM public.conciliacao_financeira cf
    WHERE cf.empresa_id = p_empresa_id
      AND cf.conta_financeira_id = p_conta_id
      AND cf.data_mov BETWEEN p_data_inicio AND p_data_fim
      AND cf.importar IS TRUE
      AND LOWER(TRIM(COALESCE(cf.status_conciliacao, ''))) = 'executado'
),

por_lote AS
(
    SELECT
        f.*,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                f.lote_conciliacao_id,
                f.data_mov,
                ROUND(f.valor::NUMERIC, 2),
                f.tipo_conciliacao,
                f.historico_chave
            ORDER BY f.id
        ) AS ocorrencia_no_lote

    FROM filtrado f
),

sem_duplicidade AS
(
    SELECT
        p.*,

        ROW_NUMBER() OVER
        (
            PARTITION BY
                p.data_mov,
                ROUND(p.valor::NUMERIC, 2),
                p.tipo_conciliacao,
                p.historico_chave,
                p.ocorrencia_no_lote
            ORDER BY
                p.lote_conciliacao_id ASC NULLS LAST,
                p.id ASC
        ) AS manter

    FROM por_lote p
)

INSERT INTO contab.conciliacao_tmp
(
    empresa_id,
    conta_id,
    origem,
    origem_id,
    lote_id,
    data_mov,
    valor,
    tipo,
    historico,
    achei,
    par_id,
    motivo,
    acao,
    data_sugerida,
    valor_sugerido
)
SELECT
    cf.empresa_id,
    cf.conta_financeira_id,
    'P',
    cf.id,
    cf.lote_conciliacao_id,
    cf.data_mov,
    ABS(cf.valor),
    cf.tipo_conciliacao,

    COALESCE(
        NULLIF(TRIM(cf.historico_lancamento), ''),
        cf.historico
    ),

    FALSE,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL

FROM sem_duplicidade cf
WHERE cf.manter = 1
ORDER BY cf.data_mov, cf.id;

GET DIAGNOSTICS v_qtd_extrato = ROW_COUNT;

IF v_qtd_extrato = 0 THEN
    RAISE EXCEPTION
        'Nenhum movimento executado encontrado na conciliação financeira entre % e %',
        p_data_inicio,
        p_data_fim;
END IF;

 
------------------------------------------------------------------
-- IMPORTA RAZÃO
------------------------------------------------------------------


    INSERT INTO contab.conciliacao_tmp
    (
        empresa_id,
        conta_id,
        origem,
        origem_id,
        lote_id,
        data_mov,
        valor,
        tipo,
        historico,
        achei,
        par_id,
        motivo,
        acao,
        data_sugerida,
        valor_sugerido
    )
    SELECT
        l.empresa_id,
        p_conta_id,
        'R',
        l.id,
        l.lote_id,
        l.data_mov,
        ABS(l.debito - l.credito),

        CASE
            WHEN l.debito > 0 THEN 'C'
            ELSE 'D'
        END,

        l.historico,
        FALSE,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL

    FROM contab.lancamentos l
    WHERE l.empresa_id = p_empresa_id
      AND l.conta_id   = v_contabil_id
      AND l.data_mov BETWEEN v_data_ini AND v_data_fim;

    GET DIAGNOSTICS v_qtd_razao = ROW_COUNT;

    ------------------------------------------------------------------
    -- LIMPA POSSÍVEIS MARCAÇÕES RESIDUAIS DOS REGISTROS ATUAIS
    ------------------------------------------------------------------

    UPDATE contab.conciliacao_tmp
    SET
        achei          = FALSE,
        par_id         = NULL,
        motivo         = NULL,
        acao           = NULL,
        data_sugerida  = NULL,
        valor_sugerido = NULL
    WHERE empresa_id = p_empresa_id
      AND conta_id   = p_conta_id;

    ------------------------------------------------------------------
    -- IGNORA LINHAS DE SALDO DO EXTRATO
    ------------------------------------------------------------------

    UPDATE contab.conciliacao_tmp
    SET
        achei  = TRUE,
        motivo = 'IGNORAR_SALDO',
        acao   = NULL
    WHERE empresa_id = p_empresa_id
      AND conta_id   = p_conta_id
      AND origem     = 'P'
      AND (
            UPPER(TRIM(COALESCE(historico, '')))
                LIKE 'SALDO DO DIA%'

         OR UPPER(TRIM(COALESCE(historico, '')))
                LIKE 'SALDO ANTERIOR%'

         OR UPPER(TRIM(COALESCE(historico, '')))
                LIKE 'SALDO INICIAL%'

         OR UPPER(TRIM(COALESCE(historico, '')))
                LIKE 'SALDO FINAL%'
      );
 

 ------------------------------------------------------------------
-- CAMADA 1
------------------------------------------------------------------


---- IA ATÉ AUI  O SELECT SERA SOBRE A CONCILIACA_FINANCIEOR E NÃO MAIS NESTA TABELA TEMP 
    FOR v_extrato IN

        SELECT
            id,
            data_mov,
            tipo,
            valor
        FROM contab.conciliacao_tmp
        WHERE empresa_id = p_empresa_id
          AND conta_id   = p_conta_id
          AND origem     = 'P'
          AND achei      = FALSE
        ORDER BY
            data_mov,
            tipo,
            valor,
            id

    LOOP

        v_id_razao := NULL;

        SELECT r.id
          INTO v_id_razao
        FROM contab.conciliacao_tmp r
        WHERE r.empresa_id = p_empresa_id
          AND r.conta_id   = p_conta_id
          AND r.origem     = 'R'
          AND r.achei      = FALSE
          AND r.data_mov   = v_extrato.data_mov
          AND r.tipo       = v_extrato.tipo
          AND ROUND(r.valor, 2) = ROUND(v_extrato.valor, 2)
        ORDER BY r.id
        LIMIT 1;

        IF v_id_razao IS NOT NULL THEN

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_id_razao,
                motivo = 'EXATO',
                acao   = NULL
            WHERE id = v_extrato.id;

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_extrato.id,
                motivo = 'EXATO',
                acao   = NULL
            WHERE id = v_id_razao
              AND achei = FALSE;

        END IF;

    END LOOP;

     
    -- CAMADA 2
    -- MESMO TIPO + MESMO VALOR EM OUTRA DATA
    --
    -- ESCOLHE PRIMEIRO A DATA MAIS PRÓXIMA.
    -- COMO O REGISTRO É MARCADO IMEDIATAMENTE, NÃO É REUTILIZADO.
    

    FOR v_extrato IN

        SELECT
            id,
            data_mov,
            tipo,
            valor
        FROM contab.conciliacao_tmp
        WHERE empresa_id = p_empresa_id
          AND conta_id   = p_conta_id
          AND origem     = 'P'
          AND achei      = FALSE
        ORDER BY
            data_mov,
            tipo,
            valor,
            id

    LOOP

        v_id_razao   := NULL;
        v_data_razao := NULL;

        SELECT
            r.id,
            r.data_mov
        INTO
            v_id_razao,
            v_data_razao
        FROM contab.conciliacao_tmp r
        WHERE r.empresa_id = p_empresa_id
          AND r.conta_id   = p_conta_id
          AND r.origem     = 'R'
          AND r.achei      = FALSE
          AND r.tipo       = v_extrato.tipo
          AND ROUND(r.valor, 2) = ROUND(v_extrato.valor, 2)
        ORDER BY
            ABS(r.data_mov - v_extrato.data_mov),
            r.data_mov,
            r.id
        LIMIT 1;

        IF v_id_razao IS NOT NULL THEN

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_id_razao,
                motivo = 'DATA_DIFERENTE',
                acao   = NULL
            WHERE id = v_extrato.id;

            UPDATE contab.conciliacao_tmp
            SET
                achei         = TRUE,
                par_id        = v_extrato.id,
                motivo        = 'DATA_DIFERENTE',
                acao          = 'ALTERAR_DATA',
                data_sugerida = v_extrato.data_mov
            WHERE id = v_id_razao
              AND achei = FALSE;

        END IF;

    END LOOP;
 
    -- CAMADA 3
    -- DIFERENÇA DE CENTAVOS
    -- MESMA DATA + MESMO TIPO + DIFERENÇA ATÉ R$ 0,05
 

    FOR v_extrato IN

        SELECT
            id,
            data_mov,
            tipo,
            valor
        FROM contab.conciliacao_tmp
        WHERE empresa_id = p_empresa_id
          AND conta_id   = p_conta_id
          AND origem     = 'P'
          AND achei      = FALSE
        ORDER BY
            data_mov,
            tipo,
            valor,
            id

    LOOP

        v_id_razao    := NULL;
        v_valor_razao := NULL;

        SELECT
            r.id,
            r.valor
        INTO
            v_id_razao,
            v_valor_razao
        FROM contab.conciliacao_tmp r
        WHERE r.empresa_id = p_empresa_id
          AND r.conta_id   = p_conta_id
          AND r.origem     = 'R'
          AND r.achei      = FALSE
          AND r.data_mov   = v_extrato.data_mov
          AND r.tipo       = v_extrato.tipo
          AND ROUND(r.valor, 2) <> ROUND(v_extrato.valor, 2)
          AND ABS(r.valor - v_extrato.valor) <= 0.05
        ORDER BY
            ABS(r.valor - v_extrato.valor),
            r.id
        LIMIT 1;

        IF v_id_razao IS NOT NULL THEN

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_id_razao,
                motivo = 'DIFERENCA_CENTAVOS',
                acao   = NULL
            WHERE id = v_extrato.id;

            UPDATE contab.conciliacao_tmp
            SET
                achei          = TRUE,
                par_id         = v_extrato.id,
                motivo         = 'DIFERENCA_CENTAVOS',
                acao           = 'ALTERAR_VALOR',
                valor_sugerido = v_extrato.valor
            WHERE id = v_id_razao
              AND achei = FALSE;

        END IF;

    END LOOP;
 
    -- CAMADA 4
    -- 2 OU 3 MOVIMENTOS DO RAZÃO PARA 1 MOVIMENTO DO EXTRATO
    --
    -- EXEMPLO:
    -- RAZÃO   800 + 800 + 800
    -- EXTRATO 2400
 

    FOR v_extrato IN

        SELECT
            id,
            data_mov,
            tipo,
            valor
        FROM contab.conciliacao_tmp
        WHERE empresa_id = p_empresa_id
          AND conta_id   = p_conta_id
          AND origem     = 'P'
          AND achei      = FALSE
        ORDER BY
            data_mov,
            tipo,
            valor,
            id

    LOOP

        v_ids_razao := NULL;

        --------------------------------------------------------------
        -- PROCURA PRIMEIRO UMA COMBINAÇÃO DE 2 MOVIMENTOS
        --------------------------------------------------------------

        SELECT ARRAY[r1.id, r2.id]
          INTO v_ids_razao
        FROM contab.conciliacao_tmp r1
        INNER JOIN contab.conciliacao_tmp r2
                ON r2.empresa_id = r1.empresa_id
               AND r2.conta_id   = r1.conta_id
               AND r2.origem     = 'R'
               AND r2.achei      = FALSE
               AND r2.tipo       = r1.tipo
               AND r2.id         > r1.id
        WHERE r1.empresa_id = p_empresa_id
          AND r1.conta_id   = p_conta_id
          AND r1.origem     = 'R'
          AND r1.achei      = FALSE
          AND r1.tipo       = v_extrato.tipo
          AND ROUND(r1.valor + r2.valor, 2)
              = ROUND(v_extrato.valor, 2)
        ORDER BY
            GREATEST(
                ABS(r1.data_mov - v_extrato.data_mov),
                ABS(r2.data_mov - v_extrato.data_mov)
            ),
            r1.id,
            r2.id
        LIMIT 1;

        --------------------------------------------------------------
        -- SE NÃO ACHOU 2, PROCURA 3 MOVIMENTOS
        --------------------------------------------------------------

        IF v_ids_razao IS NULL THEN

            SELECT ARRAY[r1.id, r2.id, r3.id]
              INTO v_ids_razao
            FROM contab.conciliacao_tmp r1

            INNER JOIN contab.conciliacao_tmp r2
                    ON r2.empresa_id = r1.empresa_id
                   AND r2.conta_id   = r1.conta_id
                   AND r2.origem     = 'R'
                   AND r2.achei      = FALSE
                   AND r2.tipo       = r1.tipo
                   AND r2.id         > r1.id

            INNER JOIN contab.conciliacao_tmp r3
                    ON r3.empresa_id = r1.empresa_id
                   AND r3.conta_id   = r1.conta_id
                   AND r3.origem     = 'R'
                   AND r3.achei      = FALSE
                   AND r3.tipo       = r1.tipo
                   AND r3.id         > r2.id

            WHERE r1.empresa_id = p_empresa_id
              AND r1.conta_id   = p_conta_id
              AND r1.origem     = 'R'
              AND r1.achei      = FALSE
              AND r1.tipo       = v_extrato.tipo
              AND ROUND(r1.valor + r2.valor + r3.valor, 2)
                  = ROUND(v_extrato.valor, 2)

            ORDER BY
                GREATEST(
                    ABS(r1.data_mov - v_extrato.data_mov),
                    ABS(r2.data_mov - v_extrato.data_mov),
                    ABS(r3.data_mov - v_extrato.data_mov)
                ),
                r1.id,
                r2.id,
                r3.id

            LIMIT 1;

        END IF;

        --------------------------------------------------------------
        -- MARCA O GRUPO ENCONTRADO
        --------------------------------------------------------------

        IF v_ids_razao IS NOT NULL THEN

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_ids_razao[1],

                motivo =
                    CASE
                        WHEN array_length(v_ids_razao, 1) = 2
                            THEN 'AGRUPADO_2R_1P'
                        ELSE 'AGRUPADO_3R_1P'
                    END,

                acao = NULL
            WHERE id = v_extrato.id;

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_extrato.id,

                motivo =
                    CASE
                        WHEN array_length(v_ids_razao, 1) = 2
                            THEN 'AGRUPADO_2R_1P'
                        ELSE 'AGRUPADO_3R_1P'
                    END,

                acao = NULL
            WHERE id = ANY(v_ids_razao)
              AND achei = FALSE;

        END IF;

    END LOOP;

 
    -- CAMADA 5
    -- 2 OU 3 MOVIMENTOS DO EXTRATO PARA 1 MOVIMENTO DO RAZÃO
    --
    -- EXEMPLO:
    -- EXTRATO 700 + 3000
    -- RAZÃO   3700
 

    FOR v_razao IN

        SELECT
            id,
            data_mov,
            tipo,
            valor
        FROM contab.conciliacao_tmp
        WHERE empresa_id = p_empresa_id
          AND conta_id   = p_conta_id
          AND origem     = 'R'
          AND achei      = FALSE
        ORDER BY
            data_mov,
            tipo,
            valor,
            id

    LOOP

        v_ids_extrato := NULL;

        --------------------------------------------------------------
        -- PROCURA 2 MOVIMENTOS DO EXTRATO
        --------------------------------------------------------------

        SELECT ARRAY[p1.id, p2.id]
          INTO v_ids_extrato
        FROM contab.conciliacao_tmp p1

        INNER JOIN contab.conciliacao_tmp p2
                ON p2.empresa_id = p1.empresa_id
               AND p2.conta_id   = p1.conta_id
               AND p2.origem     = 'P'
               AND p2.achei      = FALSE
               AND p2.tipo       = p1.tipo
               AND p2.id         > p1.id

        WHERE p1.empresa_id = p_empresa_id
          AND p1.conta_id   = p_conta_id
          AND p1.origem     = 'P'
          AND p1.achei      = FALSE
          AND p1.tipo       = v_razao.tipo
          AND ROUND(p1.valor + p2.valor, 2)
              = ROUND(v_razao.valor, 2)

        ORDER BY
            GREATEST(
                ABS(p1.data_mov - v_razao.data_mov),
                ABS(p2.data_mov - v_razao.data_mov)
            ),
            p1.id,
            p2.id

        LIMIT 1;

        --------------------------------------------------------------
        -- SE NÃO ACHOU 2, PROCURA 3 MOVIMENTOS
        --------------------------------------------------------------

        IF v_ids_extrato IS NULL THEN

            SELECT ARRAY[p1.id, p2.id, p3.id]
              INTO v_ids_extrato
            FROM contab.conciliacao_tmp p1

            INNER JOIN contab.conciliacao_tmp p2
                    ON p2.empresa_id = p1.empresa_id
                   AND p2.conta_id   = p1.conta_id
                   AND p2.origem     = 'P'
                   AND p2.achei      = FALSE
                   AND p2.tipo       = p1.tipo
                   AND p2.id         > p1.id

            INNER JOIN contab.conciliacao_tmp p3
                    ON p3.empresa_id = p1.empresa_id
                   AND p3.conta_id   = p1.conta_id
                   AND p3.origem     = 'P'
                   AND p3.achei      = FALSE
                   AND p3.tipo       = p1.tipo
                   AND p3.id         > p2.id

            WHERE p1.empresa_id = p_empresa_id
              AND p1.conta_id   = p_conta_id
              AND p1.origem     = 'P'
              AND p1.achei      = FALSE
              AND p1.tipo       = v_razao.tipo
              AND ROUND(p1.valor + p2.valor + p3.valor, 2)
                  = ROUND(v_razao.valor, 2)

            ORDER BY
                GREATEST(
                    ABS(p1.data_mov - v_razao.data_mov),
                    ABS(p2.data_mov - v_razao.data_mov),
                    ABS(p3.data_mov - v_razao.data_mov)
                ),
                p1.id,
                p2.id,
                p3.id

            LIMIT 1;

        END IF;

        --------------------------------------------------------------
        -- MARCA O GRUPO
        --------------------------------------------------------------

        IF v_ids_extrato IS NOT NULL THEN

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_ids_extrato[1],

                motivo =
                    CASE
                        WHEN array_length(v_ids_extrato, 1) = 2
                            THEN 'AGRUPADO_2P_1R'
                        ELSE 'AGRUPADO_3P_1R'
                    END,

                acao = NULL
            WHERE id = v_razao.id;

            UPDATE contab.conciliacao_tmp
            SET
                achei  = TRUE,
                par_id = v_razao.id,

                motivo =
                    CASE
                        WHEN array_length(v_ids_extrato, 1) = 2
                            THEN 'AGRUPADO_2P_1R'
                        ELSE 'AGRUPADO_3P_1R'
                    END,

                acao = NULL
            WHERE id = ANY(v_ids_extrato)
              AND achei = FALSE;

        END IF;

    END LOOP;

  
    -- CAMADA FINAL
    -- EXTRATO SEM CORRESPONDÊNCIA NO RAZÃO
 

    UPDATE contab.conciliacao_tmp
    SET
        motivo         = 'NAO_EXISTE_NO_RAZAO',
        acao           = 'CRIAR_LANCAMENTO',
        data_sugerida  = data_mov,
        valor_sugerido = valor
    WHERE empresa_id = p_empresa_id
      AND conta_id   = p_conta_id
      AND origem     = 'P'
      AND achei      = FALSE;

    
    -- CAMADA FINAL
    -- RAZÃO SEM CORRESPONDÊNCIA NO EXTRATO
 

    UPDATE contab.conciliacao_tmp
    SET
        motivo         = 'NAO_EXISTE_NO_EXTRATO',
        acao           = 'EXCLUIR_LOTE',
        data_sugerida  = NULL,
        valor_sugerido = NULL
    WHERE empresa_id = p_empresa_id
      AND conta_id   = p_conta_id
      AND origem     = 'R'
      AND achei      = FALSE;

    ------------------------------------------------------------------
    -- TOTAL DE MOVIMENTOS CONCILIADOS
    -- CONTA APENAS O LADO DO EXTRATO PARA NÃO DUPLICAR
    ------------------------------------------------------------------

    SELECT COUNT(*)
      INTO v_qtd_mov_conciliado
    FROM contab.conciliacao_tmp
    WHERE empresa_id = p_empresa_id
      AND conta_id   = p_conta_id
      AND origem     = 'P'
      AND achei      = TRUE
      AND motivo    <> 'IGNORAR_SALDO';

    ------------------------------------------------------------------
    -- DIAS COMPLETAMENTE CONCILIADOS
    --
    -- AGORA É APENAS INFORMAÇÃO.
    -- NÃO É USADO PARA MARCAR MOVIMENTOS.
    ------------------------------------------------------------------

    SELECT COUNT(*)
      INTO v_qtd_dias
    FROM
    (
        SELECT t.data_mov
        FROM contab.conciliacao_tmp t
        WHERE t.empresa_id = p_empresa_id
          AND t.conta_id   = p_conta_id
          AND t.motivo    <> 'IGNORAR_SALDO'
        GROUP BY t.data_mov
        HAVING COUNT(*) FILTER (WHERE t.achei = FALSE) = 0
    ) dias;

    ------------------------------------------------------------------
    -- RETORNO
    ------------------------------------------------------------------

    RETURN jsonb_build_object(
        'ok', TRUE,

        'razao_importado',
        v_qtd_razao,

        'extrato_importado',
        v_qtd_extrato,

        'dias_conciliados',
        v_qtd_dias,

        'movimentos_conciliados',
        v_qtd_mov_conciliado,
        'data_inicio',
        v_data_ini, 
        'data_fim',
        v_data_fim, 
        'movimentos_pendentes',
        (
            SELECT COUNT(*)
            FROM contab.conciliacao_tmp
            WHERE empresa_id = p_empresa_id
              AND conta_id   = p_conta_id
              AND achei      = FALSE
        ),

        'acoes',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'conciliacao_id', t.id,
                        'origem', t.origem,

                        'lancamento_id',
                        CASE
                            WHEN t.origem = 'R'
                                THEN t.origem_id
                            ELSE NULL
                        END,

                        'origem_id', t.origem_id,
                        'lote_id', t.lote_id,
                        'data_mov', t.data_mov,
                        'tipo', t.tipo,
                        'valor', t.valor,
                        'historico', t.historico,
                        'motivo', t.motivo,
                        'acao', t.acao,
                        'data_sugerida', t.data_sugerida,
                        'valor_sugerido', t.valor_sugerido
                    )
                    ORDER BY
                        CASE
                            WHEN t.acao = 'EXCLUIR_LOTE' THEN 1
                            WHEN t.acao = 'CRIAR_LANCAMENTO' THEN 2
                            WHEN t.acao = 'ALTERAR_VALOR' THEN 3
                            WHEN t.acao = 'ALTERAR_DATA' THEN 4
                            ELSE 5
                        END,
                        t.data_mov,
                        t.valor,
                        t.id
                )
                FROM contab.conciliacao_tmp t
                WHERE t.empresa_id = p_empresa_id
                  AND t.conta_id   = p_conta_id
                  AND t.achei      = FALSE
                  AND t.acao       IS NOT NULL
            ),
            '[]'::jsonb
        )
    );

END;
$$;
