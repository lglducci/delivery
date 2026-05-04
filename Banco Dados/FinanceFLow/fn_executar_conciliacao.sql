 CREATE OR REPLACE FUNCTION public.fn_executar_conciliacao(
    p_empresa_id bigint,
    p_conta_id bigint,
    v_lote_conciliacao_id bigint 
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_pagar_ids json;
    v_receber_ids json;
    v_fatura_ids json;

    r record;
   v_inicio_execucao timestamp;
    v_qtd_pagar int := 0;
    v_qtd_receber int := 0;
    v_qtd_fatura int := 0;
    v_qtd_transacao int := 0;
  
BEGIN
   v_inicio_execucao := now();

 UPDATE public.conciliacao_financeira
SET classificacao =
  CASE
    WHEN upper(historico) LIKE '%RECEBIDO%'
      OR upper(historico) LIKE '%RECEBIMENTO%'
      OR upper(historico) LIKE '%RECEBIDA%'
      OR upper(historico) LIKE '%CRÉD%'
      OR upper(historico) LIKE '%CRED%'
    THEN 'receita'
    ELSE 'despesa'
  END
WHERE classificacao = 'financeiro'
  AND empresa_id = p_empresa_id 
  AND lote_conciliacao_id = v_lote_conciliacao_id;

    ------------------------------------------------------------------
    -- CONTAS A PAGAR
    ------------------------------------------------------------------
    SELECT COALESCE(json_agg(DISTINCT pagar_id), '[]'::json)
    INTO v_pagar_ids
    FROM public.conciliacao_financeira
    WHERE empresa_id = p_empresa_id
      AND importar = true
      AND status_conciliacao = 'ok'
      AND pagar_id IS NOT NULL   
      AND lote_conciliacao_id = v_lote_conciliacao_id;

    SELECT json_array_length(v_pagar_ids) INTO v_qtd_pagar;

    IF v_qtd_pagar > 0 THEN
        PERFORM public.ff_pagar_contas(
            p_empresa_id,
            v_pagar_ids,
            p_conta_id
        );
    END IF;


    ------------------------------------------------------------------
    -- CONTAS A RECEBER
    ------------------------------------------------------------------
    SELECT COALESCE(json_agg(DISTINCT receber_id), '[]'::json)
    INTO v_receber_ids
    FROM public.conciliacao_financeira
    WHERE empresa_id = p_empresa_id
      AND conta_financeira_id = p_conta_id
      AND importar = true
      AND status_conciliacao = 'ok'
      AND receber_id IS NOT NULL
      AND lote_conciliacao_id = v_lote_conciliacao_id;

    SELECT json_array_length(v_receber_ids) INTO v_qtd_receber;

    IF v_qtd_receber > 0 THEN
        PERFORM public.ff_receber_contas(
            p_empresa_id,
            v_receber_ids,
            p_conta_id
        );
    END IF;


    ------------------------------------------------------------------
    -- FATURAS DE CARTÃO
    ------------------------------------------------------------------
    SELECT COALESCE(json_agg(DISTINCT fatura_id), '[]'::json)
    INTO v_fatura_ids
    FROM public.conciliacao_financeira
    WHERE empresa_id = p_empresa_id
      AND importar = true
      AND status_conciliacao = 'ok'
      AND fatura_id IS NOT NULL
      AND lote_conciliacao_id = v_lote_conciliacao_id;

    SELECT json_array_length(v_fatura_ids) INTO v_qtd_fatura;

    IF v_qtd_fatura > 0 THEN
        PERFORM public.ff_registrar_pagamento_faturas(
            p_empresa_id,
            p_conta_id,
            v_fatura_ids
        );
    END IF;


    ------------------------------------------------------------------
    -- TRANSAÇÕES SIMPLES
    -- entrada = receita
    -- saida   = despesa
    ------------------------------------------------------------------
    FOR r IN
        SELECT *
        FROM public.conciliacao_financeira
        WHERE empresa_id = p_empresa_id
          AND importar = true
          AND status_conciliacao = 'ok'
          AND pagar_id IS NULL
          AND receber_id IS NULL
          AND fatura_id IS NULL
               AND COALESCE(tipo_evento, 'financeiro') IN (
                    'transferencia',
                    'financeiro',
                    'transacao',
                    'receber_cartao',
                    'pagar_fatura',
                    'juros',
                    'pagar',
                    'receber' 
                    )
         AND lote_conciliacao_id = v_lote_conciliacao_id 
    LOOP

        IF r.tipo = 'entrada' THEN

        PERFORM public.ff_registrar_receita(
            p_empresa_id::integer,
            p_conta_id::integer,
            r.categoria_id::integer,
            NULL::text,
            NULL::text,
            abs(r.valor)::numeric,
            r.historico::text,
            r.data_mov::date,
            'conciliacao'::text,
            COALESCE(r.classificacao, 'receita')::text,
            r.modelo_codigo::text,
            r.forma::text
        );

            v_qtd_transacao := v_qtd_transacao + 1;

        ELSIF r.tipo = 'saida' THEN

          PERFORM public.ff_registrar_despesa(
                p_empresa_id::integer,
                p_conta_id::integer,
                r.categoria_id::integer,
                NULL::text,
                NULL::text,
                abs(r.valor)::numeric,
                r.historico::text,
                r.data_mov::date,
                'conciliacao'::text,
                COALESCE(r.classificacao, 'despesa')::text,
                r.modelo_codigo::text,
                r.forma::text
            );

            v_qtd_transacao := v_qtd_transacao + 1;

        END IF;

    END LOOP;


------------------------------------------------------------------
-- TRANSFERÊNCIA MESMA TITULARIDADE
-- gera 2 transações financeiras + 1 partida dobrada contábil
------------------------------------------------------------------
FOR r IN
    SELECT *
    FROM public.conciliacao_financeira
    WHERE empresa_id = p_empresa_id
      AND importar = true
      AND status_conciliacao = 'ok'
      AND tipo_evento = 'transf_mesma_tit'
      AND lote_conciliacao_id = v_lote_conciliacao_id
LOOP

    PERFORM public.ff_transferencia_entre_contas_com_contabil(
        p_empresa_id,
        p_conta_id,
        r.destino_id, -- precisa existir na conciliacao ou vir de tabela pendente
        abs(r.valor),
        r.historico,
        r.data_mov,
        v_lote_conciliacao_id
    );

    v_qtd_transacao := v_qtd_transacao + 2;

END LOOP;

    ------------------------------------------------------------------
    -- MARCA COMO EXECUTADO
    ------------------------------------------------------------------

 

UPDATE public.conciliacao_financeira
SET status_conciliacao = 'executado',
    mensagem_conciliacao = 'Conciliação executada com sucesso' 
WHERE empresa_id = p_empresa_id
  AND importar = true
  AND status_conciliacao = 'ok' 
  AND lote_conciliacao_id = v_lote_conciliacao_id;

  
UPDATE public.conciliacao_financeira
SET 
    lote_conciliacao_id = v_lote_conciliacao_id
WHERE empresa_id = p_empresa_id
  AND importar = false
  AND status_conciliacao = 'rejeitado'
  AND COALESCE(lote_conciliacao_id, 0) = 0;


 
-- 2) amarra transferências ao mesmo lote
/*UPDATE public.transferencia_mesma_titularidade_pendente t
SET 
    lote_conciliacao_id = v_lote_conciliacao_id 
   
FROM public.conciliacao_financeira c
WHERE c.id = t.conciliacao_id
  AND c.empresa_id = t.empresa_id
  AND t.empresa_id = p_empresa_id 
  AND COALESCE(t.lote_conciliacao_id, 0) = 0;*/
 


UPDATE public.transacoes
SET importacao_id = v_lote_conciliacao_id
WHERE empresa_id = p_empresa_id
  AND conta_id = p_conta_id
  AND COALESCE(importacao_id, 0) = 0
  AND criado_em >= v_inicio_execucao
  AND lower(origem) IN (
    'conciliacao',
    'pagamento',
    'recebimento',
    'pagamento_fatura'
  );

          PERFORM  contab.ff_processa_automatico ( p_empresa_id  ) ;

    RETURN jsonb_build_object(
        'ok', true,
         'lote_conciliacao_id', v_lote_conciliacao_id,
        'pagar', v_qtd_pagar,
        'receber', v_qtd_receber,
        'faturas', v_qtd_fatura,
        'transacoes', v_qtd_transacao
    );

END;
$$;