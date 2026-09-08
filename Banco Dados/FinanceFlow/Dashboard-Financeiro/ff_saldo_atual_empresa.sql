CREATE OR REPLACE FUNCTION public.ff_saldo_atual_empresa(
  p_empresa_id bigint
)
RETURNS numeric
LANGUAGE sql
AS $$
  SELECT COALESCE(SUM(saldo_final), 0)
  FROM public.ff_consultar_saldo_periodo(
    p_empresa_id,
    DATE '2021-01-01',
    CURRENT_DATE,
    0
  );
$$;