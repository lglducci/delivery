-- Mapeia prefixos de contas para grupos da DRE e o sinal (1 = débito – crédito; -1 = crédito – débito)
CREATE TABLE IF NOT EXISTS contab.dre_mapeamento (
  conta_prefix  text  NOT NULL,
  grupo         text  NOT NULL,
  ordem         int   NOT NULL,
  sinal         int   NOT NULL  -- 1 para custos/despesas; -1 para receitas
);

TRUNCATE contab.dre_mapeamento;

INSERT INTO contab.dre_mapeamento (conta_prefix, grupo, ordem, sinal) VALUES
-- RECEITA
('3',  'RECEITA_BRUTA',             10, -1),
-- DEDUÇÕES (impostos sobre vendas, devoluções, etc.) => positivo reduz receita
('3.9','DEDUCOES',                   20,  1),

-- CUSTOS
('4',  'CMV_CSP',                    30,  1),

-- DESPESAS OPERACIONAIS
('5',  'DESPESAS_OPERACIONAIS',      40,  1),
('6',  'DESPESAS_OPERACIONAIS',      41,  1),

-- FINANCEIRO
('7.1','RECEITAS_FINANCEIRAS',       50, -1),
('7.2','DESPESAS_FINANCEIRAS',       60,  1),

-- IMPOSTOS SOBRE RESULTADO
('8',  'IR_CSLL',                    70,  1);
