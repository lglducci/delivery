 CREATE OR REPLACE FUNCTION contab.ff_excluir_lancamentos_lote(
    p_empresa_id    BIGINT,
    p_lote_id       BIGINT DEFAULT 0,
    p_importacao_id BIGINT DEFAULT 0
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_qtd INT; 
    
    v_diario_ids BIGINT[];
    v_transacao_ids BIGINT[];
BEGIN
    IF COALESCE(p_lote_id, 0) = 0 AND COALESCE(p_importacao_id, 0) = 0 THEN
        RAISE EXCEPTION 'Informe p_lote_id ou p_importacao_id';
    END IF;

    IF COALESCE(p_lote_id, 0) > 0 AND COALESCE(p_importacao_id, 0) > 0 THEN
        RAISE EXCEPTION 'Informe apenas um dos parâmetros: p_lote_id ou p_importacao_id';
    END IF;

    -- exclui um lote
    IF COALESCE(p_lote_id, 0) > 0 AND COALESCE(p_importacao_id, 0) = 0 THEN

        IF NOT EXISTS (
            SELECT 1
            FROM contab.lancamentos
            WHERE empresa_id = p_empresa_id
              AND lote_id = p_lote_id
        ) THEN
            RAISE EXCEPTION
                'Lote % não encontrado para empresa %',
                p_lote_id, p_empresa_id;
        END IF;

          
          SELECT
            array_agg(DISTINCT l.diario_id),
            array_agg(DISTINCT d.transacao_id)
                FILTER (WHERE d.transacao_id IS NOT NULL)
        INTO
            v_diario_ids,
            v_transacao_ids
        FROM contab.lancamentos l
        LEFT JOIN contab.diario d
        ON d.id = l.diario_id
        AND d.empresa_id = l.empresa_id
        WHERE l.empresa_id = p_empresa_id
        AND l.lote_id = p_lote_id;


        IF v_transacao_ids IS NOT NULL THEN

            UPDATE public.conciliacao_financeira
            SET transacao_id = NULL,
                status_conciliacao = 'rejeitado',
                mensagem_conciliacao =
                    'Lançamento excluído no contábil e removido do financeiro'
            WHERE empresa_id = p_empresa_id
            AND transacao_id = ANY(v_transacao_ids);

        END IF;

        DELETE
          FROM contab.lancamentos
         WHERE empresa_id = p_empresa_id
           AND lote_id = p_lote_id;

           
        GET DIAGNOSTICS v_qtd = ROW_COUNT;

            IF v_qtd < 2 THEN
            RAISE NOTICE
                'Atenção: lote % excluído com apenas % linha(s)',
                p_lote_id, v_qtd;
        END IF;

           DELETE FROM contab.diario d
                WHERE d.empresa_id = p_empresa_id
                AND d.id = ANY(v_diario_ids)
                AND NOT EXISTS (
                    SELECT 1
                    FROM contab.lancamentos l
                    WHERE l.empresa_id = d.empresa_id
                        AND l.diario_id = d.id
                );
 

     


         IF v_transacao_ids IS NOT NULL THEN 
            DELETE FROM public.transacoes
            WHERE empresa_id = p_empresa_id
            AND id = ANY(v_transacao_ids);

        END IF;


       

    END IF;

    -- exclui uma importação inteira
    IF COALESCE(p_lote_id, 0) = 0 AND COALESCE(p_importacao_id, 0) > 0 THEN

        IF NOT EXISTS (
            SELECT 1
            FROM contab.lancamentos
            WHERE empresa_id = p_empresa_id
              AND importacao_id = p_importacao_id
        ) THEN
            RAISE EXCEPTION
                'Importação % não encontrada para empresa %',
                p_importacao_id, p_empresa_id;
        END IF;

        DELETE
          FROM contab.lancamentos
         WHERE empresa_id = p_empresa_id
           AND importacao_id = p_importacao_id;

        GET DIAGNOSTICS v_qtd = ROW_COUNT;

        RAISE NOTICE
            'Importação % excluída com % linha(s)',
            p_importacao_id, v_qtd;
    END IF;

END;
$$;