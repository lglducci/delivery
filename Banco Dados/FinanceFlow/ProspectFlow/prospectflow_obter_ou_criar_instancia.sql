 CREATE OR REPLACE FUNCTION public.prospectflow_obter_ou_criar_instancia(
    p_empresa_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_instancia prospect.empresa_instancias%ROWTYPE;
    v_nome      text;
BEGIN
    IF p_empresa_id IS NULL OR p_empresa_id <= 0 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'mensagem', 'empresa_id inválida'
        );
    END IF;

    /*
      Procura uma instância já criada e ativa.
    */
    SELECT *
      INTO v_instancia
      FROM prospect.empresa_instancias
     WHERE empresa_id = p_empresa_id
       AND ativo = true
     ORDER BY id
     LIMIT 1;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'ok', true,
            'existe', true,
            'empresa_id', v_instancia.empresa_id,
            'instancia_nome', v_instancia.instancia_nome,
            'numero_whatsapp', v_instancia.numero_whatsapp,
            'token', v_instancia.token,
            'finalidade', v_instancia.finalidade
        );
    END IF;

    /*
      Não existe: gera prospectflow_empresa_X.
    */
    v_nome := 'prospectflow_empresa_' || p_empresa_id::text;

    /*
      Reserva o nome localmente.
      ativo=false porque ainda falta criar na Evolution.
    */
    INSERT INTO prospect.empresa_instancias (
        empresa_id,
        instancia_nome,
        numero_whatsapp,
        finalidade,
        ativo
    )
    VALUES (
        p_empresa_id,
        v_nome,
        null,
        'PROSPECTFLOW',
        false
    )
    ON CONFLICT (instancia_nome)
    DO UPDATE SET
        atualizado_em = now()
    RETURNING *
      INTO v_instancia;

    RETURN jsonb_build_object(
        'ok', true,
        'existe', false,
        'empresa_id', v_instancia.empresa_id,
        'instancia_nome', v_instancia.instancia_nome,
        'numero_whatsapp', v_instancia.numero_whatsapp,
        'finalidade', v_instancia.finalidade
    );
END;
$function$;