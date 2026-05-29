 CREATE OR REPLACE FUNCTION contab.marcar_reprocessamento(
  p_empresa_id bigint,
  p_data date
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_empresa_id IS NULL OR p_data IS NULL THEN
    RETURN;
  END IF;

  IF p_data > CURRENT_DATE THEN
    RETURN;
  END IF;

  UPDATE contab.controle_fechamento
  SET data_reprocessar_de =
    CASE
      WHEN data_reprocessar_de IS NULL THEN p_data
      WHEN p_data < data_reprocessar_de THEN p_data
      ELSE data_reprocessar_de
    END
  WHERE empresa_id = p_empresa_id;
END;
$$;