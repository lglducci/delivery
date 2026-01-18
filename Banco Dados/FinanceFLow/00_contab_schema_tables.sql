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
  id              	  BIGSERIAL PRIMARY KEY,
  codigo            	VARCHAR(30) NOT NULL UNIQUE,
  empresa_id      	bigint                  NOT NULL REFERENCES public.empresas(id),
  nome         	VARCHAR(120) NOT NULL,
  tipo              	VARCHAR(20)   NOT NULL CHECK (tipo IN ('ATIVO','PASSIVO','PL','RECEITA','CUSTO','DESPESA')),
  natureza        	CHAR(1)             NOT NULL CHECK (natureza IN ('D','C')),
  nivel           	INT                      NOT NULL DEFAULT 1,
  conta_pai_id   	BIGINT                NULL REFERENCES contab.contas(id) ON DELETE SET NULL,
  analitica       	BOOLEAN           NOT NULL DEFAULT TRUE,
  sistema                     BOOLEAN           NOT NULL DEFAULT  FALSE
);

 

-----------------------------------------------------------
-- 3) DIÁRIO
-----------------------------------------------------------
  
drop table  contab.diario cascade ;

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
  status              text  NOT NULL DEFAULT 'rascunho', 
   outros         	  JSONB,
   lote_id  uuid    
); 
 
ALTER TABLE contab.diario
ADD CONSTRAINT ck_diario_status
CHECK (status IN ('rascunho', 'confirmado', 'processado', 'estornado','manual'));



-----------------------------------------------------------
-- 4) MODELOS
-----------------------------------------------------------
CREATE TABLE contab.modelos (
  id          		BIGSERIAL PRIMARY KEY,
  empresa_id  	     bigint NOT NULL REFERENCES public.empresas(id),
  codigo      	     VARCHAR(40) NOT NULL UNIQUE,
  nome       	     VARCHAR(120) NOT NULL,
  ativo      		     BOOLEAN NOT NULL DEFAULT TRUE,
  sistema                          BOOLEAN           NOT NULL DEFAULT  FALSE
 codigo_estorno           TEXT  NULL, 
tipo_automacao           TEXT NULL  
);

ALTER TABLE contab.modelos
ADD COLUMN modelo_prazo_id BIGINT
REFERENCES contab.modelos(id);


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
  obrigatorio    	BOOLEAN NOT NULL DEFAULT TRUE,
 codigo_estorno       TEXT null,
perna_fixa BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_modelos_linhas_unq
ON contab.modelos_linhas (empresa_id, modelo_id, conta_id, dc);
 

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
  origem                TEXT   default null );

 ALTER TABLE contab.lancamentos
ADD COLUMN lote_id BIGINT;


CREATE SEQUENCE contab.lote_id_seq
START 1;

 ALTER TABLE contab.lancamentos
ALTER COLUMN lote_id SET DEFAULT nextval('contab.lote_id_seq');


  
/*drop table contab.diario_staging cascade 
CREATE TABLE contab.diario_staging (
  id BIGSERIAL PRIMARY KEY, 
  linha  int   null , 
  empresa_id bigint NOT NULL,
  data_mov date, 
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
*/
 

 
drop table contab.diario_staging cascade 

CREATE TABLE contab.diario_staging (
  id BIGSERIAL PRIMARY KEY, 
  linha  int   null , 
  empresa_id bigint NOT NULL,
  data_mov date, 
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
  modelo_codigo  text, 
  status varchar(20) DEFAULT 'pendente',
  lote_id  uuid,
  validacao text DEFAULT NULL, 
  referencia_id bigint
);


drop table  contab.eventos cascade;

 CREATE TABLE contab.eventos (
    codigo text PRIMARY KEY,
    descricao text NOT NULL,
    modelo_codigo text NOT NULL,   -- qual modelo contábil usa
    origem text NOT NULL,          -- TRANSACAO | PAGAR | RECEBER | CARTAO | SISTEMA
    ativo boolean DEFAULT true
);


CREATE TABLE contab.controle_fechamento (
  empresa_id bigint PRIMARY KEY,
  ultimo_dia_processado date NOT NULL
);


CREATE TABLE IF NOT EXISTS contab.saldos_iniciais (
  empresa_id  BIGINT NOT NULL,
  conta_id    BIGINT NOT NULL REFERENCES contab.contas(id),
  data_base   DATE   NOT NULL DEFAULT DATE '2000-01-01',
  saldo       NUMERIC(14,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (empresa_id, conta_id)
);

CREATE TABLE contab.conta_classificacao (
    id BIGSERIAL PRIMARY KEY,

    empresa_id BIGINT NOT NULL,
    
    conta_codigo TEXT NOT NULL,
    -- prefixo da conta contábil (ex: 4.1, 6.3, 5.2)

    tipo_dre TEXT NOT NULL,
    -- RECEITA_BRUTA | DED_RECEITA | CMV_CSP | DESPESA_FIXA | DESPESA_VARIAVEL

    fixo_variavel TEXT,
    -- FIXO | VARIAVEL | NULL (para receitas)

    natureza CHAR(1) NOT NULL,
    -- D = Débito | C = Crédito

    tipo_contab TEXT NOT NULL,
    -- RECEITA | CUSTO | DESPESA

    nome TEXT NOT NULL,

    criado_em TIMESTAMP DEFAULT now(),

    CONSTRAINT chk_natureza_conta_classificacao
        CHECK (natureza IN ('D','C')),

    CONSTRAINT chk_fixo_variavel_conta_classificacao
        CHECK (fixo_variavel IN ('FIXO','VARIAVEL') OR fixo_variavel IS NULL)
);

 
 INSERT INTO contab.conta_classificacao
(
  empresa_id,
  conta_codigo,
  tipo_dre,
  fixo_variavel,
  natureza,
  tipo_contab,
  nome
)
VALUES
  (1, '4.1',   'RECEITA_BRUTA',   NULL,        'C', 'RECEITA', 'Vendas'),
  (1, '4.1.9', 'DED_RECEITA',     NULL,        'D', 'RECEITA', 'Impostos s/ venda'),

  (1, '5.1',   'CMV_CSP',         'VARIAVEL',  'D', 'CUSTO',   'CMV Bebidas'),
  (1, '5.2',   'CMV_CSP',         'VARIAVEL',  'D', 'CUSTO',   'CMV Refeições'),

  (1, '6.1',   'DESPESA_FIXA',    'FIXO',      'D', 'DESPESA','Pessoal'),
  (1, '6.3',   'DESPESA_FIXA',    'FIXO',      'D', 'DESPESA','Administrativo'),
  (1, '6.4',   'DESPESA_VARIAVEL','VARIAVEL',  'D', 'DESPESA','Marketing');



INSERT INTO contab.eventos (codigo, descricao, modelo_codigo, origem) VALUES
('CRIA_PAGAR', 'Criação de conta a pagar (provisão)', 'PROV_PAGAR', 'PAGAR'),
('PAGAR', 'Pagamento de conta a pagar', 'PG_PAGAR', 'PAGAR'),
('ESTORNO_PAGAR', 'Estorno de pagamento', 'EST_PAGAR', 'PAGAR'),
('CANCELA_PAGAR', 'Cancelamento da conta a pagar', 'CANC_PAGAR', 'PAGAR');


INSERT INTO contab.eventos (codigo, descricao, modelo_codigo, origem) VALUES
('CRIA_RECEBER', 'Criação de conta a receber (provisão)', 'PROV_RECEBER', 'RECEBER'),
('RECEBER', 'Recebimento de conta a receber', 'PG_RECEBER', 'RECEBER'),
('ESTORNO_RECEBER', 'Estorno de recebimento', 'EST_RECEBER', 'RECEBER'),
('CANCELA_RECEBER', 'Cancelamento da conta a receber', 'CANC_RECEBER', 'RECEBER');


INSERT INTO contab.eventos (codigo, descricao, modelo_codigo, origem) VALUES
('COMPRA_CARTAO', 'Compra no cartão de crédito', 'CARTAO_COMPRA', 'CARTAO'),
('ESTORNO_CARTAO', 'Estorno de compra no cartão', 'CARTAO_ESTORNO', 'CARTAO'),
('PROVISAO_FATURA_CARTAO', 'Provisão da fatura do cartão', 'CARTAO_PROVISAO', 'CARTAO'),
('PAGAMENTO_FATURA_CARTAO', 'Pagamento da fatura do cartão', 'CARTAO_PAGAMENTO', 'TRANSACAO');


INSERT INTO contab.eventos (codigo, descricao, modelo_codigo, origem) VALUES
('RECEBIMENTO_PIX', 'Recebimento via PIX', 'RECEITA_PIX', 'TRANSACAO'),
('RECEBIMENTO_CARTAO', 'Recebimento via cartão', 'RECEITA_CARTAO', 'TRANSACAO'),
('VENDAS', 'Venda à vista', 'VENDA_VISTA', 'TRANSACAO'),
('COMPRA_INSUMO_VISTA', 'Compra de insumo à vista', 'COMPRA_VISTA', 'TRANSACAO'),
('TRANSFERENCIA_ENTRE_CONTAS', 'Transferência entre contas', 'TRANSFERENCIA', 'TRANSACAO'),
('AJUSTE_SALDO_ENTRADA', 'Ajuste positivo de saldo', 'AJUSTE_ENTRADA', 'TRANSACAO'),
('AJUSTE_SALDO_SAIDA', 'Ajuste negativo de saldo', 'AJUSTE_SAIDA', 'TRANSACAO');
