CREATE OR REPLACE FUNCTION public.ff_normalizar_data_compra_implantacao(
    p_data_compra_original date,
    p_data_referencia date,
    p_dia_corte integer
)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_mes_referencia date;
    v_periodo_ini date;
    v_periodo_fim date;

    v_dia_compra integer;
    v_ultimo_dia_mes integer;
    v_data_candidata date;
BEGIN
    ------------------------------------------------------------------
    -- VALIDAÇÕES
    ------------------------------------------------------------------
    IF p_data_compra_original IS NULL THEN
        RAISE EXCEPTION 'Informe a data original da compra.';
    END IF;

    IF p_data_referencia IS NULL THEN
        RAISE EXCEPTION 'Informe a referência da fatura.';
    END IF;

    IF p_dia_corte IS NULL OR p_dia_corte < 1 OR p_dia_corte > 31 THEN
        RAISE EXCEPTION 'Dia de corte inválido: %.', p_dia_corte;
    END IF;

    v_mes_referencia :=
        date_trunc('month', p_data_referencia)::date;

    ------------------------------------------------------------------
    -- PERÍODO DA FATURA
    --
    -- Referência março/2026 e corte dia 13:
    -- início = 14/02/2026
    -- fim    = 13/03/2026
    ------------------------------------------------------------------
    v_periodo_ini :=
        (
            v_mes_referencia
            - INTERVAL '1 month'
            + p_dia_corte * INTERVAL '1 day'
        )::date;

    v_ultimo_dia_mes :=
        EXTRACT(
            DAY FROM (
                v_mes_referencia
                + INTERVAL '1 month'
                - INTERVAL '1 day'
            )
        )::integer;

    v_periodo_fim :=
        make_date(
            EXTRACT(YEAR FROM v_mes_referencia)::integer,
            EXTRACT(MONTH FROM v_mes_referencia)::integer,
            LEAST(p_dia_corte, v_ultimo_dia_mes)
        );

    ------------------------------------------------------------------
    -- SE A COMPRA JÁ ESTÁ DENTRO DO PERÍODO, PRESERVA A DATA
    ------------------------------------------------------------------
    IF p_data_compra_original BETWEEN v_periodo_ini AND v_periodo_fim THEN
        RETURN p_data_compra_original;
    END IF;

    v_dia_compra :=
        EXTRACT(DAY FROM p_data_compra_original)::integer;

    ------------------------------------------------------------------
    -- TENTA O MESMO DIA NO MÊS INICIAL DO PERÍODO
    --
    -- Compra original dia 27:
    -- candidato = 27/02/2026
    ------------------------------------------------------------------
    v_ultimo_dia_mes :=
        EXTRACT(
            DAY FROM (
                date_trunc('month', v_periodo_ini)
                + INTERVAL '1 month'
                - INTERVAL '1 day'
            )
        )::integer;

    v_data_candidata :=
        make_date(
            EXTRACT(YEAR FROM v_periodo_ini)::integer,
            EXTRACT(MONTH FROM v_periodo_ini)::integer,
            LEAST(v_dia_compra, v_ultimo_dia_mes)
        );

    IF v_data_candidata BETWEEN v_periodo_ini AND v_periodo_fim THEN
        RETURN v_data_candidata;
    END IF;

    ------------------------------------------------------------------
    -- SENÃO, USA O MESMO DIA NO MÊS FINAL DO PERÍODO
    --
    -- Compra original dia 10:
    -- 10/02 fica antes de 14/02
    -- resultado = 10/03/2026
    ------------------------------------------------------------------
    v_ultimo_dia_mes :=
        EXTRACT(
            DAY FROM (
                date_trunc('month', v_periodo_fim)
                + INTERVAL '1 month'
                - INTERVAL '1 day'
            )
        )::integer;

    v_data_candidata :=
        make_date(
            EXTRACT(YEAR FROM v_periodo_fim)::integer,
            EXTRACT(MONTH FROM v_periodo_fim)::integer,
            LEAST(v_dia_compra, v_ultimo_dia_mes)
        );

    IF v_data_candidata BETWEEN v_periodo_ini AND v_periodo_fim THEN
        RETURN v_data_candidata;
    END IF;

    RAISE EXCEPTION
        'Não foi possível encaixar a data % no período de % até %.',
        p_data_compra_original,
        v_periodo_ini,
        v_periodo_fim;
END;
$$;