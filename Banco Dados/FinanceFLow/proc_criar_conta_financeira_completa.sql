 CREATE OR REPLACE FUNCTION public.proc_criar_conta_financeira_completa(
    p_id_empresa      BIGINT,
    p_nome            TEXT,
    p_banco           TEXT,
    p_nro_banco       TEXT,
    p_agencia         TEXT,
    p_conta           TEXT,
    p_conjunta        BOOLEAN,
    p_juridica        BOOLEAN,
    p_padrao          BOOLEAN,
    p_tipo            TEXT,
    p_saldo_inicial   NUMERIC,
    p_codigo_contabil TEXT
)
RETURNS TABLE (
    id BIGINT,
    empresa_id BIGINT,
    nome TEXT,
    banco TEXT,
    nro_banco TEXT,
    tipo TEXT,
    saldo_inicial NUMERIC,
    contabil_id BIGINT,
    mensagem TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_conta_contabil_id BIGINT;
    v_conta_fin_id BIGINT;

    v_codigo_banco TEXT;
    v_nome_banco TEXT;
    v_msg TEXT := '';

    v_banco_por_codigo RECORD;
    v_banco_por_nome RECORD;
BEGIN
    p_nro_banco := NULLIF(TRIM(p_nro_banco), '');
    p_banco := NULLIF(TRIM(p_banco), '');

    -------------------------------------------------------
    -- 0️⃣ VALIDA / AJUSTA BANCO
    -------------------------------------------------------

    IF p_nro_banco IS NULL THEN
        RAISE EXCEPTION 'Número do banco é obrigatório';
    END IF;

    IF p_banco IS NULL THEN
        RAISE EXCEPTION 'Nome do banco é obrigatório';
    END IF;

    SELECT *
    INTO v_banco_por_codigo
    FROM public.bancos
    WHERE codigo = p_nro_banco
      AND COALESCE(ativo, true) = true
    LIMIT 1;

    IF FOUND THEN
        v_codigo_banco := v_banco_por_codigo.codigo;
        v_nome_banco := v_banco_por_codigo.nome;

        IF lower(trim(p_banco)) <> lower(trim(v_nome_banco)) THEN
            v_msg := 'Nome do banco ajustado pelo cadastro oficial: ' || v_nome_banco;
        ELSE
            v_msg := 'Banco validado com sucesso.';
        END IF;

    ELSE
        SELECT *
        INTO v_banco_por_nome
        FROM public.bancos b
        WHERE COALESCE(b.ativo, true) = true
          AND regexp_replace(lower(b.nome), '[^a-z0-9]', '', 'g')
              =
              regexp_replace(lower(p_banco), '[^a-z0-9]', '', 'g')
        LIMIT 1;

        IF FOUND THEN
            v_codigo_banco := v_banco_por_nome.codigo;
            v_nome_banco := v_banco_por_nome.nome;

            v_msg := 'Número do banco ajustado pelo cadastro oficial: '
                     || v_codigo_banco || ' - ' || v_nome_banco;

        ELSE
            INSERT INTO public.bancos (
                codigo,
                nome,
                ativo
            )
            VALUES (
                p_nro_banco,
                p_banco,
                true
            );

            v_codigo_banco := p_nro_banco;
            v_nome_banco := p_banco;

            v_msg := 'Banco não existia no cadastro e foi incluído automaticamente.';
        END IF;
    END IF;

    -------------------------------------------------------
    -- 1️⃣ CRIA CONTA CONTÁBIL
    -------------------------------------------------------

    v_conta_contabil_id :=
        contab.ff_cria_conta_inexistente(
            p_id_empresa,
            p_codigo_contabil,
            p_nome
        );

    -------------------------------------------------------
    -- 2️⃣ INSERE CONTA FINANCEIRA
    -------------------------------------------------------

    INSERT INTO public.contas_financeiras (
        empresa_id,
        nome,
        banco,
        tipo,
        saldo_inicial,
        padrao,
        nro_banco,
        agencia,
        conta,
        conjunta,
        juridica,
        contabil_id
    )
    VALUES (
        p_id_empresa,
        p_nome,
        v_nome_banco,
        p_tipo,
        COALESCE(p_saldo_inicial, 0),
        p_padrao,
        v_codigo_banco,
        p_agencia,
        p_conta,
        p_conjunta,
        p_juridica,
        v_conta_contabil_id
    )
    RETURNING public.contas_financeiras.id INTO v_conta_fin_id;

    -------------------------------------------------------
    -- 3️⃣ SALDO INICIAL CONTÁBIL
    -------------------------------------------------------

    INSERT INTO contab.saldos_iniciais (
        empresa_id,
        conta_id,
        data_base,
        saldo
    )
    VALUES (
        p_id_empresa,
        v_conta_contabil_id,
        DATE '2000-01-01',
        COALESCE(p_saldo_inicial, 0)
    );

    -------------------------------------------------------
    -- 4️⃣ RETORNO
    -------------------------------------------------------

    RETURN QUERY
    SELECT
        cf.id,
        cf.empresa_id,
        cf.nome,
        cf.banco,
        cf.nro_banco,
        cf.tipo,
        cf.saldo_inicial,
        cf.contabil_id,
        v_msg
    FROM public.contas_financeiras cf
    WHERE cf.id = v_conta_fin_id;
END;
$$;