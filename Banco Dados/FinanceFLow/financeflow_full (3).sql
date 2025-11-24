
-- SQL COMPLETO DO SISTEMA FINANCE-FLOW
-- (12 tabelas físicas + inserts)
-- ====================================

-- 1. usuarios
CREATE TABLE usuarios (
    id BIGSERIAL PRIMARY KEY,
    nome TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    senha_hash TEXT NOT NULL,
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO usuarios (nome, email, senha_hash)
VALUES ('Administrador', 'admin@admin.com', '123456');


-- 2. empresas
CREATE TABLE empresas (
    id BIGSERIAL PRIMARY KEY,
    nome TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('PF','MEI','PJ')),
    documento TEXT,
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO empresas (nome, tipo, documento)
VALUES ('Empresa Padrão', 'PF', '00000000000');


-- 3. usuario_empresa
CREATE TABLE usuario_empresa (
    id BIGSERIAL PRIMARY KEY,
    usuario_id BIGINT NOT NULL REFERENCES usuarios(id),
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    role TEXT DEFAULT 'admin',
    UNIQUE (usuario_id, empresa_id)
);

INSERT INTO usuario_empresa (usuario_id, empresa_id, role)
VALUES (1, 1, 'admin');


-- 4. contas_financeiras
CREATE TABLE contas_financeiras (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    banco TEXT,
    tipo TEXT NOT NULL CHECK (tipo IN ('corrente','poupanca','carteira','caixa')),
    saldo_inicial NUMERIC(12,2) DEFAULT 0,
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO contas_financeiras (empresa_id, nome, banco, tipo, saldo_inicial)
VALUES
(1, 'Nubank', 'Nubank', 'corrente', 500.00),
(1, 'Carteira', 'Fisico', 'carteira', 150.00);


-- 5. categorias_gerenciais
CREATE TABLE categorias_gerenciais (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('entrada','saida'))
);

INSERT INTO categorias_gerenciais (empresa_id, nome, tipo)
VALUES
(1, 'Vendas', 'entrada'),
(1, 'PIX Recebido', 'entrada'),
(1, 'Alimentação', 'saida'),
(1, 'Tarifas', 'saida');


-- 6. transacoes
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
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO transacoes
(empresa_id, conta_id, categoria_id, tipo, valor, descricao, data_movimento)
VALUES
(1, 1, 1, 'entrada', 300.00, 'Venda PIX Cliente João', '2025-11-05'),
(1, 1, 3, 'saida', 92.50, 'Supermercado', '2025-11-06');


-- 7. contas_a_pagar
CREATE TABLE contas_a_pagar (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    descricao TEXT NOT NULL,
    valor NUMERIC(12,2) NOT NULL,
    vencimento DATE NOT NULL,
    categoria_id BIGINT REFERENCES categorias_gerenciais(id),
    parcelas INT DEFAULT 1,
    parcela_num INT DEFAULT 1,
    status TEXT NOT NULL CHECK (status IN ('aberto','pago')),
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO contas_a_pagar
(empresa_id, descricao, valor, vencimento, categoria_id, status)
VALUES
(1, 'Aluguel', 1200.00, '2025-12-10', 3, 'aberto');


-- 8. contas_a_receber
CREATE TABLE contas_a_receber (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    descricao TEXT NOT NULL,
    valor NUMERIC(12,2) NOT NULL,
    vencimento DATE NOT NULL,
    categoria_id BIGINT REFERENCES categorias_gerenciais(id),
    cliente TEXT,
    status TEXT NOT NULL CHECK (status IN ('aberto','recebido')),
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO contas_a_receber
(empresa_id, descricao, valor, vencimento, categoria_id, cliente, status)
VALUES
(1, 'Cliente Pedro', 850.00, '2025-12-12', 1, 'Pedro', 'aberto');


-- 9. cartoes
CREATE TABLE cartoes (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    nome TEXT NOT NULL,
    bandeira TEXT,
    limite_total NUMERIC(12,2),
    fechamento_dia INT,
    vencimento_dia INT,
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO cartoes (empresa_id, nome, bandeira, limite_total, fechamento_dia, vencimento_dia)
VALUES
(1, 'Nubank Roxo', 'Mastercard', 2000.00, 3, 10);


-- 10. cartoes_faturas
CREATE TABLE cartoes_faturas (
    id BIGSERIAL PRIMARY KEY,
    cartao_id BIGINT NOT NULL REFERENCES cartoes(id),
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    mes_referencia DATE NOT NULL,
    valor_total NUMERIC(12,2) DEFAULT 0,
    status TEXT CHECK (status IN ('aberta','fechada','paga')) DEFAULT 'aberta',
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO cartoes_faturas (cartao_id, empresa_id, mes_referencia, valor_total, status)
VALUES
(1, 1, '2025-11-01', 0, 'aberta');


-- 11. cartoes_transacoes
CREATE TABLE cartoes_transacoes (
    id BIGSERIAL PRIMARY KEY,
    fatura_id BIGINT NOT NULL REFERENCES cartoes_faturas(id),
    empresa_id BIGINT NOT NULL REFERENCES empresas(id),
    descricao TEXT NOT NULL,
    valor NUMERIC(12,2) NOT NULL,
    parcela_num INT,
    parcela_total INT,
    criado_em TIMESTAMP DEFAULT now()
);

INSERT INTO cartoes_transacoes
(fatura_id, empresa_id, descricao, valor, parcela_num, parcela_total)
VALUES
(1, 1, 'Mercado – compra parcelada', 150.00, 1, 3);


-- 12. extrato_importado
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

INSERT INTO extrato_importado
(empresa_id, conta_id, data_movimento, descricao, valor, hash_linha)
VALUES
(1, 1, '2025-11-05', 'PIX Cliente João', 300.00, 'hash001');

