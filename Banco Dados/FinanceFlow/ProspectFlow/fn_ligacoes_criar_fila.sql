CREATE OR REPLACE FUNCTION prospect.fn_ligacoes_criar_fila(
    p_empresa_id BIGINT,
    p_data       DATE,
    p_limite     INTEGER,
    p_lead_id    BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    v_limite          INTEGER :=
        LEAST(GREATEST(COALESCE(p_limite, 12), 1), 100);

    v_total_leads     INTEGER := 0;
    v_total_ligacoes  INTEGER := 0;
    v_dados           JSONB;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id e obrigatorio';
    END IF;

    p_data := COALESCE(p_data, CURRENT_DATE);

    IF p_lead_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM prospect.leads AS l
           WHERE l.empresa_id = p_empresa_id
             AND l.id = p_lead_id
       )
    THEN
        RAISE EXCEPTION
            'lead nao encontrado: empresa_id=%, lead_id=%',
            p_empresa_id,
            p_lead_id;
    END IF;

    WITH elegiveis AS (
        SELECT l.id AS lead_id
        FROM prospect.leads AS l
        WHERE l.empresa_id = p_empresa_id

          AND (
              (
                  p_lead_id IS NULL
                  AND l.canal_preferido = 'TELEFONE'
              )
              OR (
                  p_lead_id IS NOT NULL
                  AND l.id = p_lead_id
              )
          )

          AND NULLIF(BTRIM(l.telefone), '') IS NOT NULL
          AND COALESCE(l.nao_contatar, FALSE) = FALSE
          AND l.status NOT IN (
              'CONVERTIDO',
              'ENCERRADO',
              'BLOQUEADO'
          )

          AND NOT EXISTS (
              SELECT 1
              FROM prospect.ligacoes AS lg
              WHERE lg.empresa_id = l.empresa_id
                AND lg.lead_id = l.id
          )

        ORDER BY l.updated_at ASC, l.id ASC

        LIMIT CASE
            WHEN p_lead_id IS NOT NULL THEN 1
            ELSE v_limite
        END

        FOR UPDATE OF l SKIP LOCKED
    ),

    tentativas AS (
        SELECT
            e.lead_id,
            h.tentativa,
            (p_data + h.horario)
                AT TIME ZONE 'America/Sao_Paulo'
                AS agendada_para
        FROM elegiveis AS e

        CROSS JOIN (
            VALUES
                (1::SMALLINT, TIME '09:00'),
                (2::SMALLINT, TIME '15:00'),
                (3::SMALLINT, TIME '17:00')
        ) AS h(tentativa, horario)
    ),

    inseridas AS (
        INSERT INTO prospect.ligacoes (
            empresa_id,
            lead_id,
            agendada_para,
            tentativa,
            resultado
        )
        SELECT
            p_empresa_id,
            t.lead_id,
            t.agendada_para,
            t.tentativa,
            'PENDENTE'
        FROM tentativas AS t

        ON CONFLICT (
            empresa_id,
            lead_id,
            tentativa
        )
        DO NOTHING

        RETURNING *
    )

    SELECT
        COUNT(DISTINCT i.lead_id),
        COUNT(*)
    INTO
        v_total_leads,
        v_total_ligacoes
    FROM inseridas AS i;

    SELECT COALESCE(
        JSONB_AGG(
            TO_JSONB(q)
            ORDER BY q.nome, q.tentativa
        ),
        '[]'::JSONB
    )
    INTO v_dados
    FROM (
        SELECT
            lg.id,
            lg.lead_id,
            COALESCE(
                NULLIF(l.empresa_nome, ''),
                l.nome
            ) AS nome,
            l.telefone,
            lg.tentativa,
            lg.agendada_para,
            lg.resultado,
            lg.observacao,
            lg.realizada_em
        FROM prospect.ligacoes AS lg

        INNER JOIN prospect.leads AS l
            ON l.id = lg.lead_id
           AND l.empresa_id = lg.empresa_id

        WHERE lg.empresa_id = p_empresa_id
          AND (
              lg.agendada_para
              AT TIME ZONE 'America/Sao_Paulo'
          )::DATE = p_data

          AND (
              p_lead_id IS NULL
              OR lg.lead_id = p_lead_id
          )

        ORDER BY nome, lg.tentativa
    ) AS q;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'modo',
            CASE
                WHEN p_lead_id IS NULL
                    THEN 'FILA_AUTOMATICA'
                ELSE 'LEAD_ESPECIFICO'
            END,
        'data', p_data,
        'lead_id', p_lead_id,
        'leads_adicionados', v_total_leads,
        'ligacoes_criadas', v_total_ligacoes,
        'dados', v_dados
    );
END;
$$;