      CREATE OR REPLACE FUNCTION ff_registrar_conta_pagar_com_parcelas(
  p_empresa_id     	BIGINT,
  p_descricao      	TEXT,
  p_valor_total    	NUMERIC,
  p_data                        DATE,
  p_vencimento   	  DATE,
  p_categoria     	 TEXT DEFAULT NULL,
  p_parcelas     	  INT DEFAULT 1,
  p_fornecedor_id  	BIGINT DEFAULT NULL,
  p_categoria_id    	 BIGINT DEFAULT NULL,
  p_doc_ref              	text DEFAULT NULL,
 p_classsificacao        text DEFAULT not NULL,
 codigo  text default null ,
 p_forma_pagamento   text default not null 
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_categoria_id BIGINT;
    v_id BIGINT;
    v_valor_parcela NUMERIC;
    v_venc DATE;
    i INT;
    v_lote_id BIGINT := NULL;
   modelo_codigo text; 
   v_contabil_id  BIGINT := NULL;
   v_regra_id BIGINT := NULL;
BEGIN

 -- Só gera lote se houver mais de 1 parcela
    IF p_parcelas > 1 THEN
        v_lote_id := nextval('contas_a_pagar_lote_seq');
    END IF;

 modelo_codigo := NULLIF(TRIM(codigo), '');

    -----------------------------------------------------------
    -- 1) PRIORIDADE TOTAL: SE p_categoria_id VEM → USA DIRETO
    -----------------------------------------------------------
    IF p_categoria_id IS NOT NULL AND p_categoria_id > 0 THEN
        v_categoria_id := p_categoria_id;

    -----------------------------------------------------------
    -- 2) SE NÃO VEIO p_categoria_id → PROCURA PELO NOME
    ---------- 
    END IF;

 IF modelo_codigo IS NULL OR modelo_codigo = 'null' THEN
             modelo_codigo := contab.ff_get_modelo_evento(
                   p_empresa_id,  p_classsificacao,  'pagar'   );
end if;
       
    -----------------------------------------------------------
    -- CALCULAR VALOR POR PARCELA
    -----------------------------------------------------------
    v_valor_parcela := ROUND(p_valor_total / p_parcelas, 2);

    -----------------------------------------------------------
    -- CRIAR TODAS AS PARCELAS
    -----------------------------------------------------------


 

    FOR i IN 1..p_parcelas LOOP

        -- calcular data da parcela usando sua função
        v_venc := ff_calcula_data_parcela(p_vencimento, i);

        INSERT INTO contas_a_pagar (
            empresa_id,
            descricao,
            valor,
            vencimento,
            categoria_id,
            parcelas,
            parcela_num,
            status,
            fornecedor_id,
           lote_id ,
          doc_ref , 
         modelo_codigo ,
         classificacao,
          forma_pagamento , 
          criado_em
        )
        VALUES (
            p_empresa_id,
            p_descricao,
            v_valor_parcela,
            v_venc,
            v_categoria_id,
            p_parcelas,
            i,
            'aberto',
            p_fornecedor_id,
           v_lote_id ,
           p_doc_ref , 
           modelo_codigo ,
             p_classsificacao,
            p_forma_pagamento  ,
           p_data                         
        )
        RETURNING id INTO v_id;
 
    END LOOP; 

        
 IF v_contabil_id IS NULL THEN
  SELECT r.conta_id
  INTO v_contabil_id
  FROM public.regras_classificacao_contabil r
  WHERE r.empresa_id = p_empresa_id
    AND r.ativo = true
    AND r.conta_id IS NOT NULL
    AND r.tipo_evento = 'pagar'
    AND r.tipo_movimento = 'saida'
    AND lower(trim(p_descricao)) LIKE '%' || lower(trim(r.texto_busca)) || '%'
  ORDER BY r.prioridade ASC, length(r.texto_busca) DESC
  LIMIT 1;
   END IF;


 IF v_contabil_id IS NULL THEN
  INSERT INTO public.regras_classificacao_contabil (
    empresa_id,
    texto_busca,
    tipo_movimento,
    conta_id,
    ativo,
    prioridade,
    tipo_evento,
    classificacao
  )
  VALUES (
    p_empresa_id,
    trim(p_descricao),
    'saida',
    NULL,
    false,
    100,
    'pagar',
    'despesa'
  )
  ON CONFLICT (empresa_id, texto_busca, tipo_movimento) DO UPDATE
  SET
    tipo_evento = EXCLUDED.tipo_evento,
    classificacao = EXCLUDED.classificacao,
    conta_id = EXCLUDED.conta_id,
    ativo = EXCLUDED.ativo,
    prioridade = EXCLUDED.prioridade
  RETURNING id INTO v_regra_id; 
  RAISE NOTICE 'REGRA GERADA/ATUALIZADA ID: %, DESC: %', v_regra_id, trim(p_descricao);
END IF;


    RETURN v_id; -- retorna a última parcela criada
END;
$$;