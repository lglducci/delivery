 CREATE OR REPLACE FUNCTION public.ff_limpar_compras_manuais_cartao(
    p_empresa_id BIGINT,
    p_cartao_id BIGINT,
    p_importacao_id BIGINT,
    p_data_ini DATE,
    p_data_fim DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    m RECORD;
    v_qtd_manuais_excluidas INT := 0;
BEGIN
    FOR m IN
        SELECT cc.id
        FROM public.cartoes_compras cc
        WHERE cc.empresa_id = p_empresa_id
          AND cc.cartao_id = p_cartao_id
          AND COALESCE(cc.tipo_compra, 'manual') = 'manual'
          AND COALESCE(cc.implantacao, false) = false
          AND (p_data_ini IS NULL OR cc.data_compra >= p_data_ini)
          AND (p_data_fim IS NULL OR cc.data_compra <= p_data_fim)

          -- Só pode limpar compra que ainda está em fatura aberta.
          AND EXISTS (
              SELECT 1
              FROM public.cartoes_transacoes ct
              JOIN public.cartoes_faturas cf
                ON cf.id = ct.fatura_id
               AND cf.empresa_id = ct.empresa_id
              WHERE ct.empresa_id = p_empresa_id
                AND ct.compra_id = cc.id
                AND cf.cartao_id = p_cartao_id
                AND cf.status = 'aberta'
          )

          -- Não exclui compra manual que foi aproveitada pela importação atual.
          AND NOT EXISTS (
              SELECT 1
              FROM public.conciliacao_cartoes cx
              WHERE cx.empresa_id = p_empresa_id
                AND cx.importacao_id = p_importacao_id
                AND cx.compra_match_id = cc.id
          )
    LOOP
        PERFORM public.ff_excluir_compra_cartao(
            p_empresa_id,
            m.id
        );

        v_qtd_manuais_excluidas := v_qtd_manuais_excluidas + 1;
    END LOOP;

    RETURN v_qtd_manuais_excluidas;
END;
$$;