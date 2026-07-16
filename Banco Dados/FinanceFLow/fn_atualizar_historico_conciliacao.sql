CREATE OR REPLACE FUNCTION public.fn_atualizar_historico_conciliacao(
    p_empresa_id bigint,
    p_conciliacao_id bigint,
    p_historico_lancamento text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_historico text;
BEGIN
    v_historico := trim(COALESCE(p_historico_lancamento, ''));

    IF v_historico = '' THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'O histórico do lançamento não pode ficar vazio.'
        );
    END IF;

    UPDATE public.conciliacao_financeira
       SET historico_lancamento = v_historico
     WHERE id = p_conciliacao_id
       AND empresa_id = p_empresa_id
       AND COALESCE(status_conciliacao, 'pendente') <> 'executado';

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'ok', false,
            'message', 'Registro não encontrado ou já executado.'
        );
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'message', 'Histórico do lançamento atualizado.',
        'conciliacao_id', p_conciliacao_id,
        'historico_lancamento', v_historico
    );
END;
$$;