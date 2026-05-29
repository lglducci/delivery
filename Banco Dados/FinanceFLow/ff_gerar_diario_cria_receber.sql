    CREATE OR REPLACE FUNCTION contab.ff_gerar_diario_cria_receber(
    p_empresa_id BIGINT,
    p_data    DATE   
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_qtd INTEGER := 0;
BEGIN
    /*
      🔹 Tabela usada: fin.contas_receber  (troque se o nome for outro)
      Campos esperados (adapte se precisar):
        - empresa_id
        - descricao
        - valor
        - vencimento
        - fornecedor_id        -- parceiro
        - parcelas             -- total de parcelas da dívida
        - parcela_nr           -- nº da parcela (1..N)
        - status               -- 'aberto', 'pago', etc
        - criado_em            -- data de criação da dívida
        - lote_id              -- identificador do grupo de parcelas da mesma dívida
    */

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
    outros ,
    contabil_id 
)
SELECT
    cr.empresa_id,
    MIN(cr.criado_em)::date,
 
        cr.modelo_codigo,
      
    'Criação de Recebimento: ' || MAX(cr.descricao)
      || ' (' || MAX(cr.parcelas) || ' parcelas)',
    'CR-' || cr.lote_id,
    cr.fornecedor_id,

    -- 🔥 BUSCA DO CNPJ (NÃO NULO)
    (
      SELECT p.cpf_cnpj
      FROM public.pessoa p
      WHERE p.id = cr.fornecedor_id
    ) AS cnpj,

    MAX(cr.vencimento)::date,
    SUM(cr.valor),
    0, 0, 0,
    'rascunho',
    jsonb_build_object(
        'origem', 'CONTAS_RECEBER',
        'evento', 'CRIA_RECEBER',
        'vencimento',   MAX(cr.vencimento),
        'parcelas',  MAX(cr.descricao),
        'modelo',  cr.modelo_codigo ,
        'conta_contabil_id', contabil_id
    ) ,
 
    cr.contabil_id 
FROM contas_a_receber cr
WHERE cr.empresa_id = p_empresa_id
    AND cr.criado_em::date =  p_data
 -- AND cr.status IN ('aberto', 'em_aberto')
GROUP BY
    cr.empresa_id,
    cr.lote_id,
    cr.fornecedor_id,
   cr.modelo_codigo ,
    cr.contabil_id;  
 

 
END;
$$;