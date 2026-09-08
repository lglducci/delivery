CREATE OR REPLACE FUNCTION public.ff_recebimento_cartao_sem_baixa_titulo(
    p_empresa_id BIGINT,
    p_conta_id BIGINT,
    p_valor NUMERIC,
    p_data DATE,
    p_historico TEXT,
    p_forma_recebimento TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_modelo_codigo TEXT;
    v_contabil_id BIGINT;
    v_classificacao TEXT := 'receita';
    v_tipo_evento TEXT := 'cartao_recebimento';
    v_transacao_id BIGINT;
    v_conta_financeira BIGINT;
BEGIN

 
 
IF p_forma_recebimento = 'aprazo' THEN
    v_tipo_evento := 'aprazo';

ELSIF p_forma_recebimento = 'cartao_credito' THEN
    v_tipo_evento := 'cartao_recebimento';
    v_classificacao := 'baixa_ativo';

ELSIF p_forma_recebimento = 'cartao_debito' THEN
    v_tipo_evento := 'aprazo';
    v_classificacao := 'receita';

END IF;
    --------------------------------------------------------------
    -- CONTA CONTÁBIL DA CONTA FINANCEIRA
    --------------------------------------------------------------
    SELECT cf.contabil_id, cf.conta_financeira_id
    INTO v_contabil_id, v_conta_financeira
    FROM contas_financeiras cf
    WHERE cf.empresa_id = p_empresa_id
      AND cf.id = p_conta_id;

    IF v_contabil_id IS NULL THEN
        RAISE EXCEPTION
            'Conta financeira % sem contabil_id.',
            p_conta_id;
    END IF;

    --------------------------------------------------------------
    -- MODELO CONTÁBIL
    --------------------------------------------------------------
    v_modelo_codigo :=
        contab.ff_get_modelo_evento(
            p_empresa_id,
            v_classificacao,
            v_tipo_evento
        );

    IF v_modelo_codigo IS NULL THEN
        RAISE EXCEPTION
            'Modelo não encontrado para classificacao=% tipo_evento=%',
            v_classificacao,
            v_tipo_evento;
    END IF;

    --------------------------------------------------------------
    -- REGISTRA A ENTRADA FINANCEIRA
    --------------------------------------------------------------
    INSERT INTO public.transacoes(
        empresa_id,
        conta_id,
        categoria_id,
        tipo,
        valor,
        data_movimento,
        descricao,
        receber_id,
        evento_codigo,
        origem,
        classificacao,
        contabil_id,
        forma
    )
    VALUES (
        p_empresa_id,
        v_conta_financeira,
        NULL,
        'entrada',
        ABS(p_valor),
        p_data,
        p_historico,
        NULL,                       -- NÃO sabemos ainda qual título
        v_modelo_codigo,
        'Recebimento Cartao',
        v_classificacao,
        v_contabil_id,
        p_forma_recebimento
    )
    RETURNING id
    INTO v_transacao_id;

    --------------------------------------------------------------
    -- NÃO ATUALIZA contas_a_receber
    --------------------------------------------------------------
    -- A baixa dos títulos será feita posteriormente
    -- na conciliação Consumer x Getnet.
    --------------------------------------------------------------

    PERFORM contab.marcar_reprocessamento(
        p_empresa_id,
        p_data
    );

    RETURN v_transacao_id;
END;
$$;