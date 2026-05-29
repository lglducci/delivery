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
    v_chave text;
v_conta_origem_id bigint;
v_conta_destino_id bigint;
v_transacao_id  bigint;
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

        SELECT  public.ff_registrar_receita(
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
        ) INTO v_transacao_id;

            v_qtd_transacao := v_qtd_transacao + 1;

        ELSIF r.tipo = 'saida' THEN

          select  public.ff_registrar_despesa(
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
             ) INTO v_transacao_id;

            v_qtd_transacao := v_qtd_transacao + 1;

        END IF;

        IF v_transacao_id IS NOT NULL AND r.conta_id IS NOT NULL THEN
        UPDATE public.transacoes
        SET contabil_id = r.conta_id
        WHERE id = v_transacao_id
            AND empresa_id = p_empresa_id;
        END IF;

    END LOOP;


------------------------------------------------------------------
-- TRANSFERÊNCIA MESMA TITULARIDADE
-- gera 2 transações financeiras + 1 partida dobrada contábil
------------------------------------------------------------------
/* 
FOR r IN
    SELECT *
    FROM public.conciliacao_financeira
    WHERE empresa_id = p_empresa_id
      AND importar = true
      AND status_conciliacao = 'ok'
      AND tipo_evento = 'transf_mesma_tit'
      AND lote_conciliacao_id = v_lote_conciliacao_id
 
 
LOOP

    IF r.valor < 0 THEN
        -- saiu da conta importada
        PERFORM public.ff_transferencia_entre_contas_com_contabil(
            p_empresa_id,
            p_conta_id,
            r.destino_id,
            abs(r.valor),
            r.historico,
            r.data_mov,
            v_lote_conciliacao_id
        );
    ELSE
        -- entrou na conta importada
        PERFORM public.ff_transferencia_entre_contas_com_contabil(
            p_empresa_id,
            r.destino_id,
            p_conta_id,
            abs(r.valor),
            r.historico,
            r.data_mov,
            v_lote_conciliacao_id
        );
    END IF;

    v_qtd_transacao := v_qtd_transacao + 2;

END LOOP;*/


        FOR r IN
                SELECT *
                FROM public.conciliacao_financeira
                WHERE empresa_id = p_empresa_id
                    AND importar = true
                    AND status_conciliacao = 'ok'
                    AND tipo_evento = 'transf_mesma_tit'
                    AND lote_conciliacao_id = v_lote_conciliacao_id
                LOOP

                IF r.valor < 0 THEN
                    -- saiu da conta importada
                    v_conta_origem_id := p_conta_id;
                    v_conta_destino_id := r.destino_id;
                ELSE
                    -- entrou na conta importada
                    v_conta_origem_id := r.destino_id;
                    v_conta_destino_id := p_conta_id;
                END IF;

                v_chave :=
                    p_empresa_id || '|' ||
                    r.data_mov || '|' ||
                    v_conta_origem_id || '|' ||
                    v_conta_destino_id || '|' ||
                    ROUND(ABS(r.valor), 2)::text || '|' ||
                    COALESCE(v_lote_conciliacao_id, 0);

                IF EXISTS (
                    SELECT 1
                    FROM public.transferencia_contas
                    WHERE empresa_id = p_empresa_id
                    AND chave = v_chave
                ) THEN
                    UPDATE public.conciliacao_financeira
                    SET
                    status_conciliacao = 'rejeitado',
                    importar = false,
                    mensagem_conciliacao = 'Valor duplicado. Já existe transferência igual registrada.'
                    WHERE id = r.id
                    AND empresa_id = p_empresa_id;

                    CONTINUE;
                END IF;

                PERFORM public.ff_transferencia_entre_contas_com_contabil(
                    p_empresa_id,
                    v_conta_origem_id,
                    v_conta_destino_id,
                    ABS(r.valor),
                    r.historico,
                    r.data_mov,
                    v_lote_conciliacao_id,
                    r.id
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
  

 UPDATE contab.controle_fechamento cf
SET data_reprocessar_de = x.menor_data
FROM (
    SELECT MIN(c.data_mov) AS menor_data
    FROM public.conciliacao_financeira c
    WHERE c.empresa_id = p_empresa_id
      AND c.lote_conciliacao_id = v_lote_conciliacao_id
      AND c.status_conciliacao = 'executado'
) x
WHERE cf.empresa_id = p_empresa_id
  AND x.menor_data IS NOT NULL
  AND (
    cf.data_reprocessar_de IS NULL
    OR x.menor_data < cf.data_reprocessar_de
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