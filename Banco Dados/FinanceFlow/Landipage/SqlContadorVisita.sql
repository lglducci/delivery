CREATE TABLE IF NOT EXISTS public.landing_visitas (
    id SMALLINT PRIMARY KEY DEFAULT 1,
    total BIGINT NOT NULL DEFAULT 0,
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT landing_visitas_unico
        CHECK (id = 1)
);

INSERT INTO public.landing_visitas (
    id,
    total
)
VALUES (
    1,
    0
)
ON CONFLICT (id) DO NOTHING;


ALTER TABLE public.landing_visitas
ENABLE ROW LEVEL SECURITY;


CREATE OR REPLACE FUNCTION public.registrar_visita_landing()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total BIGINT;
BEGIN

    UPDATE public.landing_visitas
       SET total = total + 1,
           atualizado_em = NOW()
     WHERE id = 1
    RETURNING total
         INTO v_total;

    RETURN COALESCE(v_total, 0);

END;
$$;


CREATE OR REPLACE FUNCTION public.obter_total_visitas_landing()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(total, 0)
      FROM public.landing_visitas
     WHERE id = 1;
$$;


REVOKE ALL
ON FUNCTION public.registrar_visita_landing()
FROM PUBLIC;

REVOKE ALL
ON FUNCTION public.obter_total_visitas_landing()
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION public.registrar_visita_landing()
TO anon, authenticated;

GRANT EXECUTE
ON FUNCTION public.obter_total_visitas_landing()
TO anon, authenticated;