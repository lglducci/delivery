 BEGIN;

CREATE SCHEMA IF NOT EXISTS contab;
SET search_path = contab, public;

-- DROP (idempotente)
 
DROP TABLE IF EXISTS contab.modelos_linhas CASCADE;
DROP TABLE IF EXISTS contab.modelos CASCADE; 
DROP TABLE IF EXISTS contab.contas CASCADE;
DROP TABLE IF EXISTS contab.vinculos_modelo CASCADE;

-----------------------------------------------------------
-- 1) PLANO DE CONTAS
-----------------------------------------------------------
CREATE TABLE contab.contas (
  id                BIGSERIAL PRIMARY KEY,
  codigo            VARCHAR(30) NOT NULL UNIQUE,
  empresa_id      	bigint NOT NULL REFERENCES public.empresas(id),
  nome         	    VARCHAR(120) NOT NULL,
  tipo              VARCHAR(20)  NOT NULL CHECK (tipo IN ('ATIVO','PASSIVO','PL','RECEITA','CUSTO','DESPESA')),
  natureza        	CHAR(1)      NOT NULL CHECK (natureza IN ('D','C')),
  nivel           	INT          NOT NULL DEFAULT 1,
  conta_pai_id   	BIGINT       NULL REFERENCES contab.contas(id) ON DELETE SET NULL,
  analitica       	BOOLEAN      NOT NULL DEFAULT TRUE
);

-----------------------------------------------------------
-- 2) PARCEIROS
-----------------------------------------------------------
CREATE TABLE contab.parceiros (
  id          		BIGSERIAL PRIMARY KEY,
  empresa_id      	bigint NOT NULL REFERENCES public.empresas(id),
  nome          	VARCHAR(160) NOT NULL,
  tipo       		VARCHAR(20)  NOT NULL DEFAULT 'OUTRO' 
             		CHECK (tipo IN ('CLIENTE','FORNECEDOR','OUTRO'))
);

-----------------------------------------------------------
-- 3) DIÁRIO
-----------------------------------------------------------

 drop table   contab.diario cascade;

CREATE TABLE contab.diario (
  id                  BIGSERIAL PRIMARY KEY,
  empresa_id      	  bigint NOT NULL REFERENCES public.empresas(id),
  data_mov        	  DATE NOT NULL,
  modelo_codigo   	  VARCHAR(40) NOT NULL,
  historico     	  TEXT NOT NULL,
  doc_ref        	  VARCHAR(60),
  parceiro_id   	  BIGINT NULL REFERENCES public.pessoa(id) ON DELETE SET NULL,
  data_vencto     	  DATE,
  valor_total     	  NUMERIC(14,2) NOT NULL DEFAULT 0,
  valor_custo    	  NUMERIC(14,2) NOT NULL DEFAULT 0,
  valor_imposto  	  NUMERIC(14,2) NOT NULL DEFAULT 0,
  desconto        	  NUMERIC(14,2) NOT NULL DEFAULT 0,
  status              text,
  outros         	  JSONB,
   lote_id  uuid    
);



ALTER TABLE contab.diario
ADD COLUMN status text NOT NULL DEFAULT 'rascunho';

ALTER TABLE contab.diario
ADD CONSTRAINT ck_diario_status
CHECK (status IN ('rascunho', 'confirmado', 'processado', 'estornado'));



-----------------------------------------------------------
-- 4) MODELOS
-----------------------------------------------------------
CREATE TABLE contab.modelos (
  id          		BIGSERIAL PRIMARY KEY,
  empresa_id  	    bigint NOT NULL REFERENCES public.empresas(id),
  codigo      	    VARCHAR(40) NOT NULL UNIQUE,
  nome       	    VARCHAR(120) NOT NULL,
  ativo      		BOOLEAN NOT NULL DEFAULT TRUE
);

-----------------------------------------------------------
-- 5) MODELOS LINHAS
-----------------------------------------------------------
CREATE TABLE contab.modelos_linhas (
  id             	BIGSERIAL PRIMARY KEY,
  modelo_id      	BIGINT NOT NULL REFERENCES contab.modelos(id) ON DELETE CASCADE,
  empresa_id  	    bigint NOT NULL REFERENCES public.empresas(id),
  ordem         	INT NOT NULL DEFAULT 1,
  conta_id       	BIGINT NOT NULL REFERENCES contab.contas(id),
  dc           		CHAR(1) NOT NULL CHECK (dc IN ('D','C')),
  fonte_valor   	VARCHAR(30) NOT NULL,
  valor_fixo     	NUMERIC(14,2),
  fator          	NUMERIC(10,4) NOT NULL DEFAULT 1.0,
  obrigatorio    	BOOLEAN NOT NULL DEFAULT TRUE
);

-----------------------------------------------------------
-- 6) LANÇAMENTOS
-----------------------------------------------------------
CREATE TABLE contab.lancamentos (
  id          		BIGSERIAL PRIMARY KEY,
  diario_id     	BIGINT NOT NULL REFERENCES contab.diario(id) ON DELETE CASCADE,
  empresa_id    	bigint NOT NULL REFERENCES public.empresas(id),
  data_mov      	DATE NOT NULL,
  conta_id      	BIGINT NOT NULL REFERENCES contab.contas(id),
  historico     	TEXT NOT NULL,
  debito      	    NUMERIC(14,2) NOT NULL DEFAULT 0,
  credito      	    NUMERIC(14,2) NOT NULL DEFAULT 0,
  modelo_id         BIGINT REFERENCES contab.modelos(id) ON DELETE SET NULL,
  criado_em         TIMESTAMP DEFAULT now(),
  tipo_automacao    TEXT  CHECK (tipo IN ('FINANCEIRO_PADRAO','NAO_FINANCEIR')),
  CHECK ((debito > 0 AND credito = 0) OR (credito > 0 AND debito = 0))
);

-----------------------------------------------------------
-- 7) VÍNCULOS MODELO (obrigatório)
-----------------------------------------------------------
CREATE TABLE contab.vinculos_modelo (
  id 		    BIGSERIAL PRIMARY KEY,
  empresa_id 	bigint NOT NULL REFERENCES public.empresas(id),
  origem 		text NOT NULL CHECK (
  origem IN 
    ('categoria','pagar','receber','cartao','fatura','transaction')
  ),
  origem_id	    bigint NOT NULL,
  evento		text NOT NULL,
  modelo_id 	bigint NOT NULL REFERENCES contab.modelos(id),
  ativo 		boolean NOT NULL DEFAULT true
);

CREATE INDEX vinculo_idx ON contab.vinculos_modelo (empresa_id, origem, origem_id);



 

  
drop table contab.diario_staging cascade 
CREATE TABLE contab.diario_staging (
  id BIGSERIAL PRIMARY KEY, 
  linha  int   null , 
  empresa_id bigint NOT NULL,
  data_mov date,
  modelo_codigo varchar(40),
  historico text,
  doc_ref varchar(60),
  cnpj  varchar(20) not null ,
  data_vencto date,
  parceiro_id int,
  valor_total numeric(14,2),
  valor_custo numeric(14,2),
  valor_imposto numeric(14,2),
  desconto numeric(14,2),
  outros jsonb,
  status varchar(20) DEFAULT 'pendente',
  lote_id  uuid,
  validacao text DEFAULT NULL
);

 

COMMIT;
