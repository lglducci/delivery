 CREATE OR REPLACE FUNCTION contab.ff_gerar_contabil_final(
    p_empresa_id BIGINT,
    p_data_ini   DATE,
    p_data_fim   DATE
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
BEGIN
    ----------------------------------------------------------------
    -- 1) LIMPA LANÇAMENTOS DO PERÍODO
    ----------------------------------------------------------------
    DELETE FROM contab.lancamentos
WHERE empresa_id = p_empresa_id
  AND data_mov BETWEEN p_data_ini AND p_data_fim
  AND COALESCE(origem, '') <> 'CONTABIL';
    ----------------------------------------------------------------
    -- 2) PROCESSA DIÁRIO NORMAL / NÃO IMPORTAÇÃO
    ----------------------------------------------------------------
   FOR r IN
        SELECT d.id, d.empresa_id, d.modelo_codigo
        FROM contab.diario d
        LEFT JOIN public.transacoes t
          ON t.id = d.transacao_id
         AND t.empresa_id = d.empresa_id
        WHERE d.empresa_id = p_empresa_id
          AND d.data_mov BETWEEN p_data_ini AND p_data_fim
          AND t.importacao_id IS NULL
        ORDER BY d.id
    LOOP
        PERFORM contab.dispatch_gerar_lancamentos(
            r.id,
            r.empresa_id,
            r.modelo_codigo
        );
    END LOOP; 

    ----------------------------------------------------------------
    -- 3) PROCESSA DIÁRIO DE IMPORTAÇÃO
    ----------------------------------------------------------------
    FOR r IN
        SELECT d.id, d.empresa_id, d.modelo_codigo
        FROM contab.diario d
        JOIN public.transacoes t
          ON t.id = d.transacao_id 
         AND t.empresa_id = d.empresa_id
        WHERE d.empresa_id = p_empresa_id
          AND d.data_mov BETWEEN p_data_ini AND p_data_fim 
        ORDER BY d.id
    LOOP
        PERFORM contab.gerar_lancamentos_importacao(
            r.id,
            r.empresa_id
        );
    END LOOP;

    ----------------------------------------------------------------
    -- 4) LIMPA STAGING
    ----------------------------------------------------------------
    DELETE FROM contab.diario_staging
    WHERE empresa_id = p_empresa_id
      AND data_mov BETWEEN p_data_ini AND p_data_fim;

    ----------------------------------------------------------------
    -- 5) ATUALIZA DIÁRIO
    ----------------------------------------------------------------
    UPDATE contab.diario
    SET status = 'processado'
    WHERE empresa_id = p_empresa_id
      AND data_mov BETWEEN p_data_ini AND p_data_fim
      AND status = 'rascunho';

    ----------------------------------------------------------------
    -- 6) CONTROLE DE FECHAMENTO
    ----------------------------------------------------------------
    UPDATE contab.controle_fechamento
    SET ultimo_dia_processado = p_data_fim  
    WHERE empresa_id = p_empresa_id;
END;
$$;