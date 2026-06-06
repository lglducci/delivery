 create table public.contas_recorrentes (
  id bigserial primary key,
  empresa_id bigint not null,

  descricao text not null,

  fornecedor_id bigint null, 
   conta_id bigint null,

  dia_vencimento integer not null,

  tipo_valor text not null default 'VARIAVEL',
  valor_padrao numeric(12,2) null,

  ativo boolean not null default true,

  criado_em timestamp default now()
);


DROP TABLE IF EXISTS public.contas_recorrentes_geradas;

CREATE TABLE public.contas_recorrentes_geradas (
  id bigserial PRIMARY KEY,

  empresa_id bigint NOT NULL,
  recorrente_id bigint NOT NULL,

  competencia date NOT NULL,
  conta_id bigint NULL,
  despesa_id bigint NULL,
  descricao    text ,
  data_pagamento date NOT NULL,
  valor_gerado numeric(12,2) NULL,

  criado_em timestamp DEFAULT now(),

  UNIQUE (empresa_id, recorrente_id, competencia)
);

CREATE INDEX idx_contas_recorrentes_geradas_empresa
ON public.contas_recorrentes_geradas (empresa_id);

CREATE INDEX idx_contas_recorrentes_geradas_recorrente
ON public.contas_recorrentes_geradas (recorrente_id);

CREATE INDEX idx_contas_recorrentes_geradas_competencia
ON public.contas_recorrentes_geradas (empresa_id, competencia);