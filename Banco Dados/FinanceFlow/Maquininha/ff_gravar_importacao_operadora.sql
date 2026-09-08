CREATE OR REPLACE FUNCTION public.ff_gravar_importacao_operadora(
    p_empresa_id BIGINT,
    p_conta_id BIGINT,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_importacao_id BIGINT;

    v_diagnostico JSONB;
    v_movimentos JSONB;

    v_item JSONB;

    v_qtd_recebidos INTEGER := 0;
    v_qtd_gravados INTEGER := 0;
    v_qtd_duplicados INTEGER := 0;

    v_id_movimento BIGINT;

    v_operadora TEXT;
    v_data_inicio DATE;
    v_data_fim DATE;

BEGIN

    ----------------------------------------------------------------
    -- VALIDAÇÃO BÁSICA
    ----------------------------------------------------------------

    IF p_payload IS NULL THEN
        RAISE EXCEPTION 'Payload da operadora não informado.';
    END IF;

    IF COALESCE((p_payload->>'ok')::BOOLEAN, FALSE) = FALSE THEN
        RAISE EXCEPTION
            'Payload Getnet inválido: %',
            COALESCE(
                p_payload->>'mensagem',
                'Arquivo não validado'
            );
    END IF;


    ----------------------------------------------------------------
    -- BLOCOS DO JSON
    ----------------------------------------------------------------

    v_diagnostico := COALESCE(
        p_payload->'diagnostico',
        '{}'::JSONB
    );

    v_movimentos := COALESCE(
        p_payload->'movimentos',
        '[]'::JSONB
    );


    ----------------------------------------------------------------
    -- DADOS PRINCIPAIS
    ----------------------------------------------------------------

    v_operadora := UPPER(
        COALESCE(
            NULLIF(v_diagnostico->>'operadora', ''),
            'GETNET'
        )
    );

    v_data_inicio :=
        NULLIF(
            v_diagnostico->>'data_inicio',
            ''
        )::DATE;

    v_data_fim :=
        NULLIF(
            v_diagnostico->>'data_fim',
            ''
        )::DATE;


    IF v_data_inicio IS NULL OR v_data_fim IS NULL THEN
        RAISE EXCEPTION
            'Período da importação não identificado.';
    END IF;


    ----------------------------------------------------------------
    -- QUANTIDADE RECEBIDA
    ----------------------------------------------------------------

    v_qtd_recebidos :=
        JSONB_ARRAY_LENGTH(v_movimentos);


    ----------------------------------------------------------------
    -- CABEÇALHO DA IMPORTAÇÃO
    ----------------------------------------------------------------

    INSERT INTO public.operadora_importacoes
    (
        empresa_id,
        conta_financeira_id,

        operadora,
        tipo_arquivo,

        data_inicio,
        data_fim,

        arquivo_nome,
        arquivo_hash,

        qtd_linhas,
        qtd_cartoes,
        qtd_pix,
        qtd_outros,

        total_bruto,
        total_taxas,
        total_liquido,

        total_credito,
        total_debito,
        total_pix,

        diagnostico,
        status
    )
    VALUES
    (
        p_empresa_id,
        p_conta_id,

        v_operadora,
        COALESCE(
            NULLIF(p_payload->>'origem', ''),
            'GETNET_TXT'
        ),

        v_data_inicio,
        v_data_fim,

        NULL,
        NULL,

        COALESCE(
            (v_diagnostico->>'quantidade_movimentos')::INTEGER,
            0
        ),

        COALESCE(
            (v_diagnostico->>'quantidade_cartoes')::INTEGER,
            0
        ),

        COALESCE(
            (v_diagnostico->>'quantidade_pix')::INTEGER,
            0
        ),

        0,

        COALESCE(
            (v_diagnostico->>'total_bruto')::NUMERIC,
            0
        ),

        COALESCE(
            (v_diagnostico->>'total_taxas')::NUMERIC,
            0
        ),

        COALESCE(
            (v_diagnostico->>'total_liquido')::NUMERIC,
            0
        ),

        COALESCE(
            (v_diagnostico->>'total_credito_bruto')::NUMERIC,
            0
        ),

        COALESCE(
            (v_diagnostico->>'total_debito_bruto')::NUMERIC,
            0
        ),

        COALESCE(
            (v_diagnostico->>'total_pix_bruto')::NUMERIC,
            0
        ),

        v_diagnostico,

        'IMPORTADO'
    )
    RETURNING id
    INTO v_importacao_id;


    ----------------------------------------------------------------
    -- MOVIMENTOS
    ----------------------------------------------------------------

    FOR v_item IN
        SELECT value
        FROM JSONB_ARRAY_ELEMENTS(v_movimentos)
    LOOP

        v_id_movimento := NULL;

         INSERT INTO public.operadora_movimentos
(
    importacao_id,
    empresa_id,

    tipo_movimento,

    data_movimento,
    data_prevista_pagamento,

    bandeira,
    modalidade,
    forma_pagamento,
    status,

    parcelas,

    autorizacao,
    comprovante_venda,
    transacao_origem,

    terminal,

    valor_bruto,
    valor_taxa,
    valor_liquido,

    chave_registro,

    conciliado,

    dados_origem,
    chave_match_operadora,

    status_processamento,
    processado_em,
    processamento_erro
)
VALUES
(
    v_importacao_id,
    p_empresa_id,

    NULLIF(
        v_item->>'tipo_movimento',
        ''
    ),

    NULLIF(
        v_item->>'data_hora_movimento',
        ''
    )::TIMESTAMP,

    NULLIF(
        v_item->>'data_prevista_pagamento',
        ''
    )::DATE,

    NULLIF(
        v_item->>'bandeira',
        ''
    ),

    NULLIF(
        v_item->>'modalidade',
        ''
    ),

    NULLIF(
        v_item->>'forma_pagamento',
        ''
    ),

    NULLIF(
        v_item->>'status',
        ''
    ),

    COALESCE(
        NULLIF(
            v_item->>'parcelas',
            ''
        )::INTEGER,
        1
    ),

    NULLIF(
        v_item->>'autorizacao',
        ''
    ),

    NULLIF(
        v_item->>'comprovante_venda',
        ''
    ),

    NULLIF(
        v_item->>'transacao_origem',
        ''
    ),

    NULLIF(
        v_item->>'terminal',
        ''
    ),

    COALESCE(
        NULLIF(
            v_item->>'valor_bruto',
            ''
        )::NUMERIC,
        0
    ),

    COALESCE(
        NULLIF(
            v_item->>'valor_taxa',
            ''
        )::NUMERIC,
        0
    ),

    COALESCE(
        NULLIF(
            v_item->>'valor_liquido',
            ''
        )::NUMERIC,
        0
    ),

    v_item->>'chave_registro',

    FALSE,

    COALESCE(
        v_item->'dados_origem',
        v_item
    ),

    CASE
        WHEN NULLIF(v_item->>'data_hora_movimento', '') IS NOT NULL
         AND NULLIF(v_item->>'valor_bruto', '') IS NOT NULL
         AND NULLIF(v_item->>'forma_pagamento', '') IS NOT NULL
        THEN
            (NULLIF(
                v_item->>'data_hora_movimento',
                ''
            )::TIMESTAMP)::DATE::TEXT
            || '|'
            || TRIM(
                TO_CHAR(
                    ABS(
                        (v_item->>'valor_bruto')::NUMERIC
                    ),
                    'FM999999999990.00'
                )
            )
            || '|'
            || LOWER(
                TRIM(
                    v_item->>'forma_pagamento'
                )
            )
        ELSE NULL
    END,

    'ABERTO',
    NULL,
    NULL
)
ON CONFLICT (
    empresa_id,
    chave_registro
)
DO NOTHING
RETURNING id
INTO v_id_movimento;

        ----------------------------------------------------------------
        -- CONTAGEM
        ----------------------------------------------------------------

        IF v_id_movimento IS NULL THEN

            v_qtd_duplicados :=
                v_qtd_duplicados + 1;

        ELSE

            v_qtd_gravados :=
                v_qtd_gravados + 1;

        END IF;

    END LOOP;


    ----------------------------------------------------------------
    -- RETORNO
    ----------------------------------------------------------------

    RETURN JSONB_BUILD_OBJECT(

        'ok', TRUE,

        'importacao_id',
        v_importacao_id,

        'empresa_id',
        p_empresa_id,

        'conta_id',
        p_conta_id,

        'operadora',
        v_operadora,

        'data_inicio',
        v_data_inicio,

        'data_fim',
        v_data_fim,

        'movimentos_recebidos',
        v_qtd_recebidos,

        'movimentos_gravados',
        v_qtd_gravados,

        'movimentos_duplicados',
        v_qtd_duplicados,

        'mensagem',
        'Importação da operadora gravada com sucesso.'
    );

END;
$$;