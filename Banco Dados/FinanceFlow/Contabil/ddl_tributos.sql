 -- =========================================================
-- SCHEMA
-- =========================================================
create schema if not exists contab;

-- =========================================================
-- 1) TRIBUTOS (cadastro)
-- =========================================================
create table if not exists contab.tributos (
  id            bigserial primary key,
  empresa_id    bigint not null,
  codigo        text not null,          -- ex: ICMS, ISS, PIS, COFINS
  nome          text not null,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  unique (empresa_id, codigo)
);

-- =========================================================
-- 2) VIGÊNCIAS (aliquota por período)
-- =========================================================
create table if not exists contab.tributos_vigencias (
  id            bigserial primary key,
  empresa_id    bigint not null,
  tributo_id    bigint not null references contab.tributos(id) on delete cascade,
  vigencia_ini  date not null,
  vigencia_fim  date null,              -- null = vigente até hoje
  aliquota      numeric(9,6) not null,  -- 0.180000 = 18%
  criado_em     timestamptz not null default now(),
  constraint ck_vigencia_intervalo
    check (vigencia_fim is null or vigencia_fim >= vigencia_ini)
);

create index if not exists ix_tributos_vigencias_busca
  on contab.tributos_vigencias (empresa_id, tributo_id, vigencia_ini, vigencia_fim);

-- =========================================================
-- 3) REGRAS CONTÁBEIS (para virar partida dobrada)
--    Uma regra diz: ao apurar esse tributo, debita X e credita Y.
-- =========================================================
create table if not exists contab.tributos_regras_contabeis (
  id              bigserial primary key,
  empresa_id      bigint not null,
  tributo_id      bigint not null references contab.tributos(id) on delete cascade,

  -- opcional: atrelar a regra a uma vigência específica
  vigencia_id     bigint null references contab.tributos_vigencias(id) on delete set null,

  -- você vai ligar isso ao seu plano de contas (contab.contas)
  conta_debito_id bigint not null,
  conta_credito_id bigint not null,

  ativo           boolean not null default true,
  criado_em       timestamptz not null default now(),

  constraint ck_dc_diferentes check (conta_debito_id <> conta_credito_id)
);

create index if not exists ix_tributos_regras_busca
  on contab.tributos_regras_contabeis (empresa_id, tributo_id, ativo);

-- =========================================================
-- 4) APURAÇÃO (cabeçalho do período)
-- =========================================================
create table if not exists contab.tributos_apuracoes (
  id            bigserial primary key,
  empresa_id    bigint not null,
  periodo_ini   date not null,
  periodo_fim   date not null,
  status        text not null default 'ABERTA',  -- ABERTA | FECHADA | CANCELADA
  criado_em     timestamptz not null default now(),

  constraint ck_periodo check (periodo_fim >= periodo_ini)
);

create index if not exists ix_tributos_apuracoes_periodo
  on contab.tributos_apuracoes (empresa_id, periodo_ini, periodo_fim);

-- =========================================================
-- 5) ITENS DA APURAÇÃO (valores apurados por tributo)
-- =========================================================
create table if not exists contab.tributos_apuracoes_itens (
  id              bigserial primary key,
  apuracao_id     bigint not null references contab.tributos_apuracoes(id) on delete cascade,
  empresa_id      bigint not null,
  tributo_id      bigint not null references contab.tributos(id) on delete restrict,
  vigencia_id     bigint null references contab.tributos_vigencias(id) on delete set null,

  base_calculo    numeric(14,2) not null default 0,
  aliquota        numeric(9,6) not null default 0,
  valor_apurado   numeric(14,2) not null default 0,

  -- contas resolvidas na hora (pra lançamento)
  conta_debito_id  bigint not null,
  conta_credito_id bigint not null,

  historico       text not null default '',
  criado_em       timestamptz not null default now(),

  constraint ck_valores_nonneg check (base_calculo >= 0 and valor_apurado >= 0),
  constraint ck_itens_dc_diferentes check (conta_debito_id <> conta_credito_id)
);

create index if not exists ix_apuracao_itens_apuracao
  on contab.tributos_apuracoes_itens (apuracao_id);

create index if not exists ix_apuracao_itens_busca
  on contab.tributos_apuracoes_itens (empresa_id, tributo_id);





CREATE TABLE contab.tributo_apuracao (
    id BIGSERIAL PRIMARY KEY,

    empresa_id   BIGINT NOT NULL,
    tributo_id   BIGINT NOT NULL,

    data_ini     DATE NOT NULL,
    data_fim     DATE NOT NULL,

    base_calculo NUMERIC(14,2) NOT NULL,
    aliquota     NUMERIC(7,4)  NOT NULL,
    valor_apurado NUMERIC(14,2) NOT NULL,

    status       TEXT NOT NULL DEFAULT 'APURADO',

    criado_em    TIMESTAMP NOT NULL DEFAULT now()
);





CREATE TABLE contab.tributo_aliquotas (
    id           BIGSERIAL PRIMARY KEY,
    empresa_id   BIGINT NOT NULL,
    tributo_id   BIGINT NOT NULL,
    aliquota     NUMERIC(7,4) NOT NULL,
    data_ini     DATE NOT NULL,
    data_fim     DATE,
    ativo        BOOLEAN DEFAULT TRUE,

    CONSTRAINT fk_tributo
      FOREIGN KEY (tributo_id)
      REFERENCES contab.tributos(id)
);



CREATE TABLE contab.tributo_obrigacoes (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL,
    tributo_id BIGINT NOT NULL,

    data_ini DATE NOT NULL,
    data_fim DATE NOT NULL,

    valor NUMERIC(14,2) NOT NULL,
    vencimento DATE NOT NULL,

    origem_apuracao_id BIGINT NOT NULL,

    status TEXT NOT NULL DEFAULT 'ABERTA', 
    -- ABERTA | PAGA | CANCELADA

    criada_em TIMESTAMP NOT NULL DEFAULT now()
);



ALTER TABLE contab.tributo_apuracao
ADD COLUMN obrigacao_gerada BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN obrigacao_id BIGINT NULL,
ADD COLUMN data_apuracao TIMESTAMP DEFAULT now(),
ADD COLUMN status TEXT DEFAULT 'APURADO';

