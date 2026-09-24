CREATE OR REPLACE FUNCTION public.prospectflow_analise_atividade(
    p_empresa_id bigint,
    p_dias integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_hoje       date;
    v_data_inicio date;
    v_agora      timestamp;
    v_resultado  jsonb;
BEGIN
    /*
     * Limita o período para evitar consultas exageradas.
     */
    IF p_dias IS NULL OR p_dias < 1 OR p_dias > 365 THEN
        RAISE EXCEPTION
            'p_dias deve estar entre 1 e 365. Valor recebido: %',
            p_dias;
    END IF;

    v_agora := CLOCK_TIMESTAMP() AT TIME ZONE 'America/Sao_Paulo';
    v_hoje := v_agora::date;
    v_data_inicio := v_hoje - (p_dias - 1);

    WITH mensagens_enviadas AS (
        /*
         * Somente mensagens enviadas manualmente por você.
         * Respostas recebidas e mensagens automáticas não entram.
         */
        SELECT
            i.id,
            i.lead_id,
            (i.created_at AT TIME ZONE 'America/Sao_Paulo')::date
                AS data_atividade,
            COALESCE(i.canal, 'OUTRO') AS canal
        FROM prospect.interacoes i
        WHERE i.empresa_id = p_empresa_id
          AND i.tipo = 'ENVIO'
          AND i.automatica = FALSE
          AND (i.created_at AT TIME ZONE 'America/Sao_Paulo')::date
              BETWEEN v_data_inicio AND v_hoje
    ),

    tarefas_concluidas AS (
        SELECT
            t.id,
            t.lead_id,
            (t.concluida_em AT TIME ZONE 'America/Sao_Paulo')::date
                AS data_atividade,
            t.tipo
        FROM prospect.tarefas t
        WHERE t.empresa_id = p_empresa_id
          AND t.status = 'CONCLUIDA'
          AND t.concluida_em IS NOT NULL
          AND (t.concluida_em AT TIME ZONE 'America/Sao_Paulo')::date
              BETWEEN v_data_inicio AND v_hoje
    ),

    atividades AS (
        SELECT
            m.data_atividade,
            m.lead_id,
            'MENSAGEM_ENVIADA'::text AS origem
        FROM mensagens_enviadas m

        UNION ALL

        SELECT
            t.data_atividade,
            t.lead_id,
            'TAREFA_CONCLUIDA'::text AS origem
        FROM tarefas_concluidas t
    ),

    atividades_por_dia AS (
        SELECT
            a.data_atividade,

            COUNT(*) FILTER (
                WHERE a.origem = 'MENSAGEM_ENVIADA'
            ) AS mensagens_enviadas,

            COUNT(*) FILTER (
                WHERE a.origem = 'TAREFA_CONCLUIDA'
            ) AS tarefas_concluidas,

            COUNT(*) AS total_atividades,

            COUNT(DISTINCT a.lead_id) AS leads_trabalhados
        FROM atividades a
        GROUP BY a.data_atividade
    ),

    calendario AS (
        /*
         * Gera todos os dias do período, inclusive os dias
         * em que não houve nenhuma atividade.
         */
        SELECT
            GENERATE_SERIES(
                v_data_inicio,
                v_hoje,
                INTERVAL '1 day'
            )::date AS data_atividade
    ),

    dias AS (
        SELECT
            c.data_atividade,
            COALESCE(a.mensagens_enviadas, 0) AS mensagens_enviadas,
            COALESCE(a.tarefas_concluidas, 0) AS tarefas_concluidas,
            COALESCE(a.total_atividades, 0) AS total_atividades,
            COALESCE(a.leads_trabalhados, 0) AS leads_trabalhados
        FROM calendario c
        LEFT JOIN atividades_por_dia a
               ON a.data_atividade = c.data_atividade
    ),

    procrastinacao AS (
        SELECT
            /*
             * Tarefas do período que já venceram
             * e continuam pendentes.
             */
            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (
                        t.agendada_para
                        AT TIME ZONE 'America/Sao_Paulo'
                      ) >= v_data_inicio::timestamp
                  AND (
                        t.agendada_para
                        AT TIME ZONE 'America/Sao_Paulo'
                      ) < v_agora
            ) AS tarefas_vencidas_periodo,

            /*
             * Tarefas agendadas no período que foram concluídas.
             */
            COUNT(*) FILTER (
                WHERE t.status = 'CONCLUIDA'
                  AND (
                        t.agendada_para
                        AT TIME ZONE 'America/Sao_Paulo'
                      ) >= v_data_inicio::timestamp
                  AND (
                        t.agendada_para
                        AT TIME ZONE 'America/Sao_Paulo'
                      ) <= v_agora
            ) AS tarefas_concluidas_periodo,

            /*
             * Todas as tarefas vencidas, inclusive anteriores
             * ao período analisado.
             */
            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (
                        t.agendada_para
                        AT TIME ZONE 'America/Sao_Paulo'
                      ) < v_agora
            ) AS tarefas_vencidas_total,

            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (
                        t.agendada_para
                        AT TIME ZONE 'America/Sao_Paulo'
                      )::date = v_hoje
            ) AS tarefas_pendentes_hoje,

            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (
                        t.agendada_para
                        AT TIME ZONE 'America/Sao_Paulo'
                      ) > v_agora
            ) AS tarefas_futuras
        FROM prospect.tarefas t
        WHERE t.empresa_id = p_empresa_id
    ),

    indicadores AS (
        SELECT
            p.*,

            CASE
                WHEN (
                    p.tarefas_vencidas_periodo
                    + p.tarefas_concluidas_periodo
                ) = 0
                THEN 0::numeric

                ELSE ROUND(
                    (
                        p.tarefas_vencidas_periodo::numeric
                        /
                        (
                            p.tarefas_vencidas_periodo
                            + p.tarefas_concluidas_periodo
                        )::numeric
                    ) * 100,
                    1
                )
            END AS indice_procrastinacao,

            CASE
                WHEN (
                    p.tarefas_vencidas_periodo
                    + p.tarefas_concluidas_periodo
                ) = 0
                THEN 'SEM_DADOS'

                WHEN (
                    p.tarefas_vencidas_periodo::numeric
                    /
                    (
                        p.tarefas_vencidas_periodo
                        + p.tarefas_concluidas_periodo
                    )::numeric
                ) * 100 <= 20
                THEN 'BAIXO'

                WHEN (
                    p.tarefas_vencidas_periodo::numeric
                    /
                    (
                        p.tarefas_vencidas_periodo
                        + p.tarefas_concluidas_periodo
                    )::numeric
                ) * 100 <= 40
                THEN 'MODERADO'

                WHEN (
                    p.tarefas_vencidas_periodo::numeric
                    /
                    (
                        p.tarefas_vencidas_periodo
                        + p.tarefas_concluidas_periodo
                    )::numeric
                ) * 100 <= 70
                THEN 'ALTO'

                ELSE 'CRITICO'
            END AS nivel_procrastinacao
        FROM procrastinacao p
    )

    SELECT JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'empresa_id', p_empresa_id,
        'gerado_em', v_agora,
        'periodo', JSONB_BUILD_OBJECT(
            'dias', p_dias,
            'data_inicio', v_data_inicio,
            'data_final', v_hoje
        ),

        'resumo', JSONB_BUILD_OBJECT(
            'total_mensagens_enviadas',
                (SELECT COUNT(*) FROM mensagens_enviadas),

            'total_tarefas_concluidas',
                (SELECT COUNT(*) FROM tarefas_concluidas),

            'total_atividades',
                (SELECT COUNT(*) FROM atividades),

            'total_leads_trabalhados',
                (
                    SELECT COUNT(DISTINCT a.lead_id)
                    FROM atividades a
                ),

            'dias_com_atividade',
                (
                    SELECT COUNT(*)
                    FROM dias d
                    WHERE d.total_atividades > 0
                ),

            'dias_sem_atividade',
                (
                    SELECT COUNT(*)
                    FROM dias d
                    WHERE d.total_atividades = 0
                ),

            'media_atividades_por_dia',
                (
                    SELECT ROUND(
                        COUNT(*)::numeric / p_dias::numeric,
                        2
                    )
                    FROM atividades
                ),

            'ultima_atividade',
                (
                    SELECT MAX(a.data_atividade)
                    FROM atividades a
                ),

            'dias_desde_ultima_atividade',
                (
                    SELECT
                        CASE
                            WHEN MAX(a.data_atividade) IS NULL
                            THEN NULL
                            ELSE v_hoje - MAX(a.data_atividade)
                        END
                    FROM atividades a
                )
        ),

        'procrastinacao', (
            SELECT JSONB_BUILD_OBJECT(
                'indice', i.indice_procrastinacao,
                'nivel', i.nivel_procrastinacao,
                'tarefas_vencidas_periodo',
                    i.tarefas_vencidas_periodo,
                'tarefas_concluidas_periodo',
                    i.tarefas_concluidas_periodo,
                'tarefas_vencidas_total',
                    i.tarefas_vencidas_total,
                'tarefas_pendentes_hoje',
                    i.tarefas_pendentes_hoje,
                'tarefas_futuras',
                    i.tarefas_futuras,
                'formula',
                    'tarefas vencidas do período / ' ||
                    '(tarefas vencidas + tarefas concluídas do período)'
            )
            FROM indicadores i
        ),

        'mensagens_por_canal',
            COALESCE(
                (
                    SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'canal', x.canal,
                            'quantidade', x.quantidade
                        )
                        ORDER BY x.quantidade DESC
                    )
                    FROM (
                        SELECT
                            m.canal,
                            COUNT(*) AS quantidade
                        FROM mensagens_enviadas m
                        GROUP BY m.canal
                    ) x
                ),
                '[]'::jsonb
            ),

        'tarefas_por_tipo',
            COALESCE(
                (
                    SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'tipo', x.tipo,
                            'quantidade', x.quantidade
                        )
                        ORDER BY x.quantidade DESC
                    )
                    FROM (
                        SELECT
                            t.tipo,
                            COUNT(*) AS quantidade
                        FROM tarefas_concluidas t
                        GROUP BY t.tipo
                    ) x
                ),
                '[]'::jsonb
            ),

        'por_dia',
            COALESCE(
                (
                    SELECT JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'data', d.data_atividade,
                            'mensagens_enviadas',
                                d.mensagens_enviadas,
                            'tarefas_concluidas',
                                d.tarefas_concluidas,
                            'total_atividades',
                                d.total_atividades,
                            'leads_trabalhados',
                                d.leads_trabalhados
                        )
                        ORDER BY d.data_atividade DESC
                    )
                    FROM dias d
                ),
                '[]'::jsonb
            )
    )
    INTO v_resultado;

    RETURN v_resultado;
END;
$function$;