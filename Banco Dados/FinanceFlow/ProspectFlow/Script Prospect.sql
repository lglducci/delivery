CREATE TABLE prospect.empresa_instancias (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    empresa_id BIGINT NOT NULL,
    instancia_nome TEXT NOT NULL,
    numero_whatsapp TEXT,
    finalidade TEXT,

    ativo BOOLEAN NOT NULL DEFAULT TRUE,

    criado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    token  text,
    CONSTRAINT uq_empresa_instancias_nome
        UNIQUE (instancia_nome)
);


ALTER TABLE prospect.empresa_instancias
ADD CONSTRAINT fk_empresa_instancias_empresa
FOREIGN KEY (empresa_id)
REFERENCES public.empresas(id);



CREATE POLICY "service_role_acesso_total_empresa_instancias"
ON prospect.empresa_instancias
AS PERMISSIVE
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);





CREATE TABLE IF NOT EXISTS prospect.webhook_eventos (
    id                       BIGSERIAL PRIMARY KEY,
    empresa_instancia_id     BIGINT NOT NULL
                             REFERENCES prospect.empresa_instancias(id),
    mensagem_externa_id      TEXT NOT NULL,
    evento                   TEXT NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_webhook_evento
        UNIQUE (
            empresa_instancia_id,
            mensagem_externa_id,
            evento
        )
);