 CREATE TABLE IF NOT EXISTS public.regras_classificacao_contabil (
  id bigserial PRIMARY KEY,
  empresa_id bigint NOT NULL,
  texto_busca text NOT NULL,
  tipo_movimento text NULL,
  conta_id bigint NOT NULL,
  ativo boolean NOT NULL DEFAULT true,
  prioridade integer NOT NULL DEFAULT 100,
  criado_em timestamp without time zone DEFAULT now(),

  CONSTRAINT regras_classificacao_empresa_fkey
    FOREIGN KEY (empresa_id) REFERENCES public.empresas(id),

  CONSTRAINT regras_classificacao_conta_fkey
    FOREIGN KEY (conta_id) REFERENCES contab.contas(id)
      ON DELETE CASCADE,

  CONSTRAINT regras_classificacao_tipo_movimento_chk
    CHECK (
      tipo_movimento IS NULL
      OR tipo_movimento IN ('entrada', 'saida')
    )
);

CREATE INDEX IF NOT EXISTS idx_regras_classificacao_empresa_ativo
ON public.regras_classificacao_contabil (empresa_id, ativo);

CREATE INDEX IF NOT EXISTS idx_regras_classificacao_conta
ON public.regras_classificacao_contabil (conta_id);



ALTER TABLE public.regras_classificacao_contabil
ADD CONSTRAINT regras_classificacao_unique
UNIQUE (
  empresa_id,
  texto_busca,
  tipo_movimento
);

ALTER TABLE public.regras_classificacao_contabil
ALTER COLUMN conta_id DROP NOT NULL;

-----

ALTER TABLE public.regras_classificacao_contabil
ADD COLUMN IF NOT EXISTS tipo_evento text,
ADD COLUMN IF NOT EXISTS classificacao text;

ALTER TABLE public.regras_classificacao_contabil
ADD CONSTRAINT regras_classificacao_evento_chk
CHECK (
  tipo_evento IS NULL OR tipo_evento IN (
    'financeiro',
    'transacao',
    'pagar',
    'receber',
    'pagar_fatura',
    'receber_cartao',
    'transferencia',
    'transf_mesma_tit',
    'juros'
  )
);

----  


SELECT r.conta_id
FROM public.regras_classificacao_contabil r
WHERE r.empresa_id = p_empresa_id
  AND r.ativo = true
  AND upper(p_historico) LIKE '%' || upper(r.texto_busca) || '%'
  AND (r.tipo_movimento IS NULL OR r.tipo_movimento = p_tipo)
ORDER BY r.prioridade ASC, length(r.texto_busca) DESC
LIMIT 1;

 CREATE OR REPLACE VIEW public.vw_regras_classificacao_contabil AS
SELECT
  r.id,
  r.empresa_id,
  r.texto_busca,
  r.tipo_movimento,
  r.conta_id,
  c.codigo AS conta_codigo,
  c.nome AS conta_nome,
  CASE
    WHEN c.id IS NULL THEN 'Pendente de conta'
    ELSE c.codigo || ' - ' || c.nome
  END AS conta_descricao,
  r.ativo,
  r.prioridade,
  r.criado_em
FROM public.regras_classificacao_contabil r
LEFT JOIN contab.contas c ON c.id = r.conta_id;