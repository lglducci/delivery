CREATE OR REPLACE FUNCTION contab.fn_importa_extrato_pdf(
    p_empresa_id   BIGINT,
    p_conta_id     BIGINT,
    p_contabil_id  BIGINT,
    p_movimentos   JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS
$$
DECLARE
    r JSONB;
    v_data DATE;
    v_qtd  INTEGER := 0;
BEGIN

    -- limpa importação anterior
    DELETE
      FROM contab.conciliacao_tmp
     WHERE empresa_id = p_empresa_id ;

    -- insere movimentos do PDF
    FOR r IN
        SELECT *
        FROM jsonb_array_elements(p_movimentos)
    LOOP

        v_data :=
            to_date(
                r->>'data' || '/' || extract(year from current_date),
                'DD/MM/YYYY'
            );

        INSERT INTO contab.conciliacao_tmp
        (
            empresa_id,
            conta_id,
            origem,
            origem_id,
            data_mov,
            valor,
            tipo,
            historico
        )
        VALUES
        (
            p_empresa_id,
            p_conta_id,
            'P',
            v_qtd + 1,
            v_data,
            (r->>'valor')::numeric,
            r->>'tipo',
            r->>'historico'
        );

        v_qtd := v_qtd + 1;

    END LOOP;

    -- chama a conciliação
 --   PERFORM contab.fn_concilia_extrato_pdf_razao(
 --       p_empresa_id,
  --      p_conta_id,
  --      p_contabil_id
  --  );

    RETURN jsonb_build_object(
        'ok', true,
        'movimentos_importados', v_qtd
    );

END;
$$;