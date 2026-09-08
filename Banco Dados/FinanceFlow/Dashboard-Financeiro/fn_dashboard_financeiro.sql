 CREATE OR REPLACE FUNCTION fn_dashboard_financeiro(p_empresa_id BIGINT) 
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
  result JSON;
BEGIN
  WITH recorrentes_projetadas AS (
    SELECT
      NULL::bigint AS id,
      cr.descricao,
      make_date(
        EXTRACT(YEAR FROM gs.mes)::int,
        EXTRACT(MONTH FROM gs.mes)::int,
        LEAST(
          cr.dia_vencimento,
          EXTRACT(DAY FROM (date_trunc('month', gs.mes) + interval '1 month - 1 day'))::int
        )
      ) AS vencimento,
      COALESCE(cr.valor_padrao, 0)::numeric(14,2) AS valor,
      'recorrente_projetada'::text AS origem
    FROM public.contas_recorrentes cr
    CROSS JOIN generate_series(
      date_trunc('month', CURRENT_DATE)::date,
      date_trunc('month', CURRENT_DATE + interval '30 days')::date,
      interval '1 month'
    ) gs(mes)
    WHERE cr.empresa_id = p_empresa_id
      AND cr.ativo = true
      AND cr.valor_padrao IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.contas_recorrentes_geradas g
        WHERE g.empresa_id = cr.empresa_id
          AND g.recorrente_id = cr.id
          AND date_trunc('month', g.competencia)::date =
              date_trunc('month', gs.mes)::date
      )
  ),

  pagar_base AS (
    SELECT
      cp.id,
      cp.descricao,
      cp.vencimento::date AS vencimento,
      COALESCE(cp.valor, 0)::numeric(14,2) AS valor,
      'conta_pagar'::text AS origem
    FROM public.contas_a_pagar cp
    WHERE cp.empresa_id = p_empresa_id
      AND cp.status = 'aberto'

    UNION ALL

    SELECT
      rp.id,
      rp.descricao,
      rp.vencimento,
      rp.valor,
      rp.origem
    FROM recorrentes_projetadas rp
  )

  SELECT json_build_object(
    'resultado_12_meses', (
      SELECT COALESCE(SUM(resultado), 0)
      FROM vw_resultado_12_meses
      WHERE empresa_id = p_empresa_id
    ),

    'despesa_12_meses', (
      SELECT COALESCE(SUM(total_despesa), 0)
      FROM vw_despesa_12_meses
      WHERE empresa_id = p_empresa_id
    ),

    'saldo_atual', public.ff_saldo_atual_empresa(p_empresa_id),

    'receita_mes', (
      SELECT COALESCE(SUM(total_recebido), 0)
      FROM vw_receita_mes_atual
      WHERE empresa_id = p_empresa_id
    ),

    'resultado_mes', (
      SELECT COALESCE(SUM(resultado), 0)
      FROM vw_resultado_mes_atual
      WHERE empresa_id = p_empresa_id
    ),

    'receita_12m', (
      SELECT json_agg(v)
      FROM vw_receita_12_meses v
      WHERE empresa_id = p_empresa_id
    ),

    'receber_aberto', (
      SELECT COALESCE(SUM(total_receber), 0)
      FROM vw_total_receber_aberto
      WHERE empresa_id = p_empresa_id
    ),

    'pagar_aberto', (
      SELECT COALESCE(SUM(valor), 0)
      FROM pagar_base
    ),

    'receber_vencido', (
      SELECT row_to_json(v)
      FROM vw_receber_vencido v
      WHERE empresa_id = p_empresa_id
    ),

    'pagar_vencido', (
      SELECT row_to_json(v)
      FROM (
        SELECT
          COALESCE(SUM(valor), 0) AS total_vencido,
          COUNT(*) AS quantidade
        FROM pagar_base
        WHERE vencimento < CURRENT_DATE
      ) v
    ),

    'faturas_aberto', (
      SELECT total_aberto
      FROM vw_cartoes_a_pagar_aberto v
      WHERE empresa_id = p_empresa_id
    ),

    'faturas_vencida', (
      SELECT total_vencido
      FROM public.vw_cartoes_vencidos v
      WHERE empresa_id = p_empresa_id
    ),

    'saldo_projetado_30_dias', (
      SELECT COALESCE(SUM(saldo_projetado), 0)
      FROM vw_saldo_projetado_30_dias
      WHERE empresa_id = p_empresa_id
    ),

    'saldo_projetado', (
      SELECT COALESCE(SUM(saldo_projetado), 0)
      FROM vw_saldo_projetado
      WHERE empresa_id = p_empresa_id
    ),

    'proximos_receber', (
      SELECT json_agg(v)
      FROM vw_proximos_recebimentos v
      WHERE empresa_id = p_empresa_id
    ),

    'proximos_pagar', (
      SELECT json_agg(v ORDER BY v.vencimento)
      FROM (
        SELECT
          id,
          descricao,
          vencimento,
          valor,
          origem
        FROM pagar_base
        WHERE vencimento >= CURRENT_DATE
        ORDER BY vencimento
        LIMIT 10
      ) v
    ),

    'receita_6m', (
      SELECT COALESCE(SUM(total_recebido), 0)
      FROM vw_receita_6_meses
      WHERE empresa_id = p_empresa_id
    ),

    'receita_6m_serie', (
      SELECT json_agg(v ORDER BY v.ano_mes)
      FROM vw_receita_6_meses v
      WHERE empresa_id = p_empresa_id
    ),

    'resultado_12m_serie', (
      SELECT json_agg(v ORDER BY v.ano_mes)
      FROM vw_resultado_12_meses v
      WHERE empresa_id = p_empresa_id
    ),

    'despesa_12m_serie', (
      SELECT json_agg(v ORDER BY v.ano_mes)
      FROM vw_despesa_12_meses v
      WHERE empresa_id = p_empresa_id
    ),

    'receita_12m_serie', (
      SELECT json_agg(v ORDER BY v.ano_mes)
      FROM vw_receita_12_meses v
      WHERE empresa_id = p_empresa_id
    ),

    'pagar_vencendo_7d', (
      SELECT COALESCE(SUM(valor), 0)
      FROM pagar_base
      WHERE vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
    ),

    'pagar_vencendo_15d', (
      SELECT COALESCE(SUM(valor), 0)
      FROM pagar_base
      WHERE vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '15 days'
    ),

    'pagar_vencendo_30d', (
      SELECT COALESCE(SUM(valor), 0)
      FROM pagar_base
      WHERE vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
    ),

    'faturas_vencendo_7d', (
      SELECT COALESCE(SUM(valor_total), 0)
      FROM public.cartoes_faturas
      WHERE empresa_id = p_empresa_id
        AND status = 'aberta'
        AND vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
    ),

    'faturas_vencendo_15d', (
      SELECT COALESCE(SUM(valor_total), 0)
      FROM public.cartoes_faturas
      WHERE empresa_id = p_empresa_id
        AND status = 'aberta'
        AND vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '15 days'
    ),

    'faturas_vencendo_30d', (
      SELECT COALESCE(SUM(valor_total), 0)
      FROM public.cartoes_faturas
      WHERE empresa_id = p_empresa_id
        AND status = 'aberta'
        AND vencimento BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
    ),


     'despesa_30_dias', (
      SELECT COALESCE(SUM(total_despesa), 0)
      FROM public.vw_despesa_30_dias 
      WHERE empresa_id = p_empresa_id
    ),
   

      'receita_30_dias', (
      SELECT COALESCE(SUM(total_recebido), 0)
      FROM public.vw_receita_30_dias 
      WHERE empresa_id = p_empresa_id
    ),
 
  
      'resultado_30_dias', (
      SELECT COALESCE(SUM(resultado), 0)
      FROM public.vw_resultado_30_dias 
      WHERE empresa_id = p_empresa_id
    ),
 

 'top_despesas_30_dias', (
  SELECT json_agg(v ORDER BY v.total DESC)
  FROM (
    SELECT
      codigo,
      conta_nome,
      total
    FROM public.vw_top_despesas_30_dias
    WHERE empresa_id = p_empresa_id
    ORDER BY total DESC
    LIMIT 10
  ) v
),



'aumentos_30_dias', (
  SELECT json_agg(v ORDER BY v.variacao_valor DESC)
  FROM (
    SELECT *
    FROM public.vw_variacao_despesas_30_dias
    WHERE empresa_id = p_empresa_id
      AND variacao_valor > 0
    ORDER BY variacao_valor DESC
    LIMIT 5
  ) v
),


'reducoes_30_dias', (
  SELECT json_agg(v ORDER BY v.variacao_valor ASC)
  FROM (
    SELECT *
    FROM public.vw_variacao_despesas_30_dias
    WHERE empresa_id = p_empresa_id
      AND variacao_valor < 0
    ORDER BY variacao_valor ASC
    LIMIT 5
  ) v
),


'projecao_caixa_30_dias', (
  SELECT json_agg(v ORDER BY v.data_ref)
  FROM public.fn_projecao_caixa_30_dias(p_empresa_id) v
),

'menor_saldo_30_dias', (
  SELECT MIN(saldo_previsto)
  FROM public.fn_projecao_caixa_30_dias(p_empresa_id)
),

'data_menor_saldo_30_dias', (
  SELECT data_ref
  FROM public.fn_projecao_caixa_30_dias(p_empresa_id)
  ORDER BY saldo_previsto ASC
  LIMIT 1
),





    'proximas_faturas', (
      SELECT json_agg(v ORDER BY v.vencimento)
      FROM (
        SELECT
          id,
          cartao_id,
          mes_referencia,
          vencimento,
          valor_total,
          status
        FROM public.cartoes_faturas
        WHERE empresa_id = p_empresa_id
          AND status = 'aberta'
          AND vencimento >= CURRENT_DATE
        ORDER BY vencimento
        LIMIT 10
      ) v
    )
  )
  INTO result;

  RETURN result;
END;
$$;