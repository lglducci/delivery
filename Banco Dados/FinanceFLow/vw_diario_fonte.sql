CREATE OR REPLACE VIEW contab.vw_diario_fonte AS
WITH base AS (
    -- =======================================================
    -- AQUI VOCÊ VAI UNINDO AS FONTES REAIS (AJUSTAR DEPOIS)
    -- =======================================================

    -- 1) EXEMPLO – TRANSACOES FINANCEIRAS
    -- SUBSTITUA financeiro.transacoes / campos pelos seus
    
    SELECT
        t.empresa_id,
        t.data_mov,
        t.modelo_codigo,
        t.historico,
        t.doc_ref,
        p.cnpj,
        t.data_mov        AS data_vencto,
        t.parceiro_id,
        t.valor           AS valor_total,
        0::numeric(14,2)  AS valor_custo,
        0::numeric(14,2)  AS valor_imposto,
        0::numeric(14,2)  AS desconto,
        NULL::jsonb       AS outros,
        'TRANSACAO'::text AS origem,
        t.id              AS referencia_id
    FROM public.transacoes t
    LEFT JOIN public.pessoa p
           ON p.id = t.parceiro_id
          AND p.empresa_id = t.empresa_id
 

    -- 2) EXEMPLO – CONTAS A PAGAR
    
    UNION ALL
    SELECT
        cp.empresa_id,
        cp.data_lancamento     AS data_mov,
        cp.modelo_codigo,
        cp.descricao           AS historico,
        cp.doc_ref,
        p.cnpj,
        cp.data_vencto,
        cp.parceiro_id,
        cp.valor               AS valor_total,
        0::numeric(14,2)       AS valor_custo,
        0::numeric(14,2)       AS valor_imposto,
        0::numeric(14,2)       AS desconto,
        NULL::jsonb            AS outros,
        'PAGAR'::text          AS origem,
        cp.id                  AS referencia_id
    FROM public.contas_pagar cp
    LEFT JOIN public.pessoa p
           ON p.id = cp.parceiro_id
          AND p.empresa_id = cp.empresa_id
   

    -- 3) EXEMPLO – CONTAS A RECEBER
    
    UNION ALL
    SELECT
        cr.empresa_id,
        cr.data_lancamento     AS data_mov,
        cr.modelo_codigo,
        cr.descricao           AS historico,
        cr.doc_ref,
        p.cnpj,
        cr.data_vencto,
        cr.parceiro_id,
        cr.valor               AS valor_total,
        0::numeric(14,2)       AS valor_custo,
        0::numeric(14,2)       AS valor_imposto,
        0::numeric(14,2)       AS desconto,
        NULL::jsonb            AS outros,
        'RECEBER'::text        AS origem,
        cr.id                  AS referencia_id
    FROM financeiro.contas_receber cr
    LEFT JOIN public.pessoa p
           ON p.id = cr.parceiro_id
          AND p.empresa_id = cr.empresa_id
 
    -- FIM DOS EXEMPLOS

    -- POR ENQUANTO: VIEW VAZIA, SÓ PRA COMPILAR
    SELECT
        NULL::bigint        AS empresa_id,
        NULL::date          AS data_mov,
        NULL::text          AS modelo_codigo,
        NULL::text          AS historico,
        NULL::varchar(60)   AS doc_ref,
        NULL::varchar(20)   AS cnpj,
        NULL::date          AS data_vencto,
        NULL::int           AS parceiro_id,
        NULL::numeric(14,2) AS valor_total,
        NULL::numeric(14,2) AS valor_custo,
        NULL::numeric(14,2) AS valor_imposto,
        NULL::numeric(14,2) AS desconto,
        NULL::jsonb         AS outros,
        NULL::text          AS origem,
        NULL::bigint        AS referencia_id
    WHERE false
)
SELECT * FROM base;
