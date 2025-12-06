 CREATE OR REPLACE FUNCTION ff_calcula_data_parcela(
  p_data_compra DATE,
  p_parcela_num INT
)
RETURNS DATE
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_parcela_num = 1 THEN
    RETURN p_data_compra;
  END IF;

  RETURN (p_data_compra + ((p_parcela_num - 1) * INTERVAL '1 month'))::date;
END;
$$;
