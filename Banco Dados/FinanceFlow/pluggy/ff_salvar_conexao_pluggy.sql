 DROP FUNCTION IF EXISTS public.ff_salvar_conexao_pluggy(
    BIGINT,
    BIGINT,
    UUID
);

CREATE OR REPLACE FUNCTION public.ff_salvar_conexao_pluggy(
    p_empresa_id BIGINT,
    p_conta_id   BIGINT,
    p_item_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_conexao public.pluggy_conexoes;
BEGIN
    ------------------------------------------------------------
    -- Validação: empresa
    ------------------------------------------------------------
    IF COALESCE(p_empresa_id, 0) <= 0 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'acao', 'NAO_GRAVAR',
            'tipo_erro', 'EMPRESA_NAO_INFORMADA',
            'mensagem', 'Empresa não informada.'
        );
    END IF;

    ------------------------------------------------------------
    -- Validação: conta
    ------------------------------------------------------------
    IF COALESCE(p_conta_id, 0) <= 0 THEN
        RETURN jsonb_build_object(
            'ok', false,
            'acao', 'NAO_GRAVAR',
            'tipo_erro', 'CONTA_NAO_INFORMADA',
            'mensagem', 'Conta financeira não informada.'
        );
    END IF;

    ------------------------------------------------------------
    -- Validação: item da Pluggy
    ------------------------------------------------------------
    IF p_item_id IS NULL THEN
        RETURN jsonb_build_object(
            'ok', false,
            'acao', 'NAO_GRAVAR',
            'tipo_erro', 'ITEM_ID_NAO_INFORMADO',
            'mensagem', 'Item ID da Pluggy não informado.'
        );
    END IF;

    ------------------------------------------------------------
    -- Confirma que a conta pertence à empresa
    ------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM public.contas_financeiras cf
        WHERE cf.id = p_conta_id
          AND cf.empresa_id = p_empresa_id
    ) THEN
        RETURN jsonb_build_object(
            'ok', false,
            'acao', 'EXCLUIR_ITEM_PLUGGY',
            'tipo_erro', 'CONTA_FINANCEFLOW_NAO_ENCONTRADA',
            'item_id', p_item_id,
            'empresa_id', p_empresa_id,
            'conta_id', p_conta_id,
            'mensagem',
                format(
                    'A conta %s não foi encontrada para a empresa %s.',
                    p_conta_id,
                    p_empresa_id
                )
        );
    END IF;

    ------------------------------------------------------------
    -- Grava ou atualiza a conexão
    ------------------------------------------------------------
    INSERT INTO public.pluggy_conexoes (
        empresa_id,
        conta_id,
        item_id
    )
    VALUES (
        p_empresa_id,
        p_conta_id,
        p_item_id
    )
    ON CONFLICT (empresa_id, conta_id)
    DO UPDATE SET
        item_id = EXCLUDED.item_id
    RETURNING *
    INTO v_conexao;

    ------------------------------------------------------------
    -- Retorno de sucesso
    ------------------------------------------------------------
    RETURN jsonb_build_object(
        'ok', true,
        'acao', 'CONEXAO_SALVA',
        'mensagem', 'Conexão Pluggy salva com sucesso.',
        'conexao', jsonb_build_object(
            'id', v_conexao.id,
            'empresa_id', v_conexao.empresa_id,
            'conta_id', v_conexao.conta_id,
            'item_id', v_conexao.item_id,
            'criado_em', v_conexao.criado_em
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'ok', false,
            'acao', 'TENTAR_SALVAR_NOVAMENTE',
            'tipo_erro', 'ERRO_AO_GRAVAR_CONEXAO',
            'item_id', p_item_id,
            'empresa_id', p_empresa_id,
            'conta_id', p_conta_id,
            'mensagem', SQLERRM
        );
END;
$$;