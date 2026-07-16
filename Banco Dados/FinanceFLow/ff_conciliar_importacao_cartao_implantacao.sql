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
    v_fatura_id BIGINT;

    v_parcela_atual INTEGER;
    v_parcela_total INTEGER;
    v_parcelas_restantes INTEGER;
    v_valor_total_implantacao NUMERIC(14,2);

    v_data_implantacao DATE;
    v_data_compra DATE;

    v_qtd_processadas INTEGER := 0;
    v_qtd_compras_criadas INTEGER := 0;
    v_qtd_conciliadas INTEGER := 0;
    v_qtd_ignoradas INTEGER := 0;
    v_qtd_creditos INTEGER := 0;
    v_qtd_manuais_excluidas INTEGER := 0;

    v_fechamento_dia INTEGER := 0;
BEGIN
    IF p_data_referencia IS NULL THEN
        RAISE EXCEPTION
            'Informe a data de referência da implantação.';
    END IF;

    --------------------------------------------------------------
    -- REFERÊNCIA DA FATURA IMPLANTADA
    --------------------------------------------------------------
    v_mes_referencia :=
        date_trunc(
            'month',
            p_data_referencia
        )::date;

    v_data_implantacao := v_mes_referencia;

    --------------------------------------------------------------
    -- CARTÃO
    --------------------------------------------------------------
    SELECT
        ci.cartao_id,
        c.nome,
        COALESCE(c.fechamento_dia, 20)
    INTO
        v_cartao_id,
        v_cartao_nome,
        v_fechamento_dia
    FROM public.cartao_importacoes ci
    JOIN public.cartoes c
      ON c.id = ci.cartao_id
     AND c.empresa_id = ci.empresa_id
    WHERE ci.id = p_importacao_id
      AND ci.empresa_id = p_empresa_id;

    IF v_cartao_id IS NULL THEN
        RAISE EXCEPTION
            'Importação % não encontrada para empresa %.',
            p_importacao_id,
            p_empresa_id;
    END IF;

    --------------------------------------------------------------
    -- PROCESSA PRIMEIRO COMPRAS E PARCELAS POSITIVAS.
    -- CRÉDITOS/ESTORNOS FICAM POR ÚLTIMO.
    --------------------------------------------------------------
    FOR r IN
        SELECT *
        FROM public.conciliacao_cartoes
        WHERE empresa_id = p_empresa_id
          AND importacao_id = p_importacao_id
          AND status_conciliacao = 'pendente'
        ORDER BY
            CASE
                WHEN valor > 0 THEN 0
                ELSE 1
            END,
            data_compra,
            id
    LOOP
        v_qtd_processadas :=
            v_qtd_processadas + 1;

        ----------------------------------------------------------
        -- PAGAMENTO DE FATURA ANTERIOR: IGNORA
        ----------------------------------------------------------
        IF r.tipo_linha = 'pagamento' THEN
            UPDATE public.conciliacao_cartoes
               SET status_conciliacao =
                   'ignorado_pagamento'
             WHERE id = r.id;

            v_qtd_ignoradas :=
                v_qtd_ignoradas + 1;

            CONTINUE;
        END IF;

        ----------------------------------------------------------
        -- CRÉDITO OU ESTORNO:
        -- ENTRA NEGATIVO NA FATURA DA IMPLANTAÇÃO
        ----------------------------------------------------------
        IF r.tipo_linha = 'credito'
           AND r.valor < 0 THEN

            v_fatura_id := NULL;
            v_transacao_id := NULL;

            SELECT cf.id
              INTO v_fatura_id
            FROM public.cartoes_faturas cf
            WHERE cf.empresa_id = p_empresa_id
              AND cf.cartao_id = v_cartao_id
              AND cf.mes_referencia =
                  v_mes_referencia
            ORDER BY cf.id DESC
            LIMIT 1;

            IF v_fatura_id IS NULL THEN
                RAISE EXCEPTION
                    'Fatura de implantação não encontrada. Cartão %, referência %.',
                    v_cartao_id,
                    v_mes_referencia;
            END IF;

            INSERT INTO public.cartoes_transacoes (
                fatura_id,
                empresa_id,
                compra_id,
                descricao,
                valor,
                parcela_num,
                parcela_total,
                data_compra,
                data_parcela
            )
            VALUES (
                v_fatura_id,
                p_empresa_id,
                NULL,
                '[ESTORNO/CRÉDITO] ' ||
                    r.estabelecimento,
                r.valor,
                1,
                1,
                r.data_compra,
                r.data_compra
            )
            RETURNING id
            INTO v_transacao_id;

            /*
              r.valor já é negativo.
              Exemplo:
              1.798,86 + (-590,79) = 1.208,07
            */
            UPDATE public.cartoes_faturas
               SET valor_total =
                   COALESCE(valor_total, 0) +
                   r.valor
             WHERE id = v_fatura_id
               AND empresa_id = p_empresa_id;

            UPDATE public.conciliacao_cartoes
               SET status_conciliacao =
                       'conciliado',
                   transacao_cartao_id =
                       v_transacao_id,
                   compra_match_id = NULL
             WHERE id = r.id;

            v_qtd_creditos :=
                v_qtd_creditos + 1;

            v_qtd_conciliadas :=
                v_qtd_conciliadas + 1;

            PERFORM contab.marcar_reprocessamento(
                p_empresa_id,
                r.data_compra
            );

            CONTINUE;
        END IF;

        ----------------------------------------------------------
        -- OUTROS TIPOS NÃO PROCESSADOS
        ----------------------------------------------------------
        IF r.tipo_linha NOT IN (
            'compra',
            'parcela'
        )
        OR r.valor <= 0 THEN

            UPDATE public.conciliacao_cartoes
               SET status_conciliacao =
                   'ignorado_tipo_linha'
             WHERE id = r.id;

            v_qtd_ignoradas :=
                v_qtd_ignoradas + 1;

            CONTINUE;
        END IF;

        ----------------------------------------------------------
        -- DADOS DA COMPRA/PARCELA DE IMPLANTAÇÃO
        ----------------------------------------------------------
        v_parcela_atual :=
            GREATEST(
                COALESCE(r.parcela_atual, 1),
                1
            );

        v_parcela_total :=
            GREATEST(
                COALESCE(r.parcela_total, 1),
                1
            );

        IF v_parcela_atual > v_parcela_total THEN
            v_parcela_atual :=
                v_parcela_total;
        END IF;

        /*
          Exemplo:
          parcela original 5/12
          restam 8 parcelas

          compra técnica:
          8 x valor da parcela
        */
        v_parcelas_restantes :=
            v_parcela_total -
            v_parcela_atual +
            1;

        v_valor_total_implantacao :=
            ROUND(
                (
                    r.valor *
                    v_parcelas_restantes
                )::numeric,
                2
            );

        v_compra_id := NULL;
        v_transacao_id := NULL;
        v_ultima_transacao_id := NULL;

        ----------------------------------------------------------
        -- EVITA DUPLICAR COMPRA TÉCNICA
        ----------------------------------------------------------
        SELECT cc.id
          INTO v_compra_id
        FROM public.cartoes_compras cc
        WHERE cc.empresa_id = p_empresa_id
          AND cc.cartao_id = v_cartao_id
          AND COALESCE(
                  cc.implantacao,
                  false
              ) = true
          AND cc.parcela_inicio_implantacao =
              v_parcela_atual
          AND cc.parcela_total_original =
              v_parcela_total
          AND cc.parcelas =
              v_parcelas_restantes
          AND ABS(
                  cc.valor_total -
                  v_valor_total_implantacao
              ) <= 0.05
          AND COALESCE(
                  cc.tipo_compra,
                  'manual'
              ) = 'implantacao'
          AND (
                upper(cc.descricao) =
                    upper(
                        '[IMPLANTAÇÃO] ' ||
                        r.estabelecimento
                    )

                OR upper(cc.descricao) LIKE
                    '%' ||
                    upper(r.estabelecimento) ||
                    '%'

                OR upper(r.estabelecimento) LIKE
                    '%' ||
                    upper(cc.descricao) ||
                    '%'
              )
        ORDER BY cc.id DESC
        LIMIT 1;

        ----------------------------------------------------------
        -- CRIA COMPRA TÉCNICA DE IMPLANTAÇÃO
        ----------------------------------------------------------
        IF v_compra_id IS NULL THEN

            SELECT
                public.ff_normalizar_data_compra_implantacao(
                    r.data_compra,
                    v_mes_referencia,
                    v_fechamento_dia
                )
            INTO v_data_compra;

            SELECT public.ff_registrar_compra_credito(
                p_empresa_id,
                v_cartao_nome,
                '[IMPLANTAÇÃO] ' ||
                    r.estabelecimento,
                v_valor_total_implantacao,
                v_parcelas_restantes,

                /*
                  Mantém a data histórica no cabeçalho da compra.
                */
                r.data_compra,

                r.contabil_id,
                'despesa',
                'CRIA_CARTAO_COMPRA',
                'implantacao',
                p_importacao_id,

                /*
                  Início das parcelas normalizado
                  dentro do período da fatura.
                */
                v_data_compra
            )
            INTO v_ultima_transacao_id;

            SELECT ct.compra_id
              INTO v_compra_id
            FROM public.cartoes_transacoes ct
            WHERE ct.id =
                  v_ultima_transacao_id
              AND ct.empresa_id =
                  p_empresa_id;

            UPDATE public.cartoes_compras
               SET implantacao = true,
                   parcela_inicio_implantacao =
                       v_parcela_atual,
                   parcela_total_original =
                       v_parcela_total
             WHERE id = v_compra_id
               AND empresa_id =
                   p_empresa_id;

            v_qtd_compras_criadas :=
                v_qtd_compras_criadas + 1;
        END IF;

        ----------------------------------------------------------
        -- PRIMEIRA PARCELA TÉCNICA DA IMPLANTAÇÃO
        ----------------------------------------------------------
        SELECT ct.id
          INTO v_transacao_id
        FROM public.cartoes_transacoes ct
        WHERE ct.empresa_id = p_empresa_id
          AND ct.compra_id = v_compra_id
          AND ct.parcela_num = 1
          AND ct.parcela_total =
              v_parcelas_restantes
          AND ABS(
                  ct.valor -
                  r.valor
              ) <= 0.05
        LIMIT 1;

        IF v_transacao_id IS NULL THEN
            RAISE EXCEPTION
                'Transação técnica não encontrada. Compra %, estabelecimento %, valor %.',
                v_compra_id,
                r.estabelecimento,
                r.valor;
        END IF;

        UPDATE public.conciliacao_cartoes
           SET status_conciliacao =
                   'conciliado',
               transacao_cartao_id =
                   v_transacao_id,
               compra_match_id =
                   v_compra_id,
               contabil_id =
                   COALESCE(
                       r.contabil_id,
                       contabil_id
                   )
         WHERE id = r.id;

        v_qtd_conciliadas :=
            v_qtd_conciliadas + 1;
    END LOOP;

    --------------------------------------------------------------
    -- LIMPEZA DE COMPRAS MANUAIS
    --------------------------------------------------------------
    SELECT public.ff_limpar_compras_manuais_cartao(
        p_empresa_id,
        v_cartao_id,
        p_importacao_id,
        NULL,
        NULL
    )
    INTO v_qtd_manuais_excluidas;

    --------------------------------------------------------------
    -- FINALIZA IMPORTAÇÃO
    --------------------------------------------------------------
    UPDATE public.cartao_importacoes
       SET status = 'processado',
           mes_referencia =
               v_mes_referencia,
           tipo_importacao =
               'implantacao',
           data_corte =
               v_mes_referencia
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
        'compras_implantacao_criadas',
            v_qtd_compras_criadas,
        'creditos_estornos',
            v_qtd_creditos,
        'conciliadas',
            v_qtd_conciliadas,
        'ignoradas',
            v_qtd_ignoradas,
        'compras_manuais_excluidas',
            v_qtd_manuais_excluidas
    );
END;
$$;