CREATE TABLE contab.template_eventos_contabeis (
    id BIGSERIAL PRIMARY KEY,

    codigo_evento VARCHAR(50) NOT NULL,        -- CRIA_PAGAR_DESPESA
    descricao TEXT NOT NULL,

    tipo_evento VARCHAR(30) NOT NULL,          -- pagar | receber | cartao_compra | cartao_venda

    classificacao VARCHAR(30) NOT NULL,        -- despesa | estoque | receita | custo | imobilizado

    conta_debito_codigo VARCHAR(20) NOT NULL,
    conta_credito_codigo VARCHAR(20) NOT NULL,

    gera_provisao BOOLEAN DEFAULT true,
    gera_financeiro BOOLEAN DEFAULT false,

    ativo BOOLEAN DEFAULT true
);


CREATE TABLE contab.categorias_modelos (
    id BIGSERIAL PRIMARY KEY,
    empresa_id BIGINT NOT NULL,
    categoria_id BIGINT NOT NULL,
    modelo_id BIGINT NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT fk_categoria
        FOREIGN KEY (categoria_id)
        REFERENCES public.categorias_gerenciais(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_modelo
        FOREIGN KEY (modelo_id)
        REFERENCES contab.modelos(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_empresa
        FOREIGN KEY (empresa_id)
        REFERENCES empresas(id),

    CONSTRAINT categorias_modelos_uk
        UNIQUE (empresa_id, categoria_id, modelo_id)
);



 ALTER TABLE contab.categorias_modelos 
ADD COLUMN forma_operacao varchar(30)   NULL;


 ALTER TABLE contab.modelos 
ADD COLUMN forma_operacao varchar(30)   NULL;
--1

INSERT INTO contab.template_eventos_contabeis
(codigo_evento, descricao, tipo_evento, classificacao,
 conta_debito_codigo, conta_credito_codigo,
 gera_provisao, gera_financeiro)
VALUES
('CRIA_PAGAR_DESPESA',
 'Criação conta a pagar - Despesa',
 'pagar',
 'despesa',
 '6.1.9.99',     -- despesa padrão
 '2.1.1.01',     -- fornecedores
 true,
 false);

--2

INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'CRIA_PAGAR_ESTOQUE',
 'Criação conta a pagar - Estoque',
 'pagar',
 'estoque',
 '1.1.4.01',
 '2.1.1.01',
 true,
 false,
 true);


--3
INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'CRIA_RECEBER',
 'Criação conta a receber',
 'receber',
 'receita',
 '1.1.2.01',
 '4.1.1.01',
 true,
 false,
 true);


--4

INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'CRIA_CARTAO_COMPRA',
 'Compra no cartão',
 'cartao_compra',
 'despesa',
 '6.1.9.99',
 '2.1.3.01',
 true,
 false,
 true);

--5

INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'CRIA_CARTAO_VENDA',
 'Venda no cartão',
 'cartao_venda',
 'receita',
 '1.1.3.01',
 '4.1.1.01',
 true,
 false,
 true);

--6
INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'PAGAMENTO_FORNECEDOR',
 'Pagamento de fornecedor',
 'financeiro',
 'baixa',
 '2.1.1.01',
 '1.1.1.01',
 false,
 true,
 true);

 

 --7 COMPRA NO CARTÃO (PROVISÃO DA FATURA)
 

INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'PROVISAO_CARTAO_COMPRA',
 'Provisão compra no cartão',
 'cartao_compra',
 'despesa',
 '6.1.9.99',
 '2.1.3.01',
 true,
 true,
 true);

-- 8  APROPRIAÇÃO DESPESA CARTÃO (caso queira separar)
INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'APROPRIACAO_CARTAO',
 'Apropriação despesa cartão',
 'cartao_apropriacao',
 'despesa',
 '6.1.9.99',
 '2.1.3.01',
 true,
 true,
 true);


--  9  PAGAMENTO DA FATURA

 

INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'PAGAMENTO_FATURA_CARTAO',
 'Pagamento da fatura do cartão',
 'cartao_pagamento',
 'baixa_passivo',
 '2.1.3.01',
 '1.1.1.02',
 true,
 true,
 true);

-- 10  VENDA NO CARTÃO (gera ativo a receber)
INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'VENDA_CARTAO',
 'Venda no cartão',
 'cartao_venda',
 'receita',
 '1.1.3.01',
 '4.1.1.01',
 true,
 true,
 true);


 

 ---- 11 RECEBIMENTO DO CARTÃO (liquidação)
INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'RECEBIMENTO_CARTAO',
 'Recebimento de venda cartão',
 'cartao_recebimento',
 'baixa_ativo',
 '1.1.1.02',
 '1.1.3.01',
 true,
 true,
 true);



--   5x

INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'BAIXA_ESTOQUE_CMV',
 'Baixa de estoque (CMV)',
 'estoque_saida',
 'custo',
 '5.1.1.01',
 '1.1.4.01',
 true,
 true,
 true);


INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'PROVISAO_CARTAO_ESTOQUE',
 'Compra de estoque no cartão',
 'cartao_estoque',
 'estoque',
 '1.1.4.01',
 '2.1.3.01',
 true,
 true,
 true);


INSERT INTO contab.template_eventos_contabeis
VALUES
(DEFAULT,
 'CUSTO_VENDA',
 'Reconhecimento automático do custo da venda',
 'venda_custo',
 'custo',
 '5.1.1.01',
 '1.1.4.01',
 true,
 true,
 true);
