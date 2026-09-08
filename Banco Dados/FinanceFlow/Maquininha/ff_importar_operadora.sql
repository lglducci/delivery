CREATE OR REPLACE FUNCTION public.ff_importar_operadora(
    p_empresa_id bigint,
    p_conta_id bigint,
    p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_importacao_id bigint;
    v_gravacao jsonb;
    v_conferencia jsonb;
BEGIN

    SELECT public.ff_gravar_importacao_operadora(
        p_empresa_id,
        p_conta_id,
        p_payload
    )
    INTO v_gravacao;

    v_importacao_id :=
        (v_gravacao->>'importacao_id')::bigint;

    /*SELECT public.ff_conferir_operadora_consumer(
        p_empresa_id, 
        v_importacao_id
    )
    INTO v_conferencia;*/

    RETURN jsonb_build_object(
        'ok', true,
        'importacao_id', v_importacao_id,
        'gravacao', v_gravacao,
        'conferencia', v_conferencia
    );
END;
$$;