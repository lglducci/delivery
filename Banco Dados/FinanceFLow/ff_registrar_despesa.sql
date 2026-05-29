 CREATE OR REPLACE FUNCTION public.ff_registrar_despesa(
  p_empresa_id integer,
  p_conta_id integer,
  p_categoria_id integer,
  p_conta_nome text,
  p_categoria_nome text,
  p_valor numeric,
  p_descricao text,
  p_data date DEFAULT CURRENT_DATE,
  p_origem text DEFAULT 'ZAP',
  p_classificacao text DEFAULT 'despesa',
  p_codigo text DEFAULT NULL,
  p_forma_pagamento text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $function$
DECLARE
  v_conta_id bigint;
  v_cat_id bigint;
  v_id bigint;
  v_modelo_codigo text;
  v_contabil_id BIGINT;
  v_regra_id  BIGINT;
BEGIN
  IF p_conta_id IS NOT NULL AND p_conta_id > 0 THEN
    v_conta_id := p_conta_id;
  ELSE
    v_conta_id := public.ff_get_conta_id(p_empresa_id, p_conta_nome);
  END IF;

  IF p_categoria_id IS NOT NULL AND p_categoria_id > 0 THEN
    v_cat_id := p_categoria_id;
  ELSE
    v_cat_id := public.ff_get_categoria_id(p_empresa_id, p_categoria_nome, 'saida');
  END IF;

  v_modelo_codigo := NULLIF(p_codigo, '');

  IF v_modelo_codigo IS NULL OR lower(v_modelo_codigo) = 'null' THEN
    v_modelo_codigo := contab.ff_get_modelo_evento(
      p_empresa_id,
      COALESCE(NULLIF(p_classificacao, ''), 'despesa'),
      'financeiro'
    );
  END IF;

  INSERT INTO public.transacoes (
    empresa_id,
    conta_id,
    categoria_id,
    tipo,
    valor,
    descricao,
    data_movimento,
    origem,
    classificacao,
    evento_codigo,
    forma_pagamento
  )
  VALUES (
    p_empresa_id,
    v_conta_id,
    v_cat_id,
    'saida',
    p_valor,
    p_descricao,
    p_data,
    p_origem,
    COALESCE(NULLIF(p_classificacao, ''), 'despesa'),
    v_modelo_codigo,
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
    'financeiro',
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


  RETURN v_id;
END;
$function$;