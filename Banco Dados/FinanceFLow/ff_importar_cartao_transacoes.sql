 CREATE OR REPLACE FUNCTION public.ff_importar_cartao_transacoes(
    p_empresa_id BIGINT,
    p_cartao_id BIGINT,
    p_origem_arquivo TEXT,
    p_lancamentos JSONB,
    p_mes_referencia DATE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_importacao_id BIGINT;
    v_item JSONB;

    v_data DATE;
    v_estabelecimento TEXT;
    v_portador TEXT;
    v_valor NUMERIC(14,2);
    v_parcela_texto TEXT;
    v_parcela_atual INTEGER;
    v_parcela_total INTEGER;
    v_tipo_linha TEXT;
    v_hash TEXT;

    v_tipo_importacao TEXT;
    v_qtd_processadas INTEGER := 0;

    v_total_linhas INTEGER := 0;
    v_total_compras NUMERIC(14,2) := 0;
    v_total_creditos NUMERIC(14,2) := 0;
    v_implantacao_existente BOOLEAN := false;
     v_data_corte DATE;
     v_contabil_id BIGINT;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id obrigatório';
    END IF;

    IF p_cartao_id IS NULL THEN
        RAISE EXCEPTION 'cartao_id obrigatório';
    END IF;

    IF p_lancamentos IS NULL OR jsonb_typeof(p_lancamentos) <> 'array' THEN
        RAISE EXCEPTION 'p_lancamentos deve ser um array JSONB';
    END IF;

    IF p_mes_referencia IS NULL THEN
        RAISE EXCEPTION 'Referência da fatura obrigatória.';
    END IF;

    p_mes_referencia := date_trunc('month', p_mes_referencia)::date;
   
        SELECT TRUE, MIN(COALESCE(data_corte, mes_referencia))
        INTO v_implantacao_existente, v_data_corte
        FROM public.cartao_importacoes
        WHERE empresa_id = p_empresa_id
        AND cartao_id = p_cartao_id
        AND status IN ('processado', 'conciliado')
        AND tipo_importacao = 'implantacao';

        v_implantacao_existente := COALESCE(v_implantacao_existente, false);

        IF EXISTS (
            SELECT 1
            FROM public.cartao_importacoes
            WHERE empresa_id = p_empresa_id
            AND cartao_id = p_cartao_id
            AND status IN ('processado', 'conciliado')
            AND mes_referencia = p_mes_referencia
        ) THEN
            RAISE EXCEPTION
            'Já existe importação processada para este cartão nesta referência.';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM public.cartao_importacoes
            WHERE empresa_id = p_empresa_id
            AND cartao_id = p_cartao_id
            AND status IN ('processado', 'conciliado')
            AND mes_referencia > p_mes_referencia
        ) THEN
            RAISE EXCEPTION
            'Não é possível importar fatura anterior. Já existe importação posterior processada para este cartão.';
        END IF;

        IF v_implantacao_existente
        AND p_mes_referencia < v_data_corte
        THEN
            RAISE EXCEPTION
            'Não é possível importar fatura anterior à implantação deste cartão.';
        END IF;

        v_tipo_importacao :=
            CASE
                WHEN v_implantacao_existente THEN 'normal'
                ELSE 'implantacao'
            END;





    INSERT INTO public.cartao_importacoes (
        empresa_id,
        cartao_id,
        origem_arquivo,
        descricao,
        status,
        mes_referencia,
        tipo_importacao,
        data_corte
    )
    VALUES (
        p_empresa_id,
        p_cartao_id,
        p_origem_arquivo,
        'Importação de cartão - ' || COALESCE(p_origem_arquivo, 'arquivo'),
        'importado',
        p_mes_referencia,
        v_tipo_importacao,
        CASE WHEN v_tipo_importacao = 'implantacao' THEN p_mes_referencia ELSE NULL END
    )
    RETURNING id INTO v_importacao_id;

    FOR v_item IN
        SELECT * FROM jsonb_array_elements(p_lancamentos)
    LOOP
        v_data := NULLIF(v_item->>'data', '')::DATE;

        v_estabelecimento := COALESCE(
            NULLIF(v_item->>'estabelecimento', ''),
            NULLIF(v_item->>'descricao', ''),
            NULLIF(v_item->>'historico', '')
        );

        v_portador := NULLIF(v_item->>'portador', '');

        v_valor := CASE
            WHEN COALESCE(v_item->>'valor', '') LIKE '%,%' THEN
                REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(v_item->>'valor', '0'), 'R$', ''), '.', ''), ',', '.'), ' ', '')::NUMERIC(14,2)
            ELSE
                REPLACE(REPLACE(COALESCE(v_item->>'valor', '0'), 'R$', ''), ' ', '')::NUMERIC(14,2)
        END;

        v_parcela_texto := NULLIF(v_item->>'parcela', '');

        v_contabil_id := COALESCE(
                NULLIF(v_item->>'conta_contabil_id', '')::BIGINT,
                NULLIF(v_item->>'contabil_id', '')::BIGINT
            );

        IF v_parcela_texto IS NULL OR v_parcela_texto = '-' THEN
            v_parcela_texto := '1 de 1';
            v_parcela_atual := 1;
            v_parcela_total := 1;
        ELSE
            v_parcela_atual := NULL;
            v_parcela_total := NULL;

            IF v_parcela_texto ~ '^[0-9]+[ ]*de[ ]*[0-9]+$' THEN
                v_parcela_atual := split_part(v_parcela_texto, ' de ', 1)::INTEGER;
                v_parcela_total := split_part(v_parcela_texto, ' de ', 2)::INTEGER;
            ELSIF v_parcela_texto ~ '^[0-9]+/[0-9]+$' THEN
                v_parcela_atual := split_part(v_parcela_texto, '/', 1)::INTEGER;
                v_parcela_total := split_part(v_parcela_texto, '/', 2)::INTEGER;
            END IF;
        END IF;

        v_tipo_linha :=
    CASE
        WHEN v_valor < 0 AND UPPER(v_estabelecimento) LIKE '%PAGAMENTO%' THEN 'pagamento'
        WHEN v_valor < 0 THEN 'credito'
        WHEN COALESCE(v_parcela_atual, 1) > 1 THEN 'parcela'
        ELSE 'compra'
    END;

        v_hash := md5(
            p_empresa_id::TEXT || '|' ||
            p_cartao_id::TEXT || '|' ||
            COALESCE(v_data::TEXT, '') || '|' ||
            COALESCE(UPPER(TRIM(v_estabelecimento)), '') || '|' ||
            COALESCE(UPPER(TRIM(v_portador)), '') || '|' ||
            COALESCE(v_valor::TEXT, '') || '|' ||
            COALESCE(v_parcela_texto, '') || '|' ||
            COALESCE(v_item->>'linha', '')
        );

        INSERT INTO public.conciliacao_cartoes (
            empresa_id,
            cartao_id,
            importacao_id,
            data_compra,
            estabelecimento,
            portador,
            valor,
            parcela_texto,
            parcela_atual,
            parcela_total,
            tipo_linha,
            status_conciliacao,
            hash_registro,
            dados_originais,
            contabil_id
        )
        VALUES (
            p_empresa_id,
            p_cartao_id,
            v_importacao_id,
            v_data,
            v_estabelecimento,
            v_portador,
            v_valor,
            v_parcela_texto,
            v_parcela_atual,
            v_parcela_total,
            v_tipo_linha,
            'pendente',
            v_hash,
            v_item,
            v_contabil_id
        )
        ON CONFLICT (empresa_id, cartao_id, hash_registro)
        WHERE hash_registro IS NOT NULL
        DO NOTHING;

        v_total_linhas := v_total_linhas + 1;

        IF v_valor >= 0 THEN
            v_total_compras := v_total_compras + v_valor;
        ELSE
            v_total_creditos := v_total_creditos + ABS(v_valor);
        END IF;
    END LOOP;

    UPDATE public.cartao_importacoes
    SET
        total_linhas = v_total_linhas,
        total_compras = v_total_compras,
        total_creditos = v_total_creditos,
        total_liquido = v_total_compras - v_total_creditos
    WHERE id = v_importacao_id;

    RETURN jsonb_build_object(
        'ok', true,
        'importacao_id', v_importacao_id,
        'tipo_importacao', v_tipo_importacao,
        'data_corte', CASE WHEN v_tipo_importacao = 'implantacao' THEN p_mes_referencia ELSE NULL END,
        'total_linhas', v_total_linhas,
        'total_compras', v_total_compras,
        'total_creditos', v_total_creditos,
        'total_liquido', v_total_compras - v_total_creditos
    );
END;
$$;