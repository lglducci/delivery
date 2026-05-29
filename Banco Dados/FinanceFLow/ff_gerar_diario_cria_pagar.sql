 CREATE OR REPLACE FUNCTION contab.ff_gerar_diario_cria_pagar(
    p_empresa_id BIGINT,
    p_data DATE
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_qtd INTEGER := 0;
BEGIN

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
    cp.empresa_id,
    MIN(cp.criado_em)::date,

    -- 🔥 RESOLUÇÃO INTELIGENTE DO MODELO
 
        cp.modelo_codigo, 

    'Criação de dívida: ' || MAX(cp.descricao)
        || ' (' || MAX(cp.parcelas) || ' parcelas)',

    'CP-' || cp.lote_id,
    cp.fornecedor_id,

    (
        SELECT p.cpf_cnpj
        FROM public.pessoa p
        WHERE p.id = cp.fornecedor_id
    ) AS cnpj,

    MAX(cp.vencimento)::date,
    SUM(cp.valor),
    0, 0, 0,
    'rascunho',

    jsonb_build_object(
        'origem', 'CONTAS_PAGAR',
        'evento', 'CRIA_PAGAR',
        'data_criacao', MIN(cp.criado_em),
        'parcelas', MAX(cp.parcelas),
        'contabil_id', cp.contabil_id
    ),
 cp.contabil_id
FROM contas_a_pagar cp 
-- 🔵 BUSCA DO MODELO VIA CATEGORIA

WHERE cp.empresa_id = p_empresa_id
  AND cp.criado_em::date = p_data

GROUP BY
    cp.empresa_id,
    cp.lote_id,
    cp.fornecedor_id,
    cp.modelo_codigo ,
    cp.contabil_id;

GET DIAGNOSTICS v_qtd = ROW_COUNT;

RETURN v_qtd;

END;
$$;
