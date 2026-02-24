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


 
ALTER TABLE contab.modelos 
ADD COLUMN IF NOT EXISTS classificacao TEXT ;

