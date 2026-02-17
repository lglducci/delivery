-- 1️⃣ CONTAS A PAGAR
ALTER TABLE public.contas_a_pagar
ADD COLUMN modelo_codigo TEXT;

ALTER TABLE public.contas_a_pagar
ADD CONSTRAINT fk_contas_a_pagar_modelo
FOREIGN KEY (modelo_codigo)
REFERENCES contab.modelos (codigo)
ON UPDATE CASCADE
ON DELETE SET NULL;

-- 2️⃣ CONTAS A RECEBER
ALTER TABLE public.contas_a_receber
ADD COLUMN modelo_codigo TEXT;

ALTER TABLE public.contas_a_receber
ADD CONSTRAINT fk_contas_a_receber_modelo
FOREIGN KEY (modelo_codigo)
REFERENCES contab.modelos (codigo)
ON UPDATE CASCADE
ON DELETE SET NULL;

-- 3️⃣ CARTOES_COMPRAS
ALTER TABLE public.cartoes_compras
ADD COLUMN modelo_codigo TEXT;

ALTER TABLE public.cartoes_compras
ADD CONSTRAINT fk_cartoes_compras_modelo
FOREIGN KEY (modelo_codigo)
REFERENCES contab.modelos (codigo)
ON UPDATE CASCADE
ON DELETE SET NULL;



 CREATE TYPE contab.tipo_operacao_enum AS ENUM (
  'CP',  -- Conta a Pagar
  'CR',  -- Conta a Receber
  'CX',  -- Movimento de Caixa
  'IM',  -- Imobilizado
  'TR',  -- Transferência
  'AD',  -- Adiantamento
  'AJ'   -- Ajuste Contábil
);

ALTER TABLE contab.modelos
ADD COLUMN tipo_operacao contab.tipo_operacao_enum;