 CREATE OR REPLACE FUNCTION public.ff_sugerir_contas_importacao_cartao(
    p_empresa_id BIGINT,
    p_cartao_id BIGINT,
    p_fechamento_dia INT,
    p_ids JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_item JSONB;

    v_linha INT;
    v_data DATE;
    v_descricao TEXT;
    v_valor NUMERIC(14,2);
    v_parcela_total INT;
    v_valor_total NUMERIC(14,2);

    v_compra_id BIGINT;
    v_contabil_id BIGINT;

    v_resultado JSONB := '[]'::JSONB;
BEGIN
    IF p_ids IS NULL OR jsonb_typeof(p_ids) <> 'array' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'mensagem', 'O parâmetro p_ids deve ser um array JSON.',
            'data', '[]'::JSONB
        );
    END IF;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_ids)
    LOOP
        v_linha :=
            NULLIF(v_item->>'linha', '')::INT;

        v_data :=
            NULLIF(v_item->>'data', '')::DATE;

        v_descricao :=
            COALESCE(
                NULLIF(TRIM(v_item->>'estabelecimento'), ''),
                NULLIF(TRIM(v_item->>'descricao'), ''),
                NULLIF(TRIM(v_item->>'historico'), ''),
                ''
            );

        v_valor :=
            COALESCE(
                NULLIF(v_item->>'valor', '')::NUMERIC,
                0
            );

        v_parcela_total :=
            GREATEST(
                COALESCE(
                    NULLIF(v_item->>'parcela_total', '')::INT,
                    1
                ),
                1
            );

        v_valor_total :=
            ROUND(v_valor * v_parcela_total, 2);

        v_compra_id := NULL;
        v_contabil_id := NULL;

        /*
          Apenas compras positivas precisam buscar
          conta contábil em compra manual anterior.
        */
        IF v_valor > 0 AND v_data IS NOT NULL THEN
            SELECT
                cc.id,
                cc.conta_contabil_id
            INTO
                v_compra_id,
                v_contabil_id
            FROM public.cartoes_compras cc
            WHERE cc.empresa_id = p_empresa_id
              AND cc.cartao_id = p_cartao_id
              AND TRIM(COALESCE(cc.tipo_compra, 'manual')) = 'manual'
              AND cc.conta_contabil_id IS NOT NULL
              AND ABS(cc.valor_total - v_valor_total) <= 0.05
              AND COALESCE(cc.parcelas, 1) = v_parcela_total
              AND cc.data_compra BETWEEN
                    v_data - INTERVAL '10 days'
                    AND
                    v_data + INTERVAL '10 days'

            ORDER BY
                /*
                  Descrição apenas melhora o desempate.
                  Nunca impede o encontro.
                */
                CASE
                    WHEN UPPER(TRIM(COALESCE(cc.descricao, ''))) =
                         UPPER(v_descricao)
                    THEN 0

                    WHEN UPPER(TRIM(COALESCE(cc.descricao, ''))) LIKE
                         '%' || UPPER(v_descricao) || '%'
                    THEN 1

                    WHEN UPPER(v_descricao) LIKE
                         '%' || UPPER(TRIM(COALESCE(cc.descricao, ''))) || '%'
                    THEN 1

                    ELSE 2
                END,

                ABS(cc.data_compra - v_data),
                cc.id DESC

            LIMIT 1;
        END IF;

        v_resultado :=
            v_resultado ||
            jsonb_build_array(
                jsonb_build_object(
                    'linha', v_linha,
                    'contabil_id', v_contabil_id,
                    'compra_match_id', v_compra_id
                )
            );
    END LOOP;

    RETURN jsonb_build_object(
        'ok', true,
        'data', v_resultado
    );
END;
$$;