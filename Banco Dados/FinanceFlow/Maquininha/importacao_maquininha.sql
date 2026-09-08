CREATE TABLE public.operadora_importacoes (
    id bigserial PRIMARY KEY,

    empresa_id bigint NOT NULL,
    conta_financeira_id bigint NULL,

    operadora varchar(30) NOT NULL,       -- GETNET, CIELO, REDE...
    tipo_arquivo varchar(50) NULL,        -- VENDAS_DETALHADO etc.

    data_inicio date NOT NULL,
    data_fim date NOT NULL,

    arquivo_nome text NULL,
    arquivo_hash text NULL,

    qtd_linhas integer NOT NULL DEFAULT 0,
    qtd_cartoes integer NOT NULL DEFAULT 0,
    qtd_pix integer NOT NULL DEFAULT 0,
    qtd_outros integer NOT NULL DEFAULT 0,

    total_bruto numeric(14,2) NOT NULL DEFAULT 0,
    total_taxas numeric(14,2) NOT NULL DEFAULT 0,
    total_liquido numeric(14,2) NOT NULL DEFAULT 0,

    total_credito numeric(14,2) NOT NULL DEFAULT 0,
    total_debito numeric(14,2) NOT NULL DEFAULT 0,
    total_pix numeric(14,2) NOT NULL DEFAULT 0,

    diagnostico jsonb NULL,

    status varchar(30) NOT NULL DEFAULT 'IMPORTADO',

    criado_em timestamp NOT NULL DEFAULT now(),

    CONSTRAINT fk_operadora_importacao_empresa
        FOREIGN KEY (empresa_id)
        REFERENCES empresas(id),

    CONSTRAINT fk_operadora_importacao_conta
        FOREIGN KEY (conta_financeira_id)
        REFERENCES contas_financeiras(id)
);



CREATE TABLE public.operadora_movimentos (
    id bigserial PRIMARY KEY,

    importacao_id bigint NOT NULL,
    empresa_id bigint NOT NULL,

    tipo_movimento varchar(30) NOT NULL,
    -- CARTAO / PIX / RECARGA / VOUCHER / etc.

    data_movimento timestamp NULL,
    data_prevista_pagamento date NULL,

    bandeira varchar(30) NULL,
    modalidade varchar(30) NULL,
    forma_pagamento varchar(50) NULL,
    status varchar(50) NULL,

    parcelas integer NULL,

    autorizacao varchar(50) NULL,
    comprovante_venda varchar(50) NULL,
    transacao_origem varchar(100) NULL,

    terminal varchar(50) NULL,

    valor_bruto numeric(14,2) NOT NULL DEFAULT 0,
    valor_taxa numeric(14,2) NOT NULL DEFAULT 0,
    valor_liquido numeric(14,2) NOT NULL DEFAULT 0,

    chave_registro text NOT NULL,

    conciliado boolean NOT NULL DEFAULT false,
    conciliacao_financeira_id bigint NULL,

    dados_origem jsonb NULL,

    criado_em timestamp NOT NULL DEFAULT now(),

    CONSTRAINT fk_operadora_mov_importacao
        FOREIGN KEY (importacao_id)
        REFERENCES public.operadora_importacoes(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_operadora_mov_empresa
        FOREIGN KEY (empresa_id)
        REFERENCES empresas(id),

    CONSTRAINT fk_operadora_mov_conciliacao
        FOREIGN KEY (conciliacao_financeira_id)
        REFERENCES conciliacao_financeira(id)
        ON DELETE SET NULL
);


CREATE UNIQUE INDEX ux_operadora_movimento_chave
ON public.operadora_movimentos (
    empresa_id,
    chave_registro
);




ALTER TABLE public.conciliacao_financeira
ADD COLUMN IF NOT EXISTS chave_match_operadora text;

ALTER TABLE public.operadora_movimentos
ADD COLUMN IF NOT EXISTS chave_match_operadora text;

 

CREATE INDEX IF NOT EXISTS
idx_conciliacao_financeira_chave_match_operadora
ON public.conciliacao_financeira (
    empresa_id,
    chave_match_operadora
);

CREATE INDEX IF NOT EXISTS
idx_operadora_movimentos_chave_match_operadora
ON public.operadora_movimentos (
    empresa_id,
    chave_match_operadora
);


ALTER TABLE public.operadora_movimentos
ADD COLUMN IF NOT EXISTS status_processamento VARCHAR(20) NOT NULL DEFAULT 'ABERTO',
ADD COLUMN IF NOT EXISTS processado_em TIMESTAMP,
ADD COLUMN IF NOT EXISTS processamento_erro TEXT;