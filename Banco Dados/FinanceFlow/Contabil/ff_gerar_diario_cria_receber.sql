 CREATE OR REPLACE FUNCTION contab.ff_gerar_diario_cria_receber(
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
    -- 1. CONTAS A RECEBER NÃO PARCELADAS
    -- Cada recebível gera seu próprio diário.
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
        contabil_id
    )
    SELECT
        cr.empresa_id,

        cr.criado_em::date,

        cr.modelo_codigo,

        'Criação de Recebimento: ' || cr.descricao,

        'CR-' || cr.id::text,

        cr.fornecedor_id,

        p.cpf_cnpj,

        cr.vencimento::date,

        cr.valor,

        0,
        0,
        0,

        'rascunho',

        jsonb_build_object(
            'origem', 'CONTAS_RECEBER',
            'evento', 'CRIA_RECEBER',
            'data_criacao', cr.criado_em,
            'parcelas', COALESCE(cr.parcelas, 1),
            'parcela_num', COALESCE(cr.parcela_num, 1),
            'receber_id', cr.id,
            'contabil_id', cr.contabil_id
        ),

        cr.contabil_id

    FROM public.contas_a_receber cr

    LEFT JOIN public.pessoa p
      ON p.id = cr.fornecedor_id

    WHERE cr.empresa_id = p_empresa_id
      AND cr.criado_em::date = p_data
      AND (
            COALESCE(cr.parcelas, 1) = 1
            OR cr.lote_id IS NULL
          );

    GET DIAGNOSTICS v_qtd_simples = ROW_COUNT;


    ------------------------------------------------------------------
    -- 2. CONTAS A RECEBER PARCELADAS
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
        contabil_id
    )
    SELECT
        cr.empresa_id,

        MIN(cr.criado_em)::date,

        cr.modelo_codigo,

        'Criação de Recebimento parcelado: '
            || MAX(cr.descricao)
            || ' ('
            || COUNT(*)
            || ' parcelas)',

        'CR-LOTE-' || cr.lote_id::text,

        cr.fornecedor_id,

        MAX(p.cpf_cnpj),

        -- vencimento da primeira parcela
        MIN(cr.vencimento)::date,

        -- valor total do recebível parcelado
        SUM(cr.valor),

        0,
        0,
        0,

        'rascunho',

        jsonb_build_object(
            'origem', 'CONTAS_RECEBER',
            'evento', 'CRIA_RECEBER_PARCELADO',
            'data_criacao', MIN(cr.criado_em),
            'parcelas', COUNT(*),
            'lote_id', cr.lote_id,
            'primeira_parcela_id', MIN(cr.id),
            'contabil_id', cr.contabil_id
        ),

        cr.contabil_id

    FROM public.contas_a_receber cr

    LEFT JOIN public.pessoa p
      ON p.id = cr.fornecedor_id

    WHERE cr.empresa_id = p_empresa_id
      AND cr.criado_em::date = p_data
      AND cr.lote_id IS NOT NULL
      AND COALESCE(cr.parcelas, 1) > 1

    GROUP BY
        cr.empresa_id,
        cr.lote_id,
        cr.fornecedor_id,
        cr.modelo_codigo,
        cr.contabil_id;

    GET DIAGNOSTICS v_qtd_parceladas = ROW_COUNT;


    RETURN v_qtd_simples + v_qtd_parceladas;

END;
$$;