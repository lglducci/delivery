 drop table if exists public.conciliacao_financeira cascade;

create table public.conciliacao_financeira (
    id bigserial primary key,
    empresa_id bigint not null,
    conta_financeira_id bigint not null,
    data_mov date not null,
    historico text not null,
    valor numeric(14,2) not null,
    tipo varchar(10),
    forma varchar(30),
    classificacao varchar(50),
    categoria_id bigint,
    fornecedor_id bigint,
    modelo_codigo varchar(50),
    tipo_destino varchar(30),
    destino_id bigint 
);

alter table public.conciliacao_financeira
add column if not exists tipo_evento varchar(30);

alter table public.conciliacao_financeira
add column if not exists transacao_id bigint,
add column if not exists pagar_id bigint,
add column if not exists receber_id bigint,
add column if not exists fatura_id bigint;

 
 

alter table public.conciliacao_financeira
 
add column if not exists match_score numeric(5,2),
add column if not exists match_criterio text;

CREATE SEQUENCE IF NOT EXISTS public.conciliacao_lote_seq;

ALTER TABLE public.conciliacao_financeira
ADD COLUMN IF NOT EXISTS lote_conciliacao_id bigint;

alter table public.conciliacao_financeira
add constraint fk_conciliacao_conta_financeira
foreign key (conta_financeira_id)
references public.contas_financeiras(id);

create index idx_conciliacao_empresa
on public.conciliacao_financeira(empresa_id);

create index idx_conciliacao_conta_financeira
on public.conciliacao_financeira(conta_financeira_id);

create index idx_conciliacao_data
on public.conciliacao_financeira(data_mov);


 

ALTER TABLE public.conciliacao_financeira
ADD COLUMN IF NOT EXISTS chave_importacao text;

 

alter table public.conciliacao_financeira
add column if not exists importar boolean default true,
add column if not exists status_conciliacao varchar(30),
add column if not exists mensagem_conciliacao text;

// ajustando a criacao da conta na conciliacao 
ALTER TABLE public.conciliacao_financeira
ADD COLUMN IF NOT EXISTS conta_id integer;

ALTER TABLE public.conciliacao_financeira
ADD CONSTRAINT conciliacao_financeira_conta_id_fkey
FOREIGN KEY (conta_id)
REFERENCES contab.contas(id)
ON DELETE SET NULL;
// fim implantacao 



drop table  public.lote_conciliacao;

 CREATE TABLE public.lote_conciliacao (
  id BIGSERIAL PRIMARY KEY,
  empresa_id BIGINT NOT NULL,
  conta_financeira_id BIGINT NOT NULL,

  data_importacao TIMESTAMP DEFAULT now(),

  data_ini DATE   NULL,
  data_fim DATE   NULL,

  status VARCHAR(30) DEFAULT 'aberto',
  total_linhas INTEGER DEFAULT 0,
  total_valor NUMERIC(15,2) DEFAULT 0,

  criado_em TIMESTAMP DEFAULT now()
);


ALTER TABLE public.conciliacao_financeira
ADD CONSTRAINT fk_conciliacao_lote
FOREIGN KEY (lote_conciliacao_id)
REFERENCES public.lote_conciliacao(id);


CREATE TABLE IF NOT EXISTS public.transferencia_contas (
  id bigserial PRIMARY KEY,
  empresa_id bigint NOT NULL,
  data_mov date NOT NULL,
  origem_id bigint NOT NULL,
  destino_id bigint NOT NULL,
  valor numeric(15,2) NOT NULL CHECK (valor > 0),
  historico text,
  lote_id bigint,
  origem_registro text DEFAULT 'web',
  conciliacao_id bigint,
  chave text,
  duplicada boolean DEFAULT false,
  criado_em timestamptz DEFAULT now()
);

  
CREATE INDEX IF NOT EXISTS idx_transferencia_contas_empresa
ON public.transferencia_contas (empresa_id);

CREATE INDEX IF NOT EXISTS idx_transferencia_contas_chave
ON public.transferencia_contas (empresa_id, chave);

CREATE INDEX IF NOT EXISTS idx_transferencia_contas_lote
ON public.transferencia_contas (empresa_id, lote_id);