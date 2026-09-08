CREATE OR REPLACE FUNCTION public.ff_aprender_regra_contabil(
  p_empresa_id bigint,
  p_texto_busca text,
  p_tipo_movimento text,
  p_conta_id bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF NULLIF(trim(p_texto_busca), '') IS NULL THEN
    RETURN;
  END IF;

  IF p_conta_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.regras_classificacao_contabil (
    empresa_id,
    texto_busca,
    tipo_movimento,
    conta_id,
    ativo,
    prioridade
  )
  VALUES (
    p_empresa_id,
    trim(p_texto_busca),
    NULLIF(trim(p_tipo_movimento), ''),
    p_conta_id,
    true,
    100
  )
  ON CONFLICT (empresa_id, texto_busca, tipo_movimento)
  DO UPDATE SET
    conta_id = EXCLUDED.conta_id,
    ativo = true;
END;
$$;