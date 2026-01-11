 -- Empresa 1
insert into contab.tributos (empresa_id, codigo, nome)
values
  (1, 'ICMS', 'ICMS'),
  (1, 'ISS',  'ISS'),
  (1, 'PIS',  'PIS'),
  (1, 'COFINS','COFINS')
on conflict (empresa_id, codigo) do nothing;

-- Pega IDs
-- (você pode rodar isso pra conferir)
-- select * from contab.tributos where empresa_id=1;

-- Vigências (exemplo)
insert into contab.tributos_vigencias (empresa_id, tributo_id, vigencia_ini, vigencia_fim, aliquota)
select
  1,
  t.id,
  date '2025-01-01',
  null,
  case t.codigo
    when 'ICMS' then 0.180000
    when 'ISS' then 0.050000
    when 'PIS' then 0.006500
    when 'COFINS' then 0.030000
    else 0.000000
  end
from contab.tributos t
where t.empresa_id=1
on conflict do nothing;

-- Regras contábeis (EXEMPLO: troque as contas pelos seus IDs)
-- Ex: Débito: Despesa de Tributos (ou Resultado) | Crédito: Tributos a Recolher (Passivo)
insert into contab.tributos_regras_contabeis (
  empresa_id, tributo_id, vigencia_id, conta_debito_id, conta_credito_id, ativo
)
select
  1,
  t.id,
  v.id,
  1001,   -- <-- TROQUE: conta débito
  2001,   -- <-- TROQUE: conta crédito
  true
from contab.tributos t
join contab.tributos_vigencias v on v.tributo_id = t.id and v.empresa_id = 1
where t.empresa_id=1
on conflict do nothing;
