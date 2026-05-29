  CREATE OR REPLACE FUNCTION ff_registrar_receita(
  p_empresa_id BIGINT,
  p_conta_id  int,
 p_categoria_id int,  
  p_conta_nome TEXT,
  p_categoria_nome TEXT,
  p_valor NUMERIC,
  p_descricao TEXT,
  p_data DATE DEFAULT CURRENT_DATE,
 p_origem TEXT DEFAULT 'ZAP',
 p_classificacao  text default not null ,
 p_codigo   text default null ,
p_forma_pagamento  text default not  null 
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_conta_id BIGINT;
  v_cat_id   BIGINT;
  v_id       BIGINT;
 modelo_codigo  TEXT;
 v_contabil_id BIGINT;
 v_regra_id BIGINT;
BEGIN
    
           IF p_conta_id IS NOT NULL AND p_conta_id > 0 THEN
                           v_conta_id := p_conta_id;
          ELSE
                          v_conta_id := ff_get_conta_id(p_empresa_id, p_conta_nome);
          END IF;
 
         IF p_categoria_id IS NOT NULL AND p_categoria_id > 0 THEN
               v_cat_id := p_categoria_id;
          ELSE
             v_cat_id := ff_get_categoria_id(p_empresa_id, p_categoria_nome, 'entrada');
           END IF;

       
      modelo_codigo := NULLIF(p_codigo  , '');
  IF   modelo_codigo IS NULL OR modelo_codigo = 'null' THEN 
        modelo_codigo := contab.ff_get_modelo_evento(   p_empresa_id,  p_classificacao,  'financeiro');
     end if ;    

  INSERT INTO transacoes (
    empresa_id,
    conta_id,
    categoria_id,
    tipo,
    valor,
    descricao,
    data_movimento,
    origem,
   classificacao ,
   evento_codigo  ,
 forma_pagamento
  )
  VALUES (
    p_empresa_id,
    v_conta_id,
    v_cat_id,
    'entrada',
    p_valor,
    p_descricao,
    p_data,
    p_origem ,
   p_classificacao ,
  modelo_codigo  ,
 p_forma_pagamento 
  )
  RETURNING id INTO v_id;


        
 IF v_contabil_id IS NULL THEN
  SELECT r.conta_id
  INTO v_contabil_id
  FROM public.regras_classificacao_contabil r
  WHERE r.empresa_id = p_empresa_id
    AND r.ativo = true
    AND r.conta_id IS NOT NULL
    AND r.tipo_evento = 'financeiro'
    AND r.tipo_movimento = 'entrado'
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
    'entrada',
    NULL,
    false,
    100,
    'financeiro',
    'receita'
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
 
  RETURN v_id;
END;
$$;
