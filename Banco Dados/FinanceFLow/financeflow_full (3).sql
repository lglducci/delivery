   ---------------------------------------------------
-- FINANCE-FLOW – SCRIPT COMPLETO REVISADO
---------------------------------------------------

-- ORDEM IMPORTANTE: CRIAR BASE E TABELAS MESTRES PRIMEIRO
---------------------------------------------------

DROP TABLE IF EXISTS extrato_importado CASCADE;
DROP TABLE IF EXISTS cartoes_transacoes CASCADE;
DROP TABLE IF EXISTS cartoes_faturas CASCADE;
DROP TABLE IF EXISTS cartoes CASCADE;

DROP TABLE IF EXISTS contas_a_receber CASCADE;
DROP TABLE IF EXISTS contas_a_pagar CASCADE;

DROP TABLE IF EXISTS transacoes CASCADE;
DROP TABLE IF EXISTS categorias_gerenciais CASCADE;

DROP TABLE IF EXISTS contas_financeiras CASCADE;

DROP TABLE IF EXISTS usuario_empresa CASCADE;
DROP TABLE IF EXISTS pessoa CASCADE;
DROP TABLE IF EXISTS usuarios CASCADE;
DROP TABLE IF EXISTS empresas CASCADE;
     ---------------------------------------------------
-- FINANCE-FLOW – SCRIPT COMPLETO REVISADO
---------------------------------------------------

-- ORDEM IMPORTANTE: CRIAR BASE E TABELAS MESTRES PRIMEIRO
---------------------------------------------------
 


---------------------------------------------------
-- 1. USUÁRIOS
---------------------------------------------------
CREATE TABLE usuarios (
    id BIGSERIAL PRIMARY KEY,
    nome TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    senha_hash TEXT NOT NULL,
    criado_em TIMESTAMP DEFAULT now()
);


---------------------------------------------------
-- 2. EMPRESAS
---------------------------------------------------
CREATE TABLE empresas (
    id BIGSERIAL PRIMARY KEY,
    nome TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('PF','MEI','PJ')),
    documento TEXT,
    criado_em TIMESTAMP DEFAULT now()
);


---------------------------------------------------
-- 3. USUARIO x EMPRESA
---------------------------------------------------
CREATE TABLE usuario_empresa (
    id BIGSERIAL PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id),
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    role TEXT DEFAULT 'admin',
    UNIQUE (usuario_id, empresa_id),
    escolha BOOLEAN DEFAULT false 
);


---------------------------------------------------
-- 4. CONTAS FINANCEIRAS
---------------------------------------------------
 



CREATE TABLE contas_financeiras (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    banco TEXT,
    tipo TEXT NOT NULL CHECK (tipo IN ('corrente','poupanca','carteira','caixa')),
    saldo_inicial NUMERIC(12,2) DEFAULT 0,
    criado_em TIMESTAMP DEFAULT now(),
     padrao boolean DEFAULT false,
     nro_banco text,
     agencia text,
     conta text,
     conjunta boolean DEFAULT false,
     juridica boolean DEFAULT false  ,
     contabil_id BIGINT  not null     
);

 
drop table categorias_gerenciais 
---------------------------------------------------
-- 5. CATEGORIAS GERENCIAIS
---------------------------------------------------
CREATE TABLE categorias_gerenciais (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    grupo_contabil TEXT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('entrada','saida')) 
);


---------------------------------------------------
-- 6. PESSOA (Cliente / Fornecedor)
---------------------------------------------------
CREATE TABLE pessoa (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('cliente','fornecedor','ambos')),
    nome VARCHAR(200) NOT NULL, 
    cpf_cnpj VARCHAR(20) not null,
    rg_ie VARCHAR(20), 
    telefone VARCHAR(20),
    whatsapp VARCHAR(20),
    email VARCHAR(200), 
    endereco TEXT,
    bairro VARCHAR(100),
    cidade VARCHAR(100),
    estado VARCHAR(2),
    cep VARCHAR(20), 
    obs TEXT,
    criado_em TIMESTAMP DEFAULT now(),
    validado  boolean DEFAULT true
);


---------------------------------------------------
-- 7. TRANSACOES (movimentação financeira)
---------------------------------------------------
CREATE TABLE transacoes (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    conta_id BIGINT NOT NULL REFERENCES contas_financeiras(id),
    categoria_id BIGINT REFERENCES categorias_gerenciais(id),
    tipo TEXT NOT NULL CHECK (tipo IN ('entrada','saida')),
    valor NUMERIC(12,2) NOT NULL,
    descricao TEXT,
    data_movimento DATE NOT NULL,
    origem TEXT DEFAULT 'manual',
    criado_em TIMESTAMP DEFAULT now(),
    pagar_id BIGINT,
    receber_id BIGINT,
    fatura_id BIGINT
);

 alter table public.transacoes add column evento_codigo text;

---------------------------------------------------
-- 8. CONTAS A PAGAR
---------------------------------------------------
CREATE TABLE contas_a_pagar (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    descricao TEXT NOT NULL,
    valor NUMERIC(12,2) NOT NULL,
    vencimento DATE NOT NULL,
    categoria_id BIGINT REFERENCES categorias_gerenciais(id),
    fornecedor_id BIGINT REFERENCES pessoa(id),
    parcelas INT DEFAULT 1,
    parcela_num INT DEFAULT 1,
    status TEXT NOT NULL CHECK (status IN ('aberto','pago')),
    criado_em TIMESTAMP DEFAULT now(),
    lote_id BIGINT,
    doc_ref  text null,
   evento_codigo text default 'PAGAR'
);

CREATE SEQUENCE IF NOT EXISTS contas_a_pagar_lote_seq;
ALTER TABLE contas_a_pagar ALTER COLUMN lote_id SET DEFAULT nextval('contas_a_pagar_lote_seq');


---------------------------------------------------
-- 9. CONTAS A RECEBER
---------------------------------------------------
CREATE TABLE contas_a_receber (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    descricao TEXT NOT NULL,
    valor NUMERIC(12,2) NOT NULL,
    vencimento DATE NOT NULL,
    categoria_id BIGINT REFERENCES categorias_gerenciais(id),
    fornecedor_id BIGINT REFERENCES pessoa(id),
    parcelas INT DEFAULT 1,
    parcela_num INT DEFAULT 1,
    status TEXT NOT NULL CHECK (status IN ('aberto','recebido')),
    criado_em TIMESTAMP DEFAULT now(),
    lote_id BIGINT,
     evento_codigo text default 'RECEBER',
    doc_ref  text 
);

CREATE SEQUENCE IF NOT EXISTS contas_a_receber_lote_seq;
ALTER TABLE contas_a_receber ALTER COLUMN lote_id SET DEFAULT nextval('contas_a_receber_lote_seq');


---------------------------------------------------
-- 10. CARTÕES
---------------------------------------------------
  drop table cartoes cascade 
 
 
 CREATE TABLE cartoes (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
     nomecartao TEXT NOT NULL,
    numero   text not null, 
    bandeira TEXT,
    limite_total NUMERIC(12,2),
    fechamento_dia INT,
    vencimento_dia INT,
    status    text not null, 
    vencimento text not null ,
    criado_em TIMESTAMP DEFAULT now()
);


CREATE TABLE cartoes_compras (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    cartao_id BIGINT NOT NULL REFERENCES cartoes(id),

    descricao TEXT NOT NULL,
    valor_total NUMERIC(12,2) NOT NULL,
    parcelas INT NOT NULL,

    data_compra DATE NOT NULL,
	evento_codigo text default  'COMPRA_CARTAO',
    criado_em TIMESTAMP DEFAULT now()
);

ALTER TABLE cartoes_compras
ADD COLUMN conta_contabil_id BIGINT
REFERENCES contab.contas(id);
 CREATE INDEX idx_cartoes_transacoes_compra
ON cartoes_transacoes (empresa_id, compra_id);




---------------------------------------------------
-- 11. FATURAS DO CARTÃO
---------------------------------------------------
 
  CREATE TABLE cartoes_faturas (
    id BIGSERIAL PRIMARY KEY,
    cartao_id BIGINT NOT NULL REFERENCES cartoes(id),
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    mes_referencia DATE NOT NULL,
    valor_total NUMERIC(12,2) DEFAULT 0,
    status TEXT CHECK (status IN ('aberta','fechada','paga')) DEFAULT 'aberta',
	vencimento  date,
	numero text,  
	data_compra DATE,
	evento_codigo text default 'PAGAMENTO_FATURA_CARTAO',
    criado_em TIMESTAMP DEFAULT now()
);
 
 
drop table  cartoes_transacoes 
 

 CREATE TABLE cartoes_transacoes (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    fatura_id BIGINT NOT NULL REFERENCES cartoes_faturas(id), 
    compra_id BIGINT REFERENCES cartoes_compras(id), 
    descricao TEXT NOT NULL,
    valor NUMERIC(12,2) NOT NULL, 
    parcela_num INT,
    parcela_total INT, 
    data_parcela DATE NOT NULL,
    data_compra  date not null, 
    criado_em TIMESTAMP DEFAULT now()
);

---------------------------------------------------
-- 13. EXTRATO IMPORTADO
---------------------------------------------------
CREATE TABLE extrato_importado (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    conta_id BIGINT NOT NULL REFERENCES contas_financeiras(id),
    data_movimento DATE NOT NULL,
    descricao TEXT,
    valor NUMERIC(12,2) NOT NULL,
    hash_linha TEXT UNIQUE,
    conciliado BOOLEAN DEFAULT false,
    criado_em TIMESTAMP DEFAULT now()
);


 





ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_usuarios_empresa
ON public.usuarios
FOR ALL TO public
USING (true)
WITH CHECK (true);
 
 
ALTER TABLE public.empresas ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_empresas_empresa
ON public.empresas
FOR ALL TO public
USING (true)
WITH CHECK (true);
 

 
ALTER TABLE public.usuario_empresa ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_usuario_empresa
ON public.usuario_empresa
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.contas_financeiras ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_contas_financeiras
ON public.contas_financeiras
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.categorias_gerenciais ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_categorias_gerenciais
ON public.categorias_gerenciais
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.transacoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_transacoes
ON public.transacoes
 FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.contas_a_pagar ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_contas_a_pagar
ON public.contas_a_pagar
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.contas_a_receber ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_contas_a_receber
ON public.contas_a_receber
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.cartoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_cartoes
ON public.cartoes
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.cartoes_faturas ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_cartoes_faturas
ON public.cartoes_faturas
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.cartoes_transacoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_cartoes_transacoes
ON public.cartoes_transacoes
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.extrato_importado ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_extrato_importado
ON public.extrato_importado
FOR ALL TO public
USING (true)
WITH  CHECK  (true);
 
ALTER TABLE public.pessoa ENABLE ROW LEVEL SECURITY;
CREATE POLICY pol_pessoa
ON public.pessoa
FOR ALL TO public
USING (true)
WITH  CHECK  (true);


 