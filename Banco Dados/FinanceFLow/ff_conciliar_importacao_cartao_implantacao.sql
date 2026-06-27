 CREATE OR REPLACE FUNCTION public.ff_conciliar_importacao_cartao_implantacao(
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
    v_mes_referencia DATE;

    v_compra_id BIGINT;
    v_transacao_id BIGINT;
    v_ultima_transacao_id BIGINT;

    v_parcela_atual INTEGER;
    v_parcela_total INTEGER;
    v_parcelas_restantes INTEGER;
    v_valor_total_implantacao NUMERIC(14,2);

    v_data_implantacao DATE;

    v_qtd_processadas INTEGER := 0;
    v_qtd_compras_criadas INTEGER := 0;
    v_qtd_conciliadas INTEGER := 0;
    v_qtd_ignoradas INTEGER := 0;
    v_qtd_manuais_excluidas INTEGER :=0;
BEGIN
    IF p_data_referencia IS NULL THEN
        RAISE EXCEPTION 'Informe a data de referência da implantação.';
    END IF;

    /*
      p_data_referencia = mês/referência da fatura importada.
      v_data_implantacao = data real em que o saldo será criado.
    */
    v_mes_referencia := date_trunc('month', p_data_referencia)::DATE;
 
    v_data_implantacao := v_mes_referencia;


    SELECT ci.cartao_id, c.nome
      INTO v_cartao_id, v_cartao_nome
    FROM public.cartao_importacoes ci
    JOIN public.cartoes c ON c.id = ci.cartao_id
    WHERE ci.id = p_importacao_id
      AND ci.empresa_id = p_empresa_id
      AND c.empresa_id = p_empresa_id;

    IF v_cartao_id IS NULL THEN
        RAISE EXCEPTION 'Importação % não encontrada para empresa %.',
            p_importacao_id, p_empresa_id;
    END IF;

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

        IF v_parcela_atual > v_parcela_total THEN
            v_parcela_atual := v_parcela_total;
        END IF;

        /*
          Exemplo:
          Parcela original 5/12 de 157,53
          Restam 8 parcelas.
          Compra técnica = 8 x 157,53.
        */
        v_parcelas_restantes := v_parcela_total - v_parcela_atual + 1;
        v_valor_total_implantacao := ROUND((r.valor * v_parcelas_restantes)::NUMERIC, 2);

        v_compra_id := NULL;
        v_transacao_id := NULL;
        v_ultima_transacao_id := NULL;

        /*
          Evita duplicar se rodar a implantação novamente.
        */
        SELECT cc.id
          INTO v_compra_id
        FROM public.cartoes_compras cc
        WHERE cc.empresa_id = p_empresa_id
          AND cc.cartao_id = v_cartao_id
          AND COALESCE(cc.implantacao, false) = true
          AND cc.parcela_inicio_implantacao = v_parcela_atual
          AND cc.parcela_total_original = v_parcela_total
          AND cc.parcelas = v_parcelas_restantes
          AND ABS(cc.valor_total - v_valor_total_implantacao) <= 0.05
          AND COALESCE(cc.tipo_compra, 'manual') = 'implantacao'
          AND (
                upper(cc.descricao) = upper(r.estabelecimento)
                OR upper(cc.descricao) LIKE '%' || upper(r.estabelecimento) || '%'
                OR upper(r.estabelecimento) LIKE '%' || upper(cc.descricao) || '%'
              )
        ORDER BY cc.id DESC
        LIMIT 1;

        /*
          Se não existe compra técnica, cria pelo motor oficial.
          A ff_registrar_compra_credito cria:
          compra, transações, faturas, projeção e atualiza valores das faturas.
        */
        IF v_compra_id IS NULL THEN
            SELECT public.ff_registrar_compra_credito(
                p_empresa_id,
                v_cartao_nome,
                r.estabelecimento,
                v_valor_total_implantacao,
                v_parcelas_restantes,
                v_data_implantacao,
                NULL,
                'despesa',
                'CRIA_CARTAO_COMPRA',
                'implantacao',
                 p_importacao_id 
            )
            INTO v_ultima_transacao_id;

            SELECT ct.compra_id
              INTO v_compra_id
            FROM public.cartoes_transacoes ct
            WHERE ct.id = v_ultima_transacao_id
              AND ct.empresa_id = p_empresa_id;

            UPDATE public.cartoes_compras
               SET implantacao = true,
                   parcela_inicio_implantacao = v_parcela_atual,
                   parcela_total_original = v_parcela_total
             WHERE id = v_compra_id
               AND empresa_id = p_empresa_id;

            v_qtd_compras_criadas := v_qtd_compras_criadas + 1;
        END IF;

        /*
          Na implantação, a parcela original vira parcela técnica:
          original 5/12 => técnica 1/8
          original 6/12 => técnica 2/8, etc.

          Aqui estamos conciliando a linha atual da primeira fatura,
          então a parcela técnica é sempre 1.
        */
        SELECT ct.id
          INTO v_transacao_id
        FROM public.cartoes_transacoes ct
        WHERE ct.empresa_id = p_empresa_id
          AND ct.compra_id = v_compra_id
          AND ct.parcela_num = 1
          AND ct.parcela_total = v_parcelas_restantes
          AND ABS(ct.valor - r.valor) <= 0.05
        LIMIT 1;

        UPDATE public.conciliacao_cartoes
           SET status_conciliacao = 'conciliado',
               transacao_cartao_id = v_transacao_id,
               compra_match_id = v_compra_id
         WHERE id = r.id;

        v_qtd_conciliadas := v_qtd_conciliadas + 1;
    END LOOP;

     SELECT public.ff_limpar_compras_manuais_cartao(
        p_empresa_id,
        v_cartao_id,
        p_importacao_id,
        null, 
        null 
    )
    INTO v_qtd_manuais_excluidas;


    UPDATE public.cartao_importacoes
       SET status = 'processado',
           mes_referencia = v_mes_referencia,
           tipo_importacao = 'implantacao',
           data_corte = v_mes_referencia
     WHERE id = p_importacao_id
       AND empresa_id = p_empresa_id;

    RETURN jsonb_build_object(
        'ok', true,
        'tipo', 'implantacao',
        'importacao_id', p_importacao_id,
        'cartao_id', v_cartao_id,
        'mes_referencia', v_mes_referencia,
        'data_implantacao', v_data_implantacao,
        'processadas', v_qtd_processadas,
        'compras_implantacao_criadas', v_qtd_compras_criadas,
        'conciliadas', v_qtd_conciliadas,
        'ignoradas', v_qtd_ignoradas
    );
END;
$$;