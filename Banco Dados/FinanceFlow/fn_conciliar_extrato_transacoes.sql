  CREATE OR REPLACE FUNCTION public.fn_conciliar_extrato_transacoes(
    p_empresa_id bigint,
    p_conta_financeira_id bigint,
    p_lote_conciliacao_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
    x record;

    v_encontrados integer := 0;
    v_pendentes integer := 0;

    v_valor_encontrado numeric(14,2) := 0;
    v_valor_pendente numeric(14,2) := 0;

    v_data_ini date;
    v_data_fim date;

    v_detalhes jsonb := '[]'::jsonb;
BEGIN
    ------------------------------------------------------------------
    -- 1) VALIDA O LOTE
    ------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM public.lote_conciliacao l
        WHERE l.id = p_lote_conciliacao_id
          AND l.empresa_id = p_empresa_id
          AND l.conta_financeira_id = p_conta_financeira_id
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message',
            'Lote de conciliação não encontrado para a empresa e conta informadas'
        );
    END IF;

    ------------------------------------------------------------------
    -- 2) PERÍODO DO LOTE
    ------------------------------------------------------------------
    SELECT
        MIN(c.data_mov),
        MAX(c.data_mov)
    INTO
        v_data_ini,
        v_data_fim
    FROM public.conciliacao_financeira c
    WHERE c.empresa_id = p_empresa_id
      AND c.conta_financeira_id = p_conta_financeira_id
      AND c.lote_conciliacao_id = p_lote_conciliacao_id;

    ------------------------------------------------------------------
    -- 3) LIMPA RESULTADOS ANTERIORES DESTA COMPARAÇÃO
    --
    -- Não mexe nos registros rejeitados pela própria importação:
    -- duplicidade de arquivo, mesma titularidade etc.
    ------------------------------------------------------------------
    UPDATE public.conciliacao_financeira c
       SET transacao_id = NULL,
           pagar_id = NULL,
           receber_id = NULL,
           fatura_id = NULL,
           match_score = NULL,
           match_criterio = NULL,
           importar = true,
           status_conciliacao = 'pendente',
           mensagem_conciliacao =
               'Aguardando comparação com o financeiro'
     WHERE c.empresa_id = p_empresa_id
       AND c.conta_financeira_id = p_conta_financeira_id
       AND c.lote_conciliacao_id = p_lote_conciliacao_id
       AND lower(COALESCE(c.status_conciliacao, 'pendente'))
           NOT IN ('rejeitado', 'rejeitada');

    ------------------------------------------------------------------
    -- 4) PERCORRE AS LINHAS DO EXTRATO
    ------------------------------------------------------------------
    FOR r IN
        SELECT c.*
        FROM public.conciliacao_financeira c
        WHERE c.empresa_id = p_empresa_id
          AND c.conta_financeira_id = p_conta_financeira_id
          AND c.lote_conciliacao_id = p_lote_conciliacao_id
          AND lower(COALESCE(c.status_conciliacao, 'pendente'))
              NOT IN ('rejeitado', 'rejeitada')
        ORDER BY
            c.data_mov,
            c.tipo,
            abs(c.valor),
            c.id
    LOOP
        x := NULL;

        ------------------------------------------------------------------
        -- 5) PROCURA UMA TRANSAÇÃO COMPATÍVEL AINDA NÃO UTILIZADA
        --
        -- Prioridade:
        -- 1. descrição exatamente igual;
        -- 2. menor diferença de data;
        -- 3. menor ID disponível.
        --
        -- Mesmo que existam duas transações iguais, pega uma por vez.
        ------------------------------------------------------------------
        SELECT
            t.id AS transacao_id,
            t.data_movimento,
            t.valor,
            t.descricao,
            t.origem,
            t.pagar_id,
            t.receber_id,
            t.fatura_id,
            t.evento_codigo,
            t.origem_id,
            t.tipo_evento,
            t.importacao_id,

            abs(t.data_movimento - r.data_mov) AS diferenca_dias,

            CASE
                WHEN
                    unaccent(lower(trim(regexp_replace(
                        COALESCE(t.descricao, ''),
                        '\s+',
                        ' ',
                        'g'
                    ))))
                    =
                    unaccent(lower(trim(regexp_replace(
                        COALESCE(r.historico, ''),
                        '\s+',
                        ' ',
                        'g'
                    ))))
                THEN true
                ELSE false
            END AS descricao_exata

        INTO x
        FROM public.transacoes t
        WHERE t.empresa_id = r.empresa_id

          -- conciliacao_financeira.conta_financeira_id
          -- corresponde a transacoes.conta_id
          AND t.conta_id = r.conta_financeira_id

          AND t.tipo = r.tipo

          -- Extrato pode guardar saída negativa.
          -- Transações guarda o valor positivo.
          AND abs(t.valor - abs(r.valor)) <= 0.01 
        AND abs(t.data_movimento - r.data_mov) = 0

          -- A mesma transação não pode ser vinculada a duas linhas.
          AND NOT EXISTS (
              SELECT 1
              FROM public.conciliacao_financeira ja
              WHERE ja.empresa_id = r.empresa_id
                AND ja.transacao_id = t.id
                AND ja.id <> r.id
                -- Impede usar a mesma transação duas vezes somente
                -- dentro do lote atual. Vínculo em lote anterior deve
                -- ser encontrado para marcar a nova linha como repetida.
                AND ja.lote_conciliacao_id = r.lote_conciliacao_id
          )

        ORDER BY
            ----------------------------------------------------------------
            -- Primeiro tenta casar descrição idêntica.
            ----------------------------------------------------------------
            CASE
                WHEN
                    unaccent(lower(trim(regexp_replace(
                        COALESCE(t.descricao, ''),
                        '\s+',
                        ' ',
                        'g'
                    ))))
                    =
                    unaccent(lower(trim(regexp_replace(
                        COALESCE(r.historico, ''),
                        '\s+',
                        ' ',
                        'g'
                    ))))
                THEN 0
                ELSE 1
            END,

            ----------------------------------------------------------------
            -- Depois prioriza mesma data.
            ----------------------------------------------------------------
            abs(t.data_movimento - r.data_mov),

            ----------------------------------------------------------------
            -- Se ainda empatar, consome pelo ID.
            ----------------------------------------------------------------
            t.id
        LIMIT 1;

        ------------------------------------------------------------------
        -- 6) NÃO ENCONTROU TRANSAÇÃO
        ------------------------------------------------------------------
        IF x.transacao_id IS NULL THEN

            UPDATE public.conciliacao_financeira
               SET transacao_id = NULL,
                   pagar_id = NULL,
                   receber_id = NULL,
                   fatura_id = NULL,
                   importar = true,
                   status_conciliacao = 'pendente',
                   match_score = 0,

                   match_criterio = concat(
                       'transacao_nao_encontrada',
                       '; conta=', r.conta_financeira_id,
                       '; tipo=', r.tipo,
                       '; valor=', abs(r.valor),
                       '; data=', r.data_mov
                   ),

                   mensagem_conciliacao =
                       'Movimento não encontrado no financeiro'

             WHERE id = r.id
               AND empresa_id = r.empresa_id;

            v_pendentes := v_pendentes + 1;

            v_valor_pendente :=
                v_valor_pendente + abs(r.valor);

            v_detalhes :=
                v_detalhes ||
                jsonb_build_array(
                    jsonb_build_object(
                        'conciliacao_financeira_id', r.id,
                        'transacao_id', NULL,
                        'resultado', 'pendente',
                        'data_extrato', r.data_mov,
                        'tipo', r.tipo,
                        'valor_extrato', abs(r.valor),
                        'mensagem',
                            'Movimento não encontrado no financeiro'
                    )
                );

            CONTINUE;
        END IF;

        ------------------------------------------------------------------
        -- 7) ENCONTROU TRANSAÇÃO EXISTENTE
        ------------------------------------------------------------------
        UPDATE public.conciliacao_financeira
           SET transacao_id = x.transacao_id,

               -- Preserva os vínculos já existentes na transação.
               pagar_id = x.pagar_id,
               receber_id = x.receber_id,
               fatura_id = x.fatura_id,

               -- Não deve gerar outra transação.
               importar = false,

               -- Mantendo o padrão que você definiu.
               status_conciliacao = 'rejeitado',

               match_score =
                   CASE
                       WHEN x.descricao_exata
                            AND x.diferenca_dias = 0
                           THEN 100

                       WHEN x.diferenca_dias = 0
                           THEN 95

                       WHEN x.diferenca_dias = 1
                           THEN 90

                       WHEN x.diferenca_dias = 2
                           THEN 80

                       ELSE 70
                   END,

               match_criterio = concat(
                   'transacao_encontrada',
                   '; transacao_id=', x.transacao_id,
                   '; conta=', r.conta_financeira_id,
                   '; tipo=', r.tipo,
                   '; valor_extrato=', abs(r.valor),
                   '; valor_financeiro=', x.valor,
                   '; data_extrato=', r.data_mov,
                   '; data_financeiro=', x.data_movimento,
                   '; diferenca_dias=', x.diferenca_dias,
                   '; descricao_exata=', x.descricao_exata,
                   '; origem=', COALESCE(x.origem, ''),
                   '; pagar_id=', COALESCE(x.pagar_id::text, ''),
                   '; receber_id=', COALESCE(x.receber_id::text, ''),
                   '; fatura_id=', COALESCE(x.fatura_id::text, '')
               ),

               mensagem_conciliacao =
                   'Movimento já encontrado no financeiro'

         WHERE id = r.id
           AND empresa_id = r.empresa_id;

        v_encontrados := v_encontrados + 1;

        v_valor_encontrado :=
            v_valor_encontrado + abs(r.valor);

        v_detalhes :=
            v_detalhes ||
            jsonb_build_array(
                jsonb_build_object(
                    'conciliacao_financeira_id', r.id,
                    'transacao_id', x.transacao_id,
                    'resultado', 'encontrado',
                    'data_extrato', r.data_mov,
                    'data_financeiro', x.data_movimento,
                    'diferenca_dias', x.diferenca_dias,
                    'descricao_exata', x.descricao_exata,
                    'tipo', r.tipo,
                    'valor_extrato', abs(r.valor),
                    'valor_financeiro', x.valor,
                    'descricao_extrato', r.historico,
                    'descricao_financeiro', x.descricao,
                    'origem_transacao', x.origem,
                    'pagar_id', x.pagar_id,
                    'receber_id', x.receber_id,
                    'fatura_id', x.fatura_id,
                    'evento_codigo', x.evento_codigo,
                    'origem_id', x.origem_id,
                    'tipo_evento', x.tipo_evento,
                    'importacao_id_transacao', x.importacao_id,
                    'mensagem',
                        'Movimento já encontrado no financeiro'
                )
            );

    END LOOP;

    ------------------------------------------------------------------
    -- 8) RETORNA O RELATÓRIO
    ------------------------------------------------------------------
    RETURN jsonb_build_object(
        'ok', true,
        'empresa_id', p_empresa_id,
        'conta_financeira_id', p_conta_financeira_id,
        'lote_conciliacao_id', p_lote_conciliacao_id,

        'periodo', jsonb_build_object(
            'data_ini', v_data_ini,
            'data_fim', v_data_fim
        ),

        'resumo', jsonb_build_object(
            'encontrados', v_encontrados,
            'pendentes', v_pendentes,
            'ambiguos', 0,
            'total_analisado',
                v_encontrados + v_pendentes,

            'valor_encontrado', v_valor_encontrado,
            'valor_pendente', v_valor_pendente
        ),

        'detalhes', v_detalhes
    );
END;
$$;
