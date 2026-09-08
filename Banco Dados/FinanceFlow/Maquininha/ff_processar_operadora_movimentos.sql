CREATE OR REPLACE FUNCTION public.ff_processar_operadora_movimentos(
    p_empresa_id BIGINT,
    p_itens JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_item JSONB;
    v_mov_id BIGINT;

    r RECORD;
    t RECORD;

    v_forma TEXT;

    v_modelo_venda TEXT;
    v_modelo_taxa TEXT;
    v_modelo_trans TEXT;

    v_debito_id BIGINT;
    v_credito_id BIGINT;

    v_valor_bruto NUMERIC(14,2);
    v_valor_taxa NUMERIC(14,2);
    v_valor_liquido NUMERIC(14,2);

    v_data_venda DATE;
    v_data_transitoria DATE;

    v_historico TEXT;

    v_processados INTEGER := 0;
    v_erros INTEGER := 0;
    v_ignorados INTEGER := 0;

    v_retorno_itens JSONB := '[]'::JSONB;
BEGIN

    ------------------------------------------------------------------
    -- VALIDAÇÕES
    ------------------------------------------------------------------

    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'Empresa não informada.';
    END IF;

    IF p_itens IS NULL
       OR JSONB_TYPEOF(p_itens) <> 'array'
       OR JSONB_ARRAY_LENGTH(p_itens) = 0
    THEN
        RAISE EXCEPTION 'Nenhum movimento selecionado.';
    END IF;


    ------------------------------------------------------------------
    -- PROCESSA CADA MOVIMENTO
    ------------------------------------------------------------------

    FOR v_item IN
        SELECT value
        FROM JSONB_ARRAY_ELEMENTS(p_itens)
    LOOP

        ----------------------------------------------------------------
        -- ACEITA:
        -- { "operadora_movimento_id": 123 }
        -- ou { "id": 123 }
        ----------------------------------------------------------------

        v_mov_id :=
            COALESCE(
                NULLIF(v_item->>'operadora_movimento_id', '')::BIGINT,
                NULLIF(v_item->>'id', '')::BIGINT
            );

        IF v_mov_id IS NULL THEN
            v_erros := v_erros + 1;

            v_retorno_itens :=
                v_retorno_itens ||
                JSONB_BUILD_ARRAY(
                    JSONB_BUILD_OBJECT(
                        'ok', FALSE,
                        'id', NULL,
                        'mensagem', 'ID do movimento não informado.'
                    )
                );

            CONTINUE;
        END IF;


        ----------------------------------------------------------------
        -- CADA MOVIMENTO RODA EM BLOCO PRÓPRIO
        --
        -- Se uma das 3 partidas falhar, as anteriores daquela mesma
        -- operação são revertidas automaticamente.
        ----------------------------------------------------------------

        BEGIN

            ------------------------------------------------------------
            -- BUSCA MOVIMENTO
            ------------------------------------------------------------

            SELECT *
            INTO r
            FROM public.operadora_movimentos
            WHERE id = v_mov_id
              AND empresa_id = p_empresa_id
            FOR UPDATE;


            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'Movimento % não encontrado.',
                    v_mov_id;
            END IF;


            ------------------------------------------------------------
            -- JÁ PROCESSADO
            ------------------------------------------------------------

            IF COALESCE(r.status_processamento, 'ABERTO')
                = 'PROCESSADO'
            THEN

                v_ignorados := v_ignorados + 1;

                v_retorno_itens :=
                    v_retorno_itens ||
                    JSONB_BUILD_ARRAY(
                        JSONB_BUILD_OBJECT(
                            'ok', TRUE,
                            'id', v_mov_id,
                            'status', 'IGNORADO',
                            'mensagem', 'Movimento já processado.'
                        )
                    );

                CONTINUE;

            END IF;


            ------------------------------------------------------------
            -- NÃO PROCESSAR TRANSAÇÕES NEGADAS/CANCELADAS
            ------------------------------------------------------------

            IF UPPER(COALESCE(r.status, '')) LIKE '%NEGAD%'
               OR UPPER(COALESCE(r.status, '')) LIKE '%CANCEL%'
               OR UPPER(COALESCE(r.status, '')) LIKE '%EXPIR%'
               OR UPPER(COALESCE(r.status, '')) LIKE '%NAO PAGO%'
               OR UPPER(COALESCE(r.status, '')) LIKE '%NÃO PAGO%'
            THEN
                RAISE EXCEPTION
                    'Movimento não processável. Status Getnet: %',
                    COALESCE(r.status, '-');
            END IF;


            ------------------------------------------------------------
            -- NORMALIZA FORMA
            ------------------------------------------------------------

            v_forma :=
                LOWER(
                    TRIM(
                        COALESCE(r.forma_pagamento, '')
                    )
                );


            ------------------------------------------------------------
            -- DEFINE OS 3 MODELOS
            ------------------------------------------------------------

            IF v_forma = 'cartao_credito' THEN

                v_modelo_venda := 'RECEBER_CARTAO';
                v_modelo_taxa  := 'TAXA_RECEBIVEL_CREDITO';
                v_modelo_trans := 'REC_CRED_TRANS';

            ELSIF v_forma = 'cartao_debito' THEN

                v_modelo_venda := 'CRIA_RECEBER_RECEITA';
                v_modelo_taxa  := 'TAXA_RECEBIVEL_DEBITO';
                v_modelo_trans := 'REC_DEB_TRANS';

            ELSIF v_forma = 'pix' THEN

                 v_modelo_venda := 'RECEBER_PIX';
                 v_modelo_taxa  := 'TAXA_RECEBIVEL_PIX';
                  v_modelo_trans := 'REC_PIX_TRANS';

      
 
            ELSE

                RAISE EXCEPTION
                    'Forma de pagamento não tratada: %',
                    COALESCE(r.forma_pagamento, '-');

            END IF;


            ------------------------------------------------------------
            -- VALORES
            ------------------------------------------------------------

            v_valor_bruto :=
                ABS(COALESCE(r.valor_bruto, 0));

            v_valor_taxa :=
                ABS(COALESCE(r.valor_taxa, 0));

            v_valor_liquido :=
                ABS(COALESCE(r.valor_liquido, 0));


            IF v_valor_bruto <= 0 THEN
                RAISE EXCEPTION
                    'Valor bruto inválido para movimento %.',
                    v_mov_id;
            END IF;

            IF v_valor_liquido <= 0 THEN
                RAISE EXCEPTION
                    'Valor líquido inválido para movimento %.',
                    v_mov_id;
            END IF;


            ------------------------------------------------------------
            -- DATAS
            ------------------------------------------------------------

            v_data_venda :=
                r.data_movimento::DATE;

            v_data_transitoria :=
                COALESCE(
                    r.data_prevista_pagamento,
                    r.data_movimento::DATE
                );


            IF v_data_venda IS NULL THEN
                RAISE EXCEPTION
                    'Data da venda não identificada.';
            END IF;


            --------------------------------------------------------
            -- 1. VENDA
            --
            -- CRÉDITO:
            -- D 1.1.3
            -- C RECEITA
            --
            -- DÉBITO:
            -- D 1.1.2
            -- C RECEITA
            --------------------------------------------------------

            SELECT *
            INTO t
            FROM contab.template_eventos_contabeis
            WHERE codigo_evento = v_modelo_venda
              AND ativo = TRUE
            ORDER BY id DESC
            LIMIT 1;


            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'Modelo contábil % não encontrado.',
                    v_modelo_venda;
            END IF;


            SELECT id
            INTO v_debito_id
            FROM contab.contas
            WHERE empresa_id = p_empresa_id
              AND codigo = t.conta_debito_codigo
            LIMIT 1;


            SELECT id
            INTO v_credito_id
            FROM contab.contas
            WHERE empresa_id = p_empresa_id
              AND codigo = t.conta_credito_codigo
            LIMIT 1;


            IF v_debito_id IS NULL OR v_credito_id IS NULL THEN
                RAISE EXCEPTION
                    'Contas do modelo % não encontradas.',
                    v_modelo_venda;
            END IF;


             v_historico :=
                    'Venda Getnet - ' ||
                    CASE
                        WHEN v_forma = 'cartao_credito' THEN 'Cartão de crédito'
                        WHEN v_forma = 'cartao_debito'  THEN 'Cartão de débito'
                        WHEN v_forma = 'pix'            THEN 'PIX'
                        ELSE COALESCE(r.forma_pagamento, '')
                    END ||
                    CASE
                        WHEN NULLIF(TRIM(r.bandeira), '') IS NOT NULL
                            THEN ' - ' || UPPER(TRIM(r.bandeira))
                        ELSE ''
                    END ||
                    CASE
                        WHEN r.autorizacao IS NOT NULL
                            THEN ' - AUT ' || r.autorizacao
                        ELSE ''
                    END;


            PERFORM *
            FROM contab.ff_lancamento_partida_dobrada(
                p_empresa_id,
                v_debito_id,
                v_credito_id,
                v_valor_bruto,
                v_historico,
                v_data_venda,
                FALSE,
                v_data_venda
            );


            -----------------------------------------------------------------
            -- 2. TAXA
            --
            -- SOMENTE SE HOUVER TAXA
            --
            -- D DESPESA TAXA
            -- C 1.1.2 / 1.1.3
            
            -----------------------------------------------------------------

            IF v_valor_taxa > 0 THEN

                SELECT *
                INTO t
                FROM contab.template_eventos_contabeis
                WHERE codigo_evento = v_modelo_taxa
                  AND ativo = TRUE
                ORDER BY id DESC
                LIMIT 1;


                IF NOT FOUND THEN
                    RAISE EXCEPTION
                        'Modelo contábil % não encontrado.',
                        v_modelo_taxa;
                END IF;


                SELECT id
                INTO v_debito_id
                FROM contab.contas
                WHERE empresa_id = p_empresa_id
                  AND codigo = t.conta_debito_codigo
                LIMIT 1;


                SELECT id
                INTO v_credito_id
                FROM contab.contas
                WHERE empresa_id = p_empresa_id
                  AND codigo = t.conta_credito_codigo
                LIMIT 1;


                IF v_debito_id IS NULL
                   OR v_credito_id IS NULL
                THEN
                    RAISE EXCEPTION
                        'Contas do modelo % não encontradas.',
                        v_modelo_taxa;
                END IF;


               v_historico :=
                        'Taxa Getnet - ' ||
                        CASE
                            WHEN v_forma = 'cartao_credito' THEN 'Cartão de crédito'
                            WHEN v_forma = 'cartao_debito'  THEN 'Cartão de débito'
                            WHEN v_forma = 'pix'            THEN 'PIX'
                            ELSE COALESCE(r.forma_pagamento, '')
                        END ||
                        CASE
                            WHEN NULLIF(TRIM(r.bandeira), '') IS NOT NULL
                                THEN ' - ' || UPPER(TRIM(r.bandeira))
                            ELSE ''
                        END ||
                        CASE
                            WHEN r.autorizacao IS NOT NULL
                                THEN ' - AUT ' || r.autorizacao
                            ELSE ''
                        END;


                PERFORM *
                FROM contab.ff_lancamento_partida_dobrada(
                    p_empresa_id,
                    v_debito_id,
                    v_credito_id,
                    v_valor_taxa,
                    v_historico,
                    v_data_venda,
                    FALSE,
                    v_data_venda
                );

            END IF;


            
            -----------------------------------------------------------------
            -- 3. TRANSITÓRIA
            --
            -- D 1.1.4 Valores em Trânsito
            -- C 1.1.2 / 1.1.3
            --
            -- VALOR = LÍQUIDO INFORMADO PELA GETNET
           
            -----------------------------------------------------------------

            SELECT *
            INTO t
            FROM contab.template_eventos_contabeis
            WHERE codigo_evento = v_modelo_trans
              AND ativo = TRUE
            ORDER BY id DESC
            LIMIT 1;


            IF NOT FOUND THEN
                RAISE EXCEPTION
                    'Modelo contábil % não encontrado.',
                    v_modelo_trans;
            END IF;


            SELECT id
            INTO v_debito_id
            FROM contab.contas
            WHERE empresa_id = p_empresa_id
              AND codigo = t.conta_debito_codigo
            LIMIT 1;


            SELECT id
            INTO v_credito_id
            FROM contab.contas
            WHERE empresa_id = p_empresa_id
              AND codigo = t.conta_credito_codigo
            LIMIT 1;


            IF v_debito_id IS NULL
               OR v_credito_id IS NULL
            THEN
                RAISE EXCEPTION
                    'Contas do modelo % não encontradas.',
                    v_modelo_trans;
            END IF;


           /* v_historico :=
                'Getnet - valor em trânsito - ' ||
                CASE
                    WHEN v_forma = 'cartao_credito'
                        THEN 'Cartão de crédito'
                    ELSE
                        'Cartão de débito'
                END;*/


           v_historico :=
                        'Getnet - valor em trânsito - ' ||
                        CASE
                            WHEN v_forma = 'cartao_credito' THEN 'Cartão de crédito'
                            WHEN v_forma = 'cartao_debito'  THEN 'Cartão de débito'
                            WHEN v_forma = 'pix'            THEN 'PIX'
                            ELSE COALESCE(r.forma_pagamento, '')
                        END ||
                        CASE
                            WHEN NULLIF(TRIM(r.bandeira), '') IS NOT NULL
                                THEN ' - ' || UPPER(TRIM(r.bandeira))
                            ELSE ''
                        END;



            PERFORM *
            FROM contab.ff_lancamento_partida_dobrada(
                p_empresa_id,
                v_debito_id,
                v_credito_id,
                v_valor_liquido,
                v_historico,
                v_data_transitoria,
                FALSE,
                v_data_transitoria
            );


            
            -----------------------------------------------------------------
            -- PROCESSADO 
            -----------------------------------------------------------------

            UPDATE public.operadora_movimentos
            SET
                status_processamento = 'PROCESSADO',
                processado_em = NOW(),
                processamento_erro = NULL
            WHERE id = v_mov_id
              AND empresa_id = p_empresa_id;


            v_processados :=
                v_processados + 1;


            v_retorno_itens :=
                v_retorno_itens ||
                JSONB_BUILD_ARRAY(
                    JSONB_BUILD_OBJECT(
                        'ok', TRUE,
                        'id', v_mov_id,
                        'status', 'PROCESSADO',
                        'forma', v_forma,
                        'valor_bruto', v_valor_bruto,
                        'valor_taxa', v_valor_taxa,
                        'valor_liquido', v_valor_liquido,
                        'lancamentos',
                            CASE
                                WHEN v_valor_taxa > 0
                                    THEN 3
                                ELSE 2
                            END
                    )
                );


        EXCEPTION
            WHEN OTHERS THEN

                --------------------------------------------------------
                -- O bloco dessa operação foi revertido.
                -- Guarda erro e mantém ABERTO.
                --------------------------------------------------------

                UPDATE public.operadora_movimentos
                SET
                    status_processamento = 'ABERTO',
                    processamento_erro = SQLERRM
                WHERE id = v_mov_id
                  AND empresa_id = p_empresa_id;


                v_erros :=
                    v_erros + 1;


                v_retorno_itens :=
                    v_retorno_itens ||
                    JSONB_BUILD_ARRAY(
                        JSONB_BUILD_OBJECT(
                            'ok', FALSE,
                            'id', v_mov_id,
                            'status', 'ERRO',
                            'mensagem', SQLERRM
                        )
                    );

        END;

    END LOOP;


    ------------------------------------------------------------------
    -- RETORNO
    ------------------------------------------------------------------

    RETURN JSONB_BUILD_OBJECT(
        'ok', v_erros = 0,

        'empresa_id', p_empresa_id,

        'resumo',
        JSONB_BUILD_OBJECT(
            'selecionados',
                JSONB_ARRAY_LENGTH(p_itens),

            'processados',
                v_processados,

            'ignorados',
                v_ignorados,

            'erros',
                v_erros
        ),

        'itens',
        v_retorno_itens,

        'mensagem',
        CASE
            WHEN v_erros = 0 THEN
                'Movimentos processados com sucesso.'
            ELSE
                'Processamento concluído com ocorrências.'
        END
    );

END;
$$;