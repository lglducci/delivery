 create or replace function public.ff_cartoes_com_limite(
  p_empresa_id bigint
)
returns table (
  id bigint,
  empresa_id bigint,
  nome text,
  nomecartao text,
  numero text,
  bandeira text,
  limite_total numeric,
  fechamento_dia integer,
  vencimento_dia integer,
  status text,
  vencimento text,
  criado_em timestamp without time zone,

  total_em_aberto numeric,
  limite_disponivel numeric,

  proxima_fatura_id bigint,
  proxima_fatura_mes date,
  proxima_fatura_vencimento date,
  proxima_fatura_valor numeric,
  proxima_fatura_status text
)
language sql
stable
as $$
  select
    c.id,
    c.empresa_id,
    c.nome,
    c.nomecartao,
    c.numero,
    c.bandeira,
    coalesce(c.limite_total, 0) as limite_total,
    c.fechamento_dia,
    c.vencimento_dia,
    c.status,
    c.vencimento,
    c.criado_em,

    coalesce(fat.total_em_aberto, 0) as total_em_aberto,
    coalesce(c.limite_total, 0) - coalesce(fat.total_em_aberto, 0) as limite_disponivel,

    prox.id as proxima_fatura_id,
    prox.mes_referencia as proxima_fatura_mes,
    prox.vencimento as proxima_fatura_vencimento,
    coalesce(prox.valor_total, 0) as proxima_fatura_valor,
    prox.status as proxima_fatura_status

  from public.cartoes c

  left join lateral (
    select
      sum(coalesce(f.valor_total, 0)) as total_em_aberto
    from public.cartoes_faturas f
    where f.empresa_id = c.empresa_id
      and f.cartao_id = c.id
      and f.status in ('aberta', 'fechada')
  ) fat on true

  left join lateral (
    select
      f.id,
      f.mes_referencia,
      f.vencimento,
      f.valor_total,
      f.status
    from public.cartoes_faturas f
    where f.empresa_id = c.empresa_id
      and f.cartao_id = c.id
      and f.status in ('aberta', 'fechada')
    order by
      f.vencimento nulls last,
      f.mes_referencia,
      f.id
    limit 1
  ) prox on true

  where c.empresa_id = p_empresa_id
  order by c.nome;
$$;

