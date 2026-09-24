   CREATE OR REPLACE FUNCTION public.prospectflow_analise_atividade(
    p_empresa_id bigint,
    p_dias integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_agora timestamp;
    v_hoje date;
    v_data_inicio date;
    v_resultado jsonb;
BEGIN
    IF p_empresa_id IS NULL THEN
        RAISE EXCEPTION 'empresa_id é obrigatório';
    END IF;

    IF p_dias IS NULL OR p_dias < 1 OR p_dias > 365 THEN
        RAISE EXCEPTION 'p_dias deve estar entre 1 e 365';
    END IF;

    v_agora := clock_timestamp() AT TIME ZONE 'America/Sao_Paulo';
    v_hoje := v_agora::date;
    v_data_inicio := v_hoje - (p_dias - 1);

    WITH mensagens AS (
        SELECT
            i.id,
            i.lead_id,
            (i.created_at AT TIME ZONE 'America/Sao_Paulo')::date AS data_atividade,
            COALESCE(i.canal, 'OUTRO') AS canal
        FROM prospect.interacoes i
        WHERE i.empresa_id = p_empresa_id
          AND i.tipo = 'ENVIO'
          AND i.automatica = false
          AND (i.created_at AT TIME ZONE 'America/Sao_Paulo')::date
              BETWEEN v_data_inicio AND v_hoje
    ),
    tarefas AS (
        SELECT
            t.id,
            t.lead_id,
            (t.concluida_em AT TIME ZONE 'America/Sao_Paulo')::date AS data_atividade,
            t.tipo
        FROM prospect.tarefas t
        WHERE t.empresa_id = p_empresa_id
          AND t.status = 'CONCLUIDA'
          AND t.concluida_em IS NOT NULL
          AND (t.concluida_em AT TIME ZONE 'America/Sao_Paulo')::date
              BETWEEN v_data_inicio AND v_hoje
    ),
    ligacoes_realizadas AS (
        SELECT
            lg.id,
            lg.lead_id,
            (lg.realizada_em AT TIME ZONE 'America/Sao_Paulo')::date AS data_atividade,
            lg.resultado
        FROM prospect.ligacoes lg
        WHERE lg.empresa_id = p_empresa_id
          AND lg.resultado IN ('ATENDEU', 'SEM_SUCESSO', 'RETORNAR')
          AND lg.realizada_em IS NOT NULL
          AND (lg.realizada_em AT TIME ZONE 'America/Sao_Paulo')::date
              BETWEEN v_data_inicio AND v_hoje
    ),
    atividades AS (
        SELECT
            m.data_atividade,
            m.lead_id,
            'MENSAGEM_ENVIADA'::text AS origem
        FROM mensagens m

        UNION ALL

        SELECT
            t.data_atividade,
            t.lead_id,
            'TAREFA_CONCLUIDA'::text AS origem
        FROM tarefas t

        UNION ALL

        SELECT
            lg.data_atividade,
            lg.lead_id,
            'LIGACAO_REALIZADA'::text AS origem
        FROM ligacoes_realizadas lg
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
            COUNT(*) FILTER (
                WHERE a.origem = 'LIGACAO_REALIZADA'
            ) AS ligacoes_realizadas,
            COUNT(*) AS total_atividades,
            COUNT(DISTINCT a.lead_id) AS leads_trabalhados
        FROM atividades a
        GROUP BY a.data_atividade
    ),
    calendario AS (
        SELECT
            (v_data_inicio + serie.dia::integer)::date AS data_atividade
        FROM generate_series(0, p_dias - 1) AS serie(dia)
    ),
    dias AS (
        SELECT
            c.data_atividade,
            COALESCE(a.mensagens_enviadas, 0) AS mensagens_enviadas,
            COALESCE(a.tarefas_concluidas, 0) AS tarefas_concluidas,
            COALESCE(a.ligacoes_realizadas, 0) AS ligacoes_realizadas,
            COALESCE(a.total_atividades, 0) AS total_atividades,
            COALESCE(a.leads_trabalhados, 0) AS leads_trabalhados
        FROM calendario c
        LEFT JOIN atividades_por_dia a
               ON a.data_atividade = c.data_atividade
    ),
    metricas_tarefas AS (
        SELECT
            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')
                      >= v_data_inicio::timestamp
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo') < v_agora
            ) AS vencidas_periodo,
            COUNT(*) FILTER (
                WHERE t.status = 'CONCLUIDA'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')
                      >= v_data_inicio::timestamp
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo') <= v_agora
            ) AS concluidas_periodo,
            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo') < v_agora
            ) AS vencidas_total,
            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo')::date = v_hoje
            ) AS pendentes_hoje,
            COUNT(*) FILTER (
                WHERE t.status = 'PENDENTE'
                  AND (t.agendada_para AT TIME ZONE 'America/Sao_Paulo') > v_agora
            ) AS futuras
        FROM prospect.tarefas t
        WHERE t.empresa_id = p_empresa_id
    ),
    metricas_ligacoes AS (
        SELECT
            COUNT(*) FILTER (
                WHERE lg.resultado = 'PENDENTE'
                  AND (lg.agendada_para AT TIME ZONE 'America/Sao_Paulo')::date
                      BETWEEN v_data_inicio AND (v_hoje - 1)
                  AND NOT EXISTS (
                      SELECT 1
                      FROM prospect.interacoes ix
                      WHERE ix.empresa_id = lg.empresa_id
                        AND ix.lead_id = lg.lead_id
                  )
            ) AS vencidas_periodo,
            COUNT(*) FILTER (
                WHERE lg.resultado IN ('ATENDEU', 'SEM_SUCESSO', 'RETORNAR')
                  AND lg.realizada_em IS NOT NULL
                  AND (lg.realizada_em AT TIME ZONE 'America/Sao_Paulo')::date
                      BETWEEN v_data_inicio AND v_hoje
            ) AS realizadas_periodo,
            COUNT(*) FILTER (
                WHERE lg.resultado = 'PENDENTE'
                  AND (lg.agendada_para AT TIME ZONE 'America/Sao_Paulo')::date < v_hoje
                  AND NOT EXISTS (
                      SELECT 1
                      FROM prospect.interacoes ix
                      WHERE ix.empresa_id = lg.empresa_id
                        AND ix.lead_id = lg.lead_id
                  )
            ) AS vencidas_total,
            COUNT(*) FILTER (
                WHERE lg.resultado = 'PENDENTE'
                  AND (lg.agendada_para AT TIME ZONE 'America/Sao_Paulo')::date = v_hoje
            ) AS pendentes_hoje,
            COUNT(*) FILTER (
                WHERE lg.resultado = 'PENDENTE'
                  AND (lg.agendada_para AT TIME ZONE 'America/Sao_Paulo')::date > v_hoje
            ) AS futuras
        FROM prospect.ligacoes lg
        WHERE lg.empresa_id = p_empresa_id
    ),
    procrastinacao AS (
        SELECT
            mt.vencidas_periodo AS tarefas_vencidas_periodo,
            mt.concluidas_periodo AS tarefas_concluidas_periodo,
            mt.vencidas_total AS tarefas_vencidas_total,
            mt.pendentes_hoje AS tarefas_pendentes_hoje,
            mt.futuras AS tarefas_futuras,
            ml.vencidas_periodo AS ligacoes_vencidas_periodo,
            ml.realizadas_periodo AS ligacoes_realizadas_periodo,
            ml.vencidas_total AS ligacoes_vencidas_total,
            ml.pendentes_hoje AS ligacoes_pendentes_hoje,
            ml.futuras AS ligacoes_futuras,
            CASE
                WHEN mt.vencidas_periodo + ml.vencidas_periodo
                   + mt.concluidas_periodo + ml.realizadas_periodo = 0
                THEN 0::numeric
                ELSE ROUND(
                    100.0 * (mt.vencidas_periodo + ml.vencidas_periodo)
                    / (
                        mt.vencidas_periodo + ml.vencidas_periodo
                        + mt.concluidas_periodo + ml.realizadas_periodo
                    ),
                    1
                )
            END AS indice
        FROM metricas_tarefas mt
        CROSS JOIN metricas_ligacoes ml
    ),
    indicadores AS (
        SELECT
            p.*,
            CASE
                WHEN p.tarefas_vencidas_periodo + p.ligacoes_vencidas_periodo
                   + p.tarefas_concluidas_periodo + p.ligacoes_realizadas_periodo = 0
                THEN 'SEM_DADOS'
                WHEN p.indice <= 20 THEN 'BAIXO'
                WHEN p.indice <= 40 THEN 'MODERADO'
                WHEN p.indice <= 70 THEN 'ALTO'
                ELSE 'CRITICO'
            END AS nivel
        FROM procrastinacao p
    )
    SELECT jsonb_build_object(
        'ok', true,
        'empresa_id', p_empresa_id,
        'gerado_em', v_agora,
        'periodo', jsonb_build_object(
            'dias', p_dias,
            'data_inicio', v_data_inicio,
            'data_final', v_hoje
        ),
        'resumo', jsonb_build_object(
            'total_mensagens_enviadas', (SELECT COUNT(*) FROM mensagens),
            'total_tarefas_concluidas', (SELECT COUNT(*) FROM tarefas),
            'total_ligacoes_realizadas', (SELECT COUNT(*) FROM ligacoes_realizadas),
            'total_ligacoes_atendidas',
                (SELECT COUNT(*) FROM ligacoes_realizadas WHERE resultado = 'ATENDEU'),
            'total_ligacoes_sem_sucesso',
                (SELECT COUNT(*) FROM ligacoes_realizadas WHERE resultado = 'SEM_SUCESSO'),
            'total_ligacoes_retorno',
                (SELECT COUNT(*) FROM ligacoes_realizadas WHERE resultado = 'RETORNAR'),
            'total_atividades', (SELECT COUNT(*) FROM atividades),
            'total_leads_trabalhados',
                (SELECT COUNT(DISTINCT a.lead_id) FROM atividades a),
            'dias_com_atividade',
                (SELECT COUNT(*) FROM dias d WHERE d.total_atividades > 0),
            'dias_sem_atividade',
                (SELECT COUNT(*) FROM dias d WHERE d.total_atividades = 0),
            'media_atividades_por_dia',
                (SELECT ROUND(COUNT(*)::numeric / p_dias::numeric, 2) FROM atividades),
            'ultima_atividade',
                (SELECT MAX(a.data_atividade) FROM atividades a),
            'dias_desde_ultima_atividade',
                (
                    SELECT CASE
                        WHEN MAX(a.data_atividade) IS NULL THEN NULL
                        ELSE v_hoje - MAX(a.data_atividade)
                    END
                    FROM atividades a
                )
        ),
        'procrastinacao', (
            SELECT jsonb_build_object(
                'indice', i.indice,
                'nivel', i.nivel,
                'tarefas_vencidas_periodo', i.tarefas_vencidas_periodo,
                'tarefas_concluidas_periodo', i.tarefas_concluidas_periodo,
                'tarefas_vencidas_total', i.tarefas_vencidas_total,
                'tarefas_pendentes_hoje', i.tarefas_pendentes_hoje,
                'tarefas_futuras', i.tarefas_futuras,
                'ligacoes_vencidas_periodo', i.ligacoes_vencidas_periodo,
                'ligacoes_realizadas_periodo', i.ligacoes_realizadas_periodo,
                'ligacoes_vencidas_total', i.ligacoes_vencidas_total,
                'ligacoes_pendentes_hoje', i.ligacoes_pendentes_hoje,
                'ligacoes_futuras', i.ligacoes_futuras,
                'formula',
                    '(tarefas vencidas + ligações vencidas sem interação) / pendências e atividades concluídas'
            )
            FROM indicadores i
        ),
        'mensagens_por_canal', COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'canal', x.canal,
                        'quantidade', x.quantidade
                    ) ORDER BY x.quantidade DESC, x.canal
                )
                FROM (
                    SELECT m.canal, COUNT(*) AS quantidade
                    FROM mensagens m
                    GROUP BY m.canal
                ) x
            ),
            '[]'::jsonb
        ),
        'tarefas_por_tipo', COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'tipo', x.tipo,
                        'quantidade', x.quantidade
                    ) ORDER BY x.quantidade DESC, x.tipo
                )
                FROM (
                    SELECT t.tipo, COUNT(*) AS quantidade
                    FROM tarefas t
                    GROUP BY t.tipo
                ) x
            ),
            '[]'::jsonb
        ),
        'ligacoes_por_resultado', COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'resultado', x.resultado,
                        'quantidade', x.quantidade
                    ) ORDER BY x.quantidade DESC, x.resultado
                )
                FROM (
                    SELECT lg.resultado, COUNT(*) AS quantidade
                    FROM ligacoes_realizadas lg
                    GROUP BY lg.resultado
                ) x
            ),
            '[]'::jsonb
        ),
        'por_dia', COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'data', d.data_atividade,
                        'mensagens_enviadas', d.mensagens_enviadas,
                        'tarefas_concluidas', d.tarefas_concluidas,
                        'ligacoes_realizadas', d.ligacoes_realizadas,
                        'leads_trabalhados', d.leads_trabalhados,
                        'total_atividades', d.total_atividades
                    ) ORDER BY d.data_atividade DESC
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

COMMENT ON FUNCTION public.prospectflow_analise_atividade(bigint, integer)
IS 'Retorna mensagens manuais, tarefas e ligações realizadas, além de pendências vencidas usadas no índice de procrastinação do ProspectFlow.';

 
