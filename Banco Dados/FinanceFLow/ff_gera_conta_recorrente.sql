 CREATE OR REPLACE FUNCTION public.ff_gera_conta_recorrente(
  p_empresa_id integer,
  p_recorrente_id bigint,
  p_competencia date,
  p_conta_id integer,
  p_valor numeric,
  p_data_pagamento date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_existe boolean;
  v_descricao text;
  
  v_dia_vencimento integer;
  v_competencia date;
BEGIN
  v_competencia := date_trunc('month', p_competencia)::date;

  SELECT
    descricao, 
    dia_vencimento
  INTO
    v_descricao, 
    v_dia_vencimento
  FROM public.contas_recorrentes
  WHERE empresa_id = p_empresa_id
    AND id = p_recorrente_id
    AND ativo = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conta recorrente inativa ou  não encontrada.';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.contas_recorrentes_geradas g
    WHERE g.empresa_id = p_empresa_id
      AND g.recorrente_id = p_recorrente_id
      AND date_trunc('month', g.competencia)::date = v_competencia
  )
  INTO v_existe;

  IF v_existe THEN
    RAISE EXCEPTION
      'Esta conta recorrente já foi gerada para a competência %.',
      to_char(v_competencia,'MM/YYYY');
  END IF;

  PERFORM public.ff_registrar_despesa(
    p_empresa_id,
    p_conta_id,
    null,
    null,
    null,
    p_valor,
    v_descricao || ' Ref. ' || to_char(v_competencia,'MM/YYYY'),
    p_data_pagamento,
    'WebApp',
    'despesa',
    null,
    'avista'
  );

 INSERT INTO public.contas_recorrentes_geradas (
    empresa_id,
    recorrente_id,
    competencia,
    conta_id,
    data_pagamento,
    valor_gerado,
    descricao,
    criado_em
  )
  VALUES (
    p_empresa_id,
    p_recorrente_id,
    v_competencia,
    p_conta_id,
    p_data_pagamento,
    p_valor,
     v_descricao || ' Ref. ' || to_char(v_competencia,'MM/YYYY'),
    now()
  );


  RETURN jsonb_build_object(
    'ok', true,
    'message', 'Conta recorrente gerada com sucesso',
    'competencia', to_char(v_competencia,'MM/YYYY'),
    'data_pagamento', p_data_pagamento,
    'valor', p_valor
  );
END;
$$;