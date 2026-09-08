DROP FUNCTION IF EXISTS contab.ff_gerar_contabil_final_conta(
    BIGINT,
    BIGINT,
    DATE,
    DATE
);

CREATE OR REPLACE FUNCTION contab.ff_gerar_contabil_final_conta(
    p_empresa_id          BIGINT,
    p_conta_financeira_id BIGINT,
    p_data_ini            DATE,
    p_data_fim            DATE
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    ---------------------------------------------------------------
    -- 1) EXCLUI SOMENTE OS LANÇAMENTOS DA CONTA INFORMADA
    ---------------------------------------------------------------
    DELETE FROM contab.lancamentos l
    USING contab.diario d
    JOIN public.transacoes t
      ON t.id = d.transacao_id
     AND t.empresa_id = d.empresa_id
    WHERE l.diario_id = d.id
      AND l.empresa_id = p_empresa_id
      AND d.empresa_id = p_empresa_id
      AND d.data_mov BETWEEN p_data_ini AND p_data_fim
      AND t.conta_id = p_conta_financeira_id
      AND COALESCE(l.origem, '') <> 'CONTABIL';

    ---------------------------------------------------------------
    -- 2) PROCESSA TRANSAÇÕES NORMAIS DA CONTA
    ---------------------------------------------------------------
    FOR r IN
        SELECT
            d.id,
            d.empresa_id,
            d.modelo_codigo
        FROM contab.diario d
        JOIN public.transacoes t
          ON t.id = d.transacao_id
         AND t.empresa_id = d.empresa_id
        WHERE d.empresa_id = p_empresa_id
          AND d.data_mov BETWEEN p_data_ini AND p_data_fim
          AND t.conta_id = p_conta_financeira_id
          AND t.importacao_id IS NULL
        ORDER BY d.id
    LOOP
        PERFORM contab.dispatch_gerar_lancamentos(
            r.id,
            r.empresa_id,
            r.modelo_codigo
        );
    END LOOP;

    ---------------------------------------------------------------
    -- 3) PROCESSA TRANSAÇÕES DE IMPORTAÇÃO DA CONTA
    ---------------------------------------------------------------
    FOR r IN
        SELECT
            d.id,
            d.empresa_id
        FROM contab.diario d
        JOIN public.transacoes t
          ON t.id = d.transacao_id
         AND t.empresa_id = d.empresa_id
        WHERE d.empresa_id = p_empresa_id
          AND d.data_mov BETWEEN p_data_ini AND p_data_fim
          AND t.conta_id = p_conta_financeira_id
          AND t.importacao_id IS NOT NULL
        ORDER BY d.id
    LOOP
        PERFORM contab.gerar_lancamentos_importacao(
            r.id,
            r.empresa_id
        );
    END LOOP;

    ---------------------------------------------------------------
    -- 4) ATUALIZA SOMENTE OS DIÁRIOS DA CONTA
    ---------------------------------------------------------------
    UPDATE contab.diario d
    SET status = 'processado'
    FROM public.transacoes t
    WHERE t.id = d.transacao_id
      AND t.empresa_id = d.empresa_id
      AND d.empresa_id = p_empresa_id
      AND d.data_mov BETWEEN p_data_ini AND p_data_fim
      AND t.conta_id = p_conta_financeira_id
      AND d.status = 'rascunho';
END;
$$;