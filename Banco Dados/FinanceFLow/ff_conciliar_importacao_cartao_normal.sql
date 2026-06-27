 CREATE OR REPLACE FUNCTION public.ff_conciliar_importacao_cartao_normal(
    p_empresa_id BIGINT,
    p_importacao_id BIGINT,
    p_data_referencia DATE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;

    v_cartao_id BIGINT;
    v_cartao_nome TEXT;
    v_fechamento_dia INT;

    v_periodo_ini DATE;
    v_periodo_fim DATE;

    v_compra_id BIGINT;
    v_contabil_id BIGINT;

    v_parcela_atual INT;
    v_parcela_total INT;
    v_valor_total NUMERIC(14,2);

    v_ultima_transacao_id BIGINT;
    v_transacao_id BIGINT;
    v_nova_compra_id BIGINT;

    v_qtd_processadas INT := 0;
    v_qtd_recriadas INT := 0;
    v_qtd_criadas INT := 0;
    v_qtd_ignoradas INT := 0;
    v_qtd_fora_contexto INT := 0;
    v_qtd_pendentes_antigas INT := 0;
    v_qtd_manuais_excluidas INT := 0;
BEGIN
    SELECT ci.cartao_id, c.nome, COALESCE(c.fechamento_dia, 20)
      INTO v_cartao_id, v_cartao_nome, v_fechamento_dia
    FROM public.cartao_importacoes ci
    JOIN public.cartoes c ON c.id = ci.cartao_id
    WHERE ci.id = p_importacao_id
      AND ci.empresa_id = p_empresa_id;

    IF v_cartao_id IS NULL THEN
        RAISE EXCEPTION 'Importação % não encontrada.', p_importacao_id;
    END IF;

    /*
      CONTEXTO DA FATURA:
      Se a referência é 2026-01-01 e o vencimento é dia 20:
      período permitido = 2025-12-21 até 2026-01-20.

      Compra fora desse período não pode gerar compra nova
      e também não pode excluir/recriar compra existente.
    */
     
 
    
 
    v_periodo_ini :=
    (
        date_trunc('month', p_data_referencia)::date
        - INTERVAL '1 month'
        + (v_fechamento_dia - 1) * INTERVAL '1 day'
    )::date;

v_periodo_fim :=
    (
        date_trunc('month', p_data_referencia)::date
        + (v_fechamento_dia - 2) * INTERVAL '1 day'
    )::date;

    FOR r IN
        SELECT *
        FROM public.conciliacao_cartoes
        WHERE empresa_id = p_empresa_id
          AND importacao_id = p_importacao_id
          AND status_conciliacao = 'pendente'
        ORDER BY data_compra, id
    LOOP
        v_qtd_processadas := v_qtd_processadas + 1;

    IF r.tipo_linha NOT IN ('compra', 'parcela') OR r.valor <= 0 THEN
            UPDATE public.conciliacao_cartoes
               SET status_conciliacao = 'ignorado_credito_pagamento'
             WHERE id = r.id;

            v_qtd_ignoradas := v_qtd_ignoradas + 1;
            CONTINUE;
        END IF;

        v_parcela_atual := GREATEST(COALESCE(r.parcela_atual, 1), 1);
        v_parcela_total := GREATEST(COALESCE(r.parcela_total, 1), 1);
        v_valor_total := ROUND((r.valor * v_parcela_total)::NUMERIC, 2);

        v_compra_id := NULL;
        v_contabil_id := NULL;
        v_transacao_id := NULL;
        v_nova_compra_id := NULL;
        v_ultima_transacao_id := NULL;

        /*
          REGRA DE SEGURANÇA:
          Compra fora do contexto da fatura não é compra nova deste mês.
          Não pode excluir e não pode inserir.
        
        IF r.tipo_linha = 'compra'
   AND (r.data_compra < v_periodo_ini OR r.data_compra > v_periodo_fim)
THEN
            UPDATE public.conciliacao_cartoes
               SET status_conciliacao = 'fora_contexto_fatura'
             WHERE id = r.id;

            v_qtd_fora_contexto := v_qtd_fora_contexto + 1;
            CONTINUE;
        END IF; */

        /*
          Procura compra manual/existente apenas dentro do contexto.
        */
       SELECT cc.id, cc.conta_contabil_id
  INTO v_compra_id, v_contabil_id
FROM public.cartoes_compras cc
WHERE cc.empresa_id = p_empresa_id
  AND cc.cartao_id = v_cartao_id
  AND COALESCE(cc.implantacao, false) = false
  AND COALESCE(cc.tipo_compra, 'manual') = 'manual'
 -- AND cc.data_compra BETWEEN v_periodo_ini AND v_periodo_fim
  AND ABS(cc.valor_total - v_valor_total) <= 0.05
  AND cc.parcelas = v_parcela_total
  AND (
        upper(cc.descricao) = upper(r.estabelecimento)
        OR upper(cc.descricao) LIKE '%' || upper(r.estabelecimento) || '%'
        OR upper(r.estabelecimento) LIKE '%' || upper(cc.descricao) || '%'
      )
  AND cc.data_compra BETWEEN r.data_compra - INTERVAL '10 days'
                         AND r.data_compra + INTERVAL '10 days'
ORDER BY cc.id DESC
LIMIT 1;

        UPDATE public.conciliacao_cartoes
           SET compra_match_id = v_compra_id,
               contabil_id = v_contabil_id
         WHERE id = r.id;

        /*
          Parcela 2/N, 7/N etc não pode criar compra nova.
          Se não achou compra existente, fica pendente.
        */
        IF v_compra_id IS NULL AND v_parcela_atual > 1 THEN
            UPDATE public.conciliacao_cartoes
               SET status_conciliacao = 'pendente_compra_anterior_nao_encontrada'
             WHERE id = r.id;

            v_qtd_pendentes_antigas := v_qtd_pendentes_antigas + 1;
            CONTINUE;
        END IF;

        /*
          Se achou compra existente e é parcela antiga,
          não exclui/recria. Só procura a transação.
        */
        IF v_compra_id IS NOT NULL AND v_parcela_atual > 1 THEN
            SELECT ct.id
              INTO v_transacao_id
            FROM public.cartoes_transacoes ct
            WHERE ct.empresa_id = p_empresa_id
              AND ct.compra_id = v_compra_id
              AND ct.parcela_num = v_parcela_atual
              AND ct.parcela_total = v_parcela_total
              AND ABS(ct.valor - r.valor) <= 0.05
            LIMIT 1;

            IF v_transacao_id IS NULL THEN
                UPDATE public.conciliacao_cartoes
                   SET status_conciliacao = 'pendente_transacao_anterior_nao_encontrada'
                 WHERE id = r.id;

                v_qtd_pendentes_antigas := v_qtd_pendentes_antigas + 1;
                CONTINUE;
            END IF;

            UPDATE public.conciliacao_cartoes
               SET status_conciliacao = 'conciliado',
                   transacao_cartao_id = v_transacao_id,
                   compra_match_id = v_compra_id,
                   contabil_id = v_contabil_id
             WHERE id = r.id;

            CONTINUE;
        END IF;

        /*
          Daqui para baixo só entra compra do contexto e parcela 1/N.
          Agora pode excluir/recriar ou criar nova.
        */
        IF v_compra_id IS NOT NULL THEN
            PERFORM public.ff_excluir_compra_cartao(
                p_empresa_id,
                v_compra_id
            );

            v_qtd_recriadas := v_qtd_recriadas + 1;
        ELSE
            v_qtd_criadas := v_qtd_criadas + 1;
        END IF;

        SELECT public.ff_registrar_compra_credito(
            p_empresa_id,
            v_cartao_nome,
            r.estabelecimento,
            v_valor_total,
            v_parcela_total,
            r.data_compra,
            v_contabil_id,
            'despesa',
            'CRIA_CARTAO_COMPRA',
            'importacao',
            p_importacao_id
        )
        INTO v_ultima_transacao_id;

        SELECT ct.compra_id
          INTO v_nova_compra_id
        FROM public.cartoes_transacoes ct
        WHERE ct.id = v_ultima_transacao_id
          AND ct.empresa_id = p_empresa_id;

        SELECT ct.id
          INTO v_transacao_id
        FROM public.cartoes_transacoes ct
        WHERE ct.empresa_id = p_empresa_id
          AND ct.compra_id = v_nova_compra_id
          AND ct.parcela_num = v_parcela_atual
          AND ct.parcela_total = v_parcela_total
          AND ABS(ct.valor - r.valor) <= 0.05
        LIMIT 1;

        UPDATE public.conciliacao_cartoes
           SET status_conciliacao = 'conciliado',
               transacao_cartao_id = COALESCE(v_transacao_id, v_ultima_transacao_id),
               compra_match_id = COALESCE(v_nova_compra_id, v_compra_id),
               contabil_id = v_contabil_id
         WHERE id = r.id;

        PERFORM contab.marcar_reprocessamento(p_empresa_id, r.data_compra);
    END LOOP;


       

    /*
      Limpa compras manuais do período da fatura implantada
      que não foram aproveitadas pela importação atual.
    */
    SELECT public.ff_limpar_compras_manuais_cartao(
        p_empresa_id,
        v_cartao_id,
        p_importacao_id,
        v_periodo_ini, v_periodo_fim 
    )
    INTO v_qtd_manuais_excluidas;

 

    UPDATE public.cartao_importacoes
       SET status = 'processado',
           mes_referencia = date_trunc('month', p_data_referencia)::date,
           tipo_importacao = 'normal'
     WHERE id = p_importacao_id
       AND empresa_id = p_empresa_id;





    RETURN jsonb_build_object(
        'ok', true,
        'tipo', 'normal',
        'importacao_id', p_importacao_id,
        'cartao_id', v_cartao_id,
        'periodo_ini', v_periodo_ini,
        'periodo_fim', v_periodo_fim,
        'processadas', v_qtd_processadas,
        'compras_recriadas', v_qtd_recriadas,
        'compras_criadas', v_qtd_criadas,
        'fora_contexto_fatura', v_qtd_fora_contexto,
        'pendentes_compras_antigas', v_qtd_pendentes_antigas,
        'ignoradas', v_qtd_ignoradas,
        'compras_manuais_excluidas', v_qtd_manuais_excluidas
    );
END;
$$;