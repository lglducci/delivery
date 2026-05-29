 CREATE OR REPLACE FUNCTION public.ff_conciliar_importacao_cartao(
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
    v_mes_referencia DATE;
    v_fatura_id BIGINT;
    v_compra_id BIGINT;
    v_transacao_id BIGINT;

    v_parcela_atual INTEGER;
    v_parcela_total INTEGER;
    v_valor_total_compra NUMERIC(12,2);
    v_data_parcela DATE;

    v_fechamento_dia INTEGER;
    v_vencimento_dia INTEGER;
    v_vencimento DATE;
    v_numero_fatura TEXT;
    v_data_base DATE;

    v_qtd_processadas INTEGER := 0;
    v_qtd_compras_criadas INTEGER := 0;
    v_qtd_faturas_criadas INTEGER := 0;
    v_qtd_transacoes_criadas INTEGER := 0;
    v_qtd_conciliadas INTEGER := 0;
    v_qtd_ignoradas INTEGER := 0;
BEGIN

IF p_data_referencia IS NULL THEN
    RAISE EXCEPTION 'Informe a data de referência da fatura.';
END IF;

v_mes_referencia := date_trunc('month', p_data_referencia)::DATE;

    SELECT ci.cartao_id 
      INTO v_cartao_id 
    FROM public.cartao_importacoes ci
    WHERE ci.id = p_importacao_id
      AND ci.empresa_id = p_empresa_id;

    IF v_cartao_id IS NULL THEN
        RAISE EXCEPTION 'Importação % não encontrada para empresa %.',
            p_importacao_id, p_empresa_id;
    END IF;

    SELECT c.fechamento_dia, c.vencimento_dia
      INTO v_fechamento_dia, v_vencimento_dia
    FROM public.cartoes c
    WHERE c.id = v_cartao_id
      AND c.empresa_id = p_empresa_id;

    /*
      REGRA NOVA:
      A importação representa UMA FATURA.
      Então define o mês da fatura UMA VEZ, pela primeira compra importada,
      e todas as linhas dessa importação entram nessa mesma fatura.
    */
    /*IF v_mes_referencia IS NULL THEN
        SELECT max(cc.data_compra)
          INTO v_data_base
        FROM public.conciliacao_cartoes cc
        WHERE cc.empresa_id = p_empresa_id
          AND cc.importacao_id = p_importacao_id
          AND cc.tipo_linha = 'compra'
          AND cc.valor > 0  ;

        IF v_data_base IS NULL THEN
            RAISE EXCEPTION 'Importação % não possui compras válidas para definir a fatura.',
                p_importacao_id;
        END IF;

        IF EXTRACT(DAY FROM v_data_base) > COALESCE(v_fechamento_dia, 31) THEN
            v_mes_referencia := date_trunc('month', v_data_base + INTERVAL '1 month')::DATE;
        ELSE
            v_mes_referencia := date_trunc('month', v_data_base)::DATE;
        END IF;

        UPDATE public.cartao_importacoes
           SET mes_referencia = v_mes_referencia
         WHERE id = p_importacao_id
           AND empresa_id = p_empresa_id;
    END IF;*/

    SELECT cf.id
      INTO v_fatura_id
    FROM public.cartoes_faturas cf
    WHERE cf.empresa_id = p_empresa_id
      AND cf.cartao_id = v_cartao_id
      AND cf.mes_referencia = v_mes_referencia
    LIMIT 1;

    IF v_fatura_id IS NULL THEN
        v_vencimento :=
            (v_mes_referencia + (COALESCE(v_vencimento_dia, 10) - 1) * INTERVAL '1 day')::DATE;

        v_numero_fatura :=
            'FATURA_CARTAO_' || v_cartao_id || '_' || to_char(v_mes_referencia, 'YYYY-MM');

        INSERT INTO public.cartoes_faturas (
            cartao_id,
            empresa_id,
            mes_referencia,
            valor_total,
            status,
            vencimento,
            numero,
            data_compra,
            evento_codigo
        )
        VALUES (
            v_cartao_id,
            p_empresa_id,
            v_mes_referencia,
            0,
            'aberta',
            v_vencimento,
            v_numero_fatura,
            v_data_base,
            'PAGAMENTO_CARTAO'
        )
        RETURNING id INTO v_fatura_id;

        v_qtd_faturas_criadas := v_qtd_faturas_criadas + 1;
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

        IF r.tipo_linha <> 'compra' OR r.valor <= 0 THEN
            UPDATE public.conciliacao_cartoes
               SET status_conciliacao = 'ignorado_credito_pagamento'
             WHERE id = r.id;

            v_qtd_ignoradas := v_qtd_ignoradas + 1;
            CONTINUE;
        END IF;

        v_parcela_atual := GREATEST(COALESCE(r.parcela_atual, 1), 1);
        v_parcela_total := GREATEST(COALESCE(r.parcela_total, 1), 1);

        v_data_parcela :=
            (r.data_compra + ((v_parcela_atual - 1) * INTERVAL '1 month'))::DATE;

        v_valor_total_compra := ROUND((r.valor * v_parcela_total)::NUMERIC, 2);

        SELECT cc.id
          INTO v_compra_id
        FROM public.cartoes_compras cc
        WHERE cc.empresa_id = p_empresa_id
          AND cc.cartao_id = v_cartao_id
          AND cc.parcelas = v_parcela_total
          AND ABS(cc.valor_total - v_valor_total_compra) <= 0.05
          AND cc.data_compra BETWEEN r.data_compra - INTERVAL '5 days'
                                 AND r.data_compra + INTERVAL '5 days'
          AND (
                upper(cc.descricao) = upper(r.estabelecimento)
                OR upper(cc.descricao) LIKE '%' || upper(r.estabelecimento) || '%'
                OR upper(r.estabelecimento) LIKE '%' || upper(cc.descricao) || '%'
              )
        ORDER BY cc.id DESC
        LIMIT 1;

        IF v_compra_id IS NULL THEN
            INSERT INTO public.cartoes_compras (
                empresa_id,
                cartao_id,
                descricao,
                valor_total,
                parcelas,
                data_compra,
                classificacao,
                tipo_evento,
                modelo_codigo
            )
            VALUES (
                p_empresa_id,
                v_cartao_id,
                r.estabelecimento,
                v_valor_total_compra,
                v_parcela_total,
                r.data_compra,
                'despesa',
                'cartao_compra',
                'CRIA_CARTAO_COMPRA'                
            )
            RETURNING id INTO v_compra_id;

            v_qtd_compras_criadas := v_qtd_compras_criadas + 1;
        END IF;

        SELECT ct.id
          INTO v_transacao_id
        FROM public.cartoes_transacoes ct
        WHERE ct.empresa_id = p_empresa_id
          AND ct.compra_id = v_compra_id
          AND ct.fatura_id = v_fatura_id
          AND ct.parcela_num = v_parcela_atual
          AND ct.parcela_total = v_parcela_total
          AND ABS(ct.valor - r.valor) <= 0.05
        LIMIT 1;

        IF v_transacao_id IS NULL THEN
            INSERT INTO public.cartoes_transacoes (
                empresa_id,
                fatura_id,
                compra_id,
                descricao,
                valor,
                parcela_num,
                parcela_total,
                data_parcela,
                data_compra,
                tipo_evento
            )
            VALUES (
                p_empresa_id,
                v_fatura_id,
                v_compra_id,
                r.estabelecimento,
                r.valor,
                v_parcela_atual,
                v_parcela_total,
                v_data_parcela,
                r.data_compra,
                'cartao_compra'
            )
            RETURNING id INTO v_transacao_id;

            UPDATE public.cartoes_faturas
               SET valor_total = COALESCE(valor_total, 0) + r.valor
             WHERE id = v_fatura_id
               AND empresa_id = p_empresa_id;

            PERFORM contab.marcar_reprocessamento(p_empresa_id, v_data_parcela);

            v_qtd_transacoes_criadas := v_qtd_transacoes_criadas + 1;
        END IF;

        UPDATE public.conciliacao_cartoes
           SET status_conciliacao = 'conciliado',
               transacao_cartao_id = v_transacao_id
         WHERE id = r.id;

        v_qtd_conciliadas := v_qtd_conciliadas + 1;
    END LOOP;

    UPDATE public.cartao_importacoes
       SET status = 'processado',
           mes_referencia = p_data_referencia
     WHERE id = p_importacao_id
       AND empresa_id = p_empresa_id;

    RETURN jsonb_build_object(
        'ok', true,
        'importacao_id', p_importacao_id,
        'cartao_id', v_cartao_id,
        'fatura_id', v_fatura_id,
        'mes_referencia', v_mes_referencia,
        'processadas', v_qtd_processadas,
        'compras_criadas', v_qtd_compras_criadas,
        'faturas_criadas', v_qtd_faturas_criadas,
        'transacoes_criadas', v_qtd_transacoes_criadas,
        'conciliadas', v_qtd_conciliadas,
        'ignoradas', v_qtd_ignoradas
    );
END;
$$;