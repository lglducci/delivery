 CREATE OR REPLACE FUNCTION contab.ff_gerar_diario_cria_pagar(
    p_empresa_id BIGINT,
    p_data DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_qtd_simples    INTEGER := 0;
    v_qtd_parceladas INTEGER := 0;
BEGIN

    ------------------------------------------------------------------
    -- 1. CONTAS NÃO PARCELADAS
    -- Cada conta a pagar gera seu próprio diário.
    ------------------------------------------------------------------
    INSERT INTO contab.diario_staging (
        empresa_id,
        data_mov,
        modelo_codigo,
        historico,
        doc_ref,
        parceiro_id,
        cnpj,
        data_vencto,
        valor_total,
        valor_custo,
        valor_imposto,
        desconto,
        status,
        outros,
        contabil_id,
        pagar_id,
        lote_id
    )
    SELECT
        cp.empresa_id,
        cp.criado_em::date,
        cp.modelo_codigo,

        'Criação de dívida: ' || cp.descricao,

        'CP-' || cp.id::text,

        cp.fornecedor_id,

        p.cpf_cnpj,

        cp.vencimento::date,

        cp.valor,

        0,
        0,
        0,

        'rascunho',

        jsonb_build_object(
            'origem', 'CONTAS_PAGAR',
            'evento', 'CRIA_PAGAR',
            'data_criacao', cp.criado_em,
            'parcelas', COALESCE(cp.parcelas, 1),
            'parcela_num', COALESCE(cp.parcela_num, 1),
            'pagar_id', cp.id,
            'contabil_id', cp.contabil_id
        ),

        cp.contabil_id,
        cp.id,

        -- Conta simples não pertence a lote parcelado.
        NULL

    FROM public.contas_a_pagar cp

    LEFT JOIN public.pessoa p
      ON p.id = cp.fornecedor_id

    WHERE cp.empresa_id = p_empresa_id
      AND cp.criado_em::date = p_data
      AND (
            COALESCE(cp.parcelas, 1) = 1
            OR cp.lote_id IS NULL
          );

    GET DIAGNOSTICS v_qtd_simples = ROW_COUNT;


    ------------------------------------------------------------------
    -- 2. CONTAS PARCELADAS
    -- Consolida somente parcelas pertencentes ao mesmo lote.
    ------------------------------------------------------------------
    INSERT INTO contab.diario_staging (
        empresa_id,
        data_mov,
        modelo_codigo,
        historico,
        doc_ref,
        parceiro_id,
        cnpj,
        data_vencto,
        valor_total,
        valor_custo,
        valor_imposto,
        desconto,
        status,
        outros,
        contabil_id,
        pagar_id,
        lote_id
    )
    SELECT
        cp.empresa_id,

        MIN(cp.criado_em)::date,

        cp.modelo_codigo,

        'Criação de dívida parcelada: '
            || MAX(cp.descricao)
            || ' ('
            || COUNT(*)
            || ' parcelas)',

        'CP-LOTE-' || cp.lote_id::text,

        cp.fornecedor_id,

        MAX(p.cpf_cnpj),

        -- Vencimento da primeira parcela.
        MIN(cp.vencimento)::date,

        -- Valor total da dívida parcelada.
        SUM(cp.valor),

        0,
        0,
        0,

        'rascunho',

        jsonb_build_object(
            'origem', 'CONTAS_PAGAR',
            'evento', 'CRIA_PAGAR_PARCELADO',
            'data_criacao', MIN(cp.criado_em),
            'parcelas', COUNT(*),
            'lote_id', cp.lote_id,
            'primeira_parcela_id', MIN(cp.id),
            'contabil_id', cp.contabil_id
        ),

        cp.contabil_id,

        -- O valor total não pertence a uma única parcela.
        NULL,

        cp.lote_id

    FROM public.contas_a_pagar cp

    LEFT JOIN public.pessoa p
      ON p.id = cp.fornecedor_id

    WHERE cp.empresa_id = p_empresa_id
      AND cp.criado_em::date = p_data
      AND cp.lote_id IS NOT NULL
      AND COALESCE(cp.parcelas, 1) > 1

    GROUP BY
        cp.empresa_id,
        cp.lote_id,
        cp.fornecedor_id,
        cp.modelo_codigo,
        cp.contabil_id;

    GET DIAGNOSTICS v_qtd_parceladas = ROW_COUNT;


    RETURN v_qtd_simples + v_qtd_parceladas;

END;
$$;