 DROP FUNCTION IF EXISTS contab.fn_cartoes_compras_reclassificacao(
    BIGINT,
    BIGINT,
    DATE,
    DATE
);

CREATE OR REPLACE FUNCTION contab.fn_cartoes_compras_reclassificacao(
    p_empresa_id  BIGINT,
    p_cartao_id   BIGINT,
    p_data_inicio DATE,
    p_data_fim    DATE
)
RETURNS TABLE
(
    conciliacao_id       BIGINT,
    cartao_id            BIGINT,
    importacao_id        BIGINT,
    transacao_cartao_id  BIGINT,
    lote_id              BIGINT,
    data_compra          DATE,
    estabelecimento      TEXT,
    portador             TEXT,
    valor                NUMERIC,
    parcela_texto        TEXT,
    contabil_id          BIGINT,
    conta_codigo         TEXT,
    conta_nome           TEXT,
    conta_credito_codigo TEXT,
    status_conciliacao   TEXT
)
LANGUAGE plpgsql
AS
$$
BEGIN
    IF p_data_inicio IS NULL OR p_data_fim IS NULL THEN
        RAISE EXCEPTION
            'Informe a data inicial e a data final';
    END IF;

    IF p_data_inicio > p_data_fim THEN
        RAISE EXCEPTION
            'Período inválido: data inicial % maior que a data final %',
            p_data_inicio,
            p_data_fim;
    END IF;

    RETURN QUERY
    SELECT
        cc.id AS conciliacao_id,
        cc.cartao_id,
        cc.importacao_id,
        cc.transacao_cartao_id,

        MAX(l.lote_id) AS lote_id,

        MIN(l.data_mov) AS data_compra,
        cc.estabelecimento,
        cc.portador,
       COALESCE(
    MAX(ABS(l.debito)) FILTER (WHERE l.debito > 0),
    MAX(ABS(l.credito)) FILTER (WHERE l.credito > 0),
    0
) AS valor,
        cc.parcela_texto,

        MAX(l.conta_id) FILTER (
            WHERE l.debito > 0
        ) AS contabil_id,

        MAX(c.codigo::TEXT) FILTER (
            WHERE l.debito > 0
        ) AS conta_codigo,

        MAX(c.nome::TEXT) FILTER (
            WHERE l.debito > 0
        ) AS conta_nome,

        MAX(c.codigo::TEXT) FILTER (
            WHERE l.credito > 0
        ) AS conta_credito_codigo,

        cc.status_conciliacao::TEXT

    FROM contab.diario d

    INNER JOIN contab.lancamentos l
            ON l.diario_id = d.id

    INNER JOIN public.conciliacao_cartoes cc
            ON d.outros->>'compra_id' = cc.compra_match_id::TEXT

    INNER JOIN contab.contas c
            ON c.id = l.conta_id

    WHERE d.empresa_id = p_empresa_id
      AND l.empresa_id = p_empresa_id
      AND cc.empresa_id = p_empresa_id
      AND c.empresa_id = p_empresa_id

      AND d.modelo_codigo = 'CRIA_CARTAO_COMPRA'

      AND cc.cartao_id = p_cartao_id
     AND d.data_mov BETWEEN p_data_inicio AND p_data_fim
    --  AND LOWER(TRIM(cc.tipo_linha)) = 'compra'
      AND LOWER(TRIM(cc.status_conciliacao)) = 'conciliado'
      AND cc.transacao_cartao_id IS NOT NULL
      AND cc.compra_match_id IS NOT NULL

    GROUP BY
        cc.id,
        cc.cartao_id,
        cc.importacao_id,
        cc.transacao_cartao_id,
        
        cc.estabelecimento,
        cc.portador,
        cc.valor,
        cc.parcela_texto,
        cc.status_conciliacao

    ORDER BY
         MIN(l.data_mov),
        cc.estabelecimento,
        cc.id;
END;
$$;