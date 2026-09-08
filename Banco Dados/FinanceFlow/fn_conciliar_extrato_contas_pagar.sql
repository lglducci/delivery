 CREATE OR REPLACE FUNCTION public.fn_conciliar_extrato_contas_pagar(
    prm_empresa_id bigint,
    prm_conta_financeira_id bigint,
    prm_id_maior_que bigint DEFAULT 0,
    prm_conciliacao_id bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
    x record;
    v_recorrente_id bigint;
BEGIN
    FOR r IN
        SELECT *
        FROM public.conciliacao_financeira
        WHERE empresa_id = prm_empresa_id
          AND conta_financeira_id = prm_conta_financeira_id
          AND tipo = 'saida'
          AND pagar_id IS NULL
          AND fornecedor_id IS NOT NULL
          AND id > prm_id_maior_que
          AND (
              prm_conciliacao_id IS NULL
              OR id = prm_conciliacao_id
          )
        ORDER BY data_mov, id
    LOOP
        x := NULL;
        v_recorrente_id := NULL;

        




        ------------------------------------------------------------------
-- 1) PROCURA CONTA A PAGAR
------------------------------------------------------------------
SELECT
    p.id AS pagar_id,
    (
      50
      + CASE 
          WHEN abs(p.valor - abs(r.valor)) <= 0.05 THEN 30
          WHEN abs(p.valor - abs(r.valor)) <= 5 THEN 20
          WHEN abs(p.valor - abs(r.valor)) <= 20 THEN 10
          ELSE 0
        END
      + CASE 
          WHEN abs(p.vencimento - r.data_mov) <= 3 THEN 20
          WHEN abs(p.vencimento - r.data_mov) <= 7 THEN 10
          WHEN abs(p.vencimento - r.data_mov) <= 15 THEN 5
          WHEN abs(p.vencimento - r.data_mov) <= 45 THEN 2
          ELSE 0
        END
    )::numeric(5,2) AS score,

    concat(
      'status=', p.status,
      '; fornecedor=sim',
      '; valor_conta=', p.valor,
      '; valor_extrato=', abs(r.valor),
      '; dif_valor=', abs(p.valor - abs(r.valor)),
      '; vencimento=', p.vencimento,
      '; data_mov=', r.data_mov,
      '; dif_dias=', abs(p.vencimento - r.data_mov)
    ) AS criterio,

    COALESCE(p.status, 'aberto') AS pagar_status

INTO x
FROM public.contas_a_pagar p
WHERE p.empresa_id = r.empresa_id
  AND p.fornecedor_id = r.fornecedor_id

  -- Não filtra o status, pois precisamos saber se já está paga
  AND abs(p.valor - abs(r.valor)) <= 20
  AND abs(p.vencimento - r.data_mov) <= 45

  AND NOT EXISTS (
      SELECT 1
      FROM public.conciliacao_financeira ja
      WHERE ja.empresa_id = r.empresa_id
        AND ja.pagar_id = p.id
  )

ORDER BY
    score DESC,
    abs(p.valor - abs(r.valor)) ASC,
    p.vencimento ASC,
    p.id ASC
LIMIT 1;

------------------------------------------------------------------
-- 2) ACHOU CONTA A PAGAR
------------------------------------------------------------------
IF x.pagar_id IS NOT NULL AND x.score >= 70 THEN

    ------------------------------------------------------------------
    -- 2.1) CONTA JÁ ESTÁ PAGA: REJEITA A CONCILIAÇÃO
    ------------------------------------------------------------------
    IF lower(trim(COALESCE(x.pagar_status, 'aberto'))) = 'pago' THEN

        UPDATE public.conciliacao_financeira
           SET pagar_id = x.pagar_id,
               match_score = x.score,
               match_criterio = x.criterio,
               tipo_evento = 'pagar',
               status_conciliacao = 'rejeitado',
               importar = false,
               mensagem_conciliacao = 'Esta conta a pagar já se encontra paga'
         WHERE id = r.id
           AND empresa_id = r.empresa_id;

        -- Não altera contas_a_pagar.
        -- Não insere em conta_pagar_receber_conciliacao.

    ------------------------------------------------------------------
    -- 2.2) CONTA ESTÁ ABERTA: BAIXA E REGISTRA CONTROLE
    ------------------------------------------------------------------
    ELSE

    --    UPDATE public.contas_a_pagar
    --       SET status = 'pago',
    --           data_pagamento = r.data_mov
   --      WHERE id = x.pagar_id
    --       AND empresa_id = r.empresa_id;

        UPDATE public.conciliacao_financeira
           SET pagar_id = x.pagar_id,
               match_score = x.score,
               match_criterio = x.criterio,
               tipo_evento = 'pagar'
         WHERE id = r.id
           AND empresa_id = r.empresa_id;

        INSERT INTO public.conta_pagar_receber_conciliacao (
            empresa_id,
            lote_conciliacao_id,
            conciliacao_financeira_id,
            transacao_id,
            tipo_evento,
            conta_pagar_id,
            status,
            acao,
            resolvido_em
        )
        VALUES (
            r.empresa_id,
            r.lote_conciliacao_id,
            r.id,
            r.transacao_id,
            'pagar',
            x.pagar_id,
            'resolvido',
            'encontrou_pagar_baixou',
            now()
        )
        ON CONFLICT (conciliacao_financeira_id)
        DO UPDATE SET
            conta_pagar_id = EXCLUDED.conta_pagar_id,
            transacao_id = EXCLUDED.transacao_id,
            status = 'resolvido',
            acao = 'encontrou_pagar_baixou',
            resolvido_em = now();

    END IF;
 

    ------------------------------------------------------------------
    -- 3) NÃO ACHOU CONTA A PAGAR:
    -- CONTINUA AQUI SUA PROCURA PELA RECORRENTE
    ------------------------------------------------------------------


        -- fim aqui 
        ELSE

            ------------------------------------------------------------------
            -- 3) NÃO ACHOU CONTA A PAGAR: PROCURA RECORRENTE
            ------------------------------------------------------------------
            SELECT cr.id
              INTO v_recorrente_id
            FROM public.contas_recorrentes cr
            WHERE cr.empresa_id = r.empresa_id
              AND cr.fornecedor_id = r.fornecedor_id
              AND cr.ativo = true
              AND (
                    abs(cr.dia_vencimento - EXTRACT(DAY FROM r.data_mov)::int) <= 7
                    OR EXTRACT(DAY FROM r.data_mov)::int BETWEEN 25 AND 31
                    OR EXTRACT(DAY FROM r.data_mov)::int BETWEEN 1 AND 7
                  )
              AND (
                    upper(coalesce(cr.tipo_valor, 'VARIAVEL')) = 'VARIAVEL'
                    OR abs(coalesce(cr.valor_padrao, 0) - abs(r.valor)) <= 80
                  )
            ORDER BY
                CASE
                    WHEN upper(coalesce(cr.tipo_valor, 'VARIAVEL')) = 'VARIAVEL' THEN 0
                    ELSE abs(coalesce(cr.valor_padrao, 0) - abs(r.valor))
                END ASC,
                abs(cr.dia_vencimento - EXTRACT(DAY FROM r.data_mov)::int) ASC,
                cr.id ASC
            LIMIT 1;

            ------------------------------------------------------------------
            -- 4) ACHOU RECORRENTE: REGISTRA COMO RESOLVIDO
            ------------------------------------------------------------------
            IF v_recorrente_id IS NOT NULL THEN

                UPDATE public.conciliacao_financeira
                   SET tipo_evento = 'pagar',
                       match_score = 75,
                       match_criterio = 'recorrente encontrada por fornecedor/data/valor flexivel',
                       recorrente_id = v_recorrente_id
                 WHERE id = r.id;

                INSERT INTO public.conta_pagar_receber_conciliacao (
                    empresa_id,
                    lote_conciliacao_id,
                    conciliacao_financeira_id,
                    transacao_id,
                    tipo_evento,
                    recorrente_id,
                    status,
                    acao,
                    resolvido_em
                )
                VALUES (
                    r.empresa_id,
                    r.lote_conciliacao_id,
                    r.id,
                    r.transacao_id,
                    'pagar',
                    v_recorrente_id,
                    'resolvido',
                    'encontrou_recorrente_baixou',
                    now()
                )
                ON CONFLICT (conciliacao_financeira_id)
                DO UPDATE SET
                    recorrente_id = EXCLUDED.recorrente_id,
                    transacao_id = EXCLUDED.transacao_id,
                    status = 'resolvido',
                    acao = 'encontrou_recorrente_baixou',
                    resolvido_em = now();

            ELSE

                ------------------------------------------------------------------
                -- 5) NÃO ACHOU NADA: PENDÊNCIA
                ------------------------------------------------------------------
                INSERT INTO public.conta_pagar_receber_conciliacao (
                    empresa_id,
                    lote_conciliacao_id,
                    conciliacao_financeira_id,
                    transacao_id,
                    tipo_evento,
                    status,
                    acao
                )
                VALUES (
                    r.empresa_id,
                    r.lote_conciliacao_id,
                    r.id,
                    r.transacao_id,
                    'pagar',
                    'pendente',
                    'nao_encontrou_pagar_nem_recorrente'
                )
                ON CONFLICT (conciliacao_financeira_id)
                DO UPDATE SET
                    transacao_id = EXCLUDED.transacao_id,
                    status = 'pendente',
                    acao = 'nao_encontrou_pagar_nem_recorrente',
                    resolvido_em = NULL;

            END IF;
        END IF;
    END LOOP;
END;
$$;