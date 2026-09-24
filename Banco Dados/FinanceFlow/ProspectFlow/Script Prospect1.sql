 -- ProspectFlow
-- Entrada unica do webhook Evolution API -> n8n -> PostgreSQL.
--
-- Aceita:
--   1) um objeto JSONB; ou
--   2) um array JSONB com um ou mais objetos.
--
-- A funcao resolve instancia -> empresa -> lead, impede duplicidade e
-- reaproveita as funcoes atuais de envio, resposta e conversa. Toda a chamada
-- ocorre em uma unica transacao PostgreSQL.

BEGIN;

-- A Evolution pode emitir a mesma mensagem em MESSAGES_UPSERT e SEND_MESSAGE.
-- Por isso a unicidade correta e instancia + mensagem_id, sem incluir evento.
ALTER TABLE prospect.webhook_eventos
    DROP CONSTRAINT IF EXISTS uq_webhook_evento;

DROP INDEX IF EXISTS prospect.uq_webhook_evento;

CREATE UNIQUE INDEX IF NOT EXISTS uq_prospect_webhook_mensagem
    ON prospect.webhook_eventos (
        empresa_instancia_id,
        mensagem_externa_id
    );
 
 
CREATE OR REPLACE FUNCTION public.prospectflow_processar_webhook(
    p_payload JSONB 
    
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, prospect
AS $$
DECLARE
    v_itens                  JSONB;
    v_item                   JSONB;
    v_resultados             JSONB := '[]'::JSONB;

    v_instancia_nome         TEXT;
    v_empresa_instancia_id   BIGINT;
    v_empresa_id             BIGINT;

    v_tipo_evento            TEXT;
    v_evento_evolution       TEXT;
    v_from_me                BOOLEAN;
    v_direcao                TEXT;
    v_canal                  TEXT;

    v_telefone               TEXT;
    v_jid                    TEXT;
    v_mensagem               TEXT;
    v_mensagem_externa_id    TEXT;
    v_evolution_message_id   TEXT;
    v_status_entrega         TEXT;
    v_webhook_chave          TEXT;
    v_interacoes_atualizadas INTEGER;

    v_lead                   prospect.leads%ROWTYPE;
    v_tem_proxima_cadencia   BOOLEAN;

    v_webhook_evento_id      BIGINT;
    v_payload_acao           JSONB;
    v_retorno_acao           JSONB;
    v_acao                   TEXT;
    v_mensagem_template_id   BIGINT;
    v_mensagem_automatica    BOOLEAN;
    v_classificacao          TEXT;
BEGIN
    IF p_payload IS NULL OR p_payload = 'null'::JSONB THEN
        RAISE EXCEPTION 'payload do webhook e obrigatorio';
    END IF;

    -- Padroniza objeto e array para sempre trabalhar com array.
    v_itens := CASE JSONB_TYPEOF(p_payload)
        WHEN 'array'  THEN p_payload
        WHEN 'object' THEN JSONB_BUILD_ARRAY(p_payload)
        ELSE NULL
    END;



    IF v_itens IS NULL THEN
        RAISE EXCEPTION 'payload deve ser um objeto ou array JSON';
    END IF;

    IF JSONB_ARRAY_LENGTH(v_itens) = 0 THEN
        RETURN JSONB_BUILD_OBJECT(
            'ok', TRUE,
            'quantidade', 0,
            'resultados', '[]'::JSONB
        );
    END IF;


    FOR v_item IN
        SELECT value
          FROM JSONB_ARRAY_ELEMENTS(v_itens)
    LOOP
        -- Limpa variaveis que podem manter valor da iteracao anterior.
        v_empresa_instancia_id := NULL;
        v_empresa_id := NULL;
        v_webhook_evento_id := NULL;
        v_retorno_acao := NULL;
        v_acao := NULL;
        v_evolution_message_id := NULL;
        v_status_entrega := NULL;
        v_webhook_chave := NULL;
        v_interacoes_atualizadas := 0;

        IF JSONB_TYPEOF(v_item) <> 'object' THEN
            RAISE EXCEPTION 'cada item do payload deve ser um objeto JSON';
        END IF;

        v_instancia_nome := COALESCE(
            NULLIF(BTRIM(v_item->>'instancia'), ''),
            NULLIF(BTRIM(v_item->>'instance'), ''),
            NULLIF(BTRIM(v_item #>> '{body,instance}'), '')
        );

        IF v_instancia_nome IS NULL THEN
            RAISE EXCEPTION 'instancia e obrigatoria';
        END IF;

        SELECT ei.id, ei.empresa_id
          INTO v_empresa_instancia_id, v_empresa_id
          FROM prospect.empresa_instancias AS ei
         WHERE LOWER(BTRIM(ei.instancia_nome)) = LOWER(v_instancia_nome)
           AND ei.ativo = TRUE
         LIMIT 1;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'instancia ativa nao cadastrada: %', v_instancia_nome;
        END IF;

        v_tipo_evento := UPPER(COALESCE(
            NULLIF(BTRIM(v_item->>'tipo_evento'), ''),
            NULLIF(BTRIM(v_item->>'evento'), ''),
            NULLIF(BTRIM(v_item #>> '{body,event}'), ''),
            'MENSAGEM'
        ));

        v_evento_evolution := LOWER(COALESCE(
            NULLIF(BTRIM(v_item->>'evento_evolution'), ''),
            NULLIF(BTRIM(v_item->>'evento'), ''),
            NULLIF(BTRIM(v_item #>> '{body,event}'), ''),
            v_tipo_evento
        ));

        v_mensagem_automatica :=
            LOWER(COALESCE(v_item->>'mensagem_automatica', 'false'))
            IN ('true', 't', '1', 'sim', 'yes');

        v_classificacao := UPPER(COALESCE(
            NULLIF(BTRIM(v_item->>'classificacao'), ''),
            'HUMANA'
        ));

        v_from_me := CASE
            WHEN LOWER(COALESCE(v_item->>'from_me', '')) IN ('true', 't', '1', 'yes', 'sim') THEN TRUE
            WHEN LOWER(COALESCE(v_item->>'from_me', '')) IN ('false', 'f', '0', 'no', 'nao', 'não') THEN FALSE
            WHEN LOWER(COALESCE(v_item #>> '{data,fromMe}', '')) IN ('true', 't', '1', 'yes', 'sim') THEN TRUE
            WHEN LOWER(COALESCE(v_item #>> '{data,fromMe}', '')) IN ('false', 'f', '0', 'no', 'nao', 'não') THEN FALSE
            WHEN LOWER(COALESCE(v_item #>> '{body,data,fromMe}', '')) IN ('true', 't', '1', 'yes', 'sim') THEN TRUE
            WHEN LOWER(COALESCE(v_item #>> '{body,data,fromMe}', '')) IN ('false', 'f', '0', 'no', 'nao', 'não') THEN FALSE
            ELSE UPPER(COALESCE(v_item->>'direcao', '')) = 'ENVIADA_POR_MIM'
        END;

        -- Atualizacao de entrega/leitura nao e uma nova mensagem. Ela precisa
        -- ser tratada antes das validacoes de telefone, lead e classificacao.
        IF REPLACE(v_evento_evolution, '.', '_') = 'messages_update'
           OR REPLACE(LOWER(v_tipo_evento), '.', '_') = 'messages_update' THEN

            v_evolution_message_id := COALESCE(
                NULLIF(BTRIM(v_item->>'evolution_message_id'), ''),
                NULLIF(BTRIM(v_item->>'mensagem_externa_id'), ''),
                NULLIF(BTRIM(v_item->>'keyId'), ''),
                NULLIF(BTRIM(v_item #>> '{data,keyId}'), ''),
                NULLIF(BTRIM(v_item #>> '{body,data,keyId}'), '')
            );

            v_status_entrega := UPPER(COALESCE(
                NULLIF(BTRIM(v_item->>'status_entrega'), ''),
                NULLIF(BTRIM(v_item->>'status'), ''),
                NULLIF(BTRIM(v_item #>> '{data,status}'), ''),
                NULLIF(BTRIM(v_item #>> '{body,data,status}'), '')
            ));

            IF v_evolution_message_id IS NULL THEN
                RAISE EXCEPTION 'evolution_message_id/keyId e obrigatorio para MESSAGES_UPDATE';
            END IF;

            IF v_status_entrega IS NULL THEN
                RAISE EXCEPTION 'status_entrega e obrigatorio para MESSAGES_UPDATE';
            END IF;

            -- A mesma mensagem recebe varios status. A chave inclui o status
            -- para DELIVERY_ACK nao impedir o processamento posterior de READ.
            v_webhook_chave := CONCAT_WS(
                ':',
                v_evolution_message_id,
                v_status_entrega,
                CASE WHEN v_from_me THEN 'FROM_ME' ELSE 'FROM_CLIENT' END
            );

            INSERT INTO prospect.webhook_eventos (
                empresa_instancia_id,
                mensagem_externa_id,
                evento
            )
            VALUES (
                v_empresa_instancia_id,
                v_webhook_chave,
                v_evento_evolution
            )
            ON CONFLICT (empresa_instancia_id, mensagem_externa_id) DO NOTHING
            RETURNING id INTO v_webhook_evento_id;

            IF v_webhook_evento_id IS NULL THEN
                v_resultados := v_resultados || JSONB_BUILD_ARRAY(
                    JSONB_BUILD_OBJECT(
                        'ok', TRUE,
                        'processado', FALSE,
                        'duplicado', TRUE,
                        'motivo', 'STATUS_JA_PROCESSADO',
                        'instancia', v_instancia_nome,
                        'empresa_id', v_empresa_id,
                        'evolution_message_id', v_evolution_message_id,
                        'status_entrega', v_status_entrega
                    )
                );
                CONTINUE;
            END IF;

            -- Para os sinais das mensagens enviadas pelo ProspectFlow,
            -- interessam apenas os updates em que from_me = true.
            IF NOT v_from_me THEN
                v_resultados := v_resultados || JSONB_BUILD_ARRAY(
                    JSONB_BUILD_OBJECT(
                        'ok', TRUE,
                        'processado', FALSE,
                        'motivo', 'STATUS_DE_MENSAGEM_RECEBIDA_IGNORADO',
                        'instancia', v_instancia_nome,
                        'empresa_id', v_empresa_id,
                        'evolution_message_id', v_evolution_message_id,
                        'status_entrega', v_status_entrega
                    )
                );
                CONTINUE;
            END IF;

            UPDATE prospect.interacoes AS i
               SET status_entrega = v_status_entrega,
                   enviada_em = CASE
                       WHEN v_status_entrega IN ('SERVER_ACK', 'DELIVERY_ACK', 'READ', 'PLAYED')
                           THEN COALESCE(i.enviada_em, NOW())
                       ELSE i.enviada_em
                   END,
                   entregue_em = CASE
                       WHEN v_status_entrega IN ('DELIVERY_ACK', 'READ', 'PLAYED')
                           THEN COALESCE(i.entregue_em, NOW())
                       ELSE i.entregue_em
                   END,
                   lida_em = CASE
                       WHEN v_status_entrega IN ('READ', 'PLAYED')
                           THEN COALESCE(i.lida_em, NOW())
                       ELSE i.lida_em
                   END,
                   erro_envio = CASE
                       WHEN v_status_entrega = 'ERROR' THEN 'Falha informada pela Evolution'
                       WHEN v_status_entrega IN ('SERVER_ACK', 'DELIVERY_ACK', 'READ', 'PLAYED') THEN NULL
                       ELSE i.erro_envio
                   END
             WHERE i.empresa_id = v_empresa_id
               AND i.evolution_message_id = v_evolution_message_id
               AND (
                   (
                       v_status_entrega = 'ERROR'
                       AND COALESCE(i.status_entrega, '') NOT IN ('DELIVERY_ACK', 'READ', 'PLAYED')
                   )
                   OR
                   (
                       v_status_entrega <> 'ERROR'
                       AND CASE v_status_entrega
                               WHEN 'PENDING' THEN 10
                               WHEN 'SERVER_ACK' THEN 20
                               WHEN 'DELIVERY_ACK' THEN 30
                               WHEN 'READ' THEN 40
                               WHEN 'PLAYED' THEN 50
                               ELSE 0
                           END
                           >=
                           CASE COALESCE(i.status_entrega, '')
                               WHEN 'PENDING' THEN 10
                               WHEN 'SERVER_ACK' THEN 20
                               WHEN 'DELIVERY_ACK' THEN 30
                               WHEN 'READ' THEN 40
                               WHEN 'PLAYED' THEN 50
                               WHEN 'ERROR' THEN 0
                               ELSE 0
                           END
                   )
               );

            GET DIAGNOSTICS v_interacoes_atualizadas = ROW_COUNT;

            v_resultados := v_resultados || JSONB_BUILD_ARRAY(
                JSONB_BUILD_OBJECT(
                    'ok', TRUE,
                    'processado', v_interacoes_atualizadas > 0,
                    'motivo', CASE
                        WHEN v_interacoes_atualizadas > 0 THEN 'STATUS_ATUALIZADO'
                        ELSE 'INTERACAO_NAO_ENCONTRADA_OU_STATUS_ANTERIOR'
                    END,
                    'instancia', v_instancia_nome,
                    'empresa_id', v_empresa_id,
                    'evolution_message_id', v_evolution_message_id,
                    'status_entrega', v_status_entrega,
                    'interacoes_atualizadas', v_interacoes_atualizadas
                )
            );
            CONTINUE;
        END IF;

        v_direcao := CASE
            WHEN v_from_me THEN 'ENVIADA_POR_MIM'
            ELSE 'RECEBIDA_DO_CLIENTE'
        END;

        v_canal := CASE
            WHEN v_tipo_evento = 'LIGACAO' THEN 'TELEFONE'
            ELSE 'WHATSAPP'
        END;

        v_jid := NULLIF(BTRIM(v_item->>'jid_cliente'), '');

        -- Usa telefone_cliente e, como fallback, tenta extrair do JID.
        v_telefone := REGEXP_REPLACE(
            COALESCE(NULLIF(v_item->>'telefone_cliente', ''), v_jid, ''),
            '[^0-9]',
            '',
            'g'
        );

        -- Padrao brasileiro: banco e webhook passam a comparar sempre com DDI 55.
        IF LENGTH(v_telefone) IN (10, 11) THEN
            v_telefone := '55' || v_telefone;
        END IF;

        IF v_telefone = '' THEN
            v_telefone := NULL;
        END IF;

        IF v_telefone IS NULL THEN
            v_resultados := v_resultados || JSONB_BUILD_ARRAY(
                JSONB_BUILD_OBJECT(
                    'ok', FALSE,
                    'processado', FALSE,
                    'motivo', 'TELEFONE_NAO_IDENTIFICADO',
                    'instancia', v_instancia_nome,
                    'empresa_id', v_empresa_id,
                    'jid_cliente', v_jid
                )
            );
            CONTINUE;
        END IF;

        v_mensagem := NULLIF(BTRIM(v_item->>'mensagem'), '');

        IF v_mensagem IS NULL THEN
            v_mensagem := CASE
                WHEN v_tipo_evento = 'LIGACAO' AND v_from_me
                    THEN '[Ligacao realizada pelo WhatsApp]'
                WHEN v_tipo_evento = 'LIGACAO'
                    THEN '[Ligacao recebida pelo WhatsApp]'
                ELSE '[Mensagem sem texto]'
            END;
        END IF;

        v_mensagem_template_id :=
    NULLIF(v_item->>'mensagem_template_id', '')::BIGINT;

        v_mensagem_externa_id := COALESCE(
                NULLIF(BTRIM(v_item->>'evolution_message_id'), ''),
                NULLIF(BTRIM(v_item->>'mensagem_externa_id'), ''),
                NULLIF(BTRIM(v_item->>'mensagem_id'), '')
            );

        -- CALL e alguns eventos podem nao trazer mensagem_id. O hash cria uma
        -- chave deterministica para evitar repeticao do mesmo webhook.
        IF v_mensagem_externa_id IS NULL THEN
            v_mensagem_externa_id := MD5(CONCAT_WS(
                '|',
                v_instancia_nome,
                v_tipo_evento,
                v_direcao,
                v_telefone,
                COALESCE(v_item->>'data_evento', ''),
                v_mensagem
            ));
        END IF;

        -- Reserva a mensagem antes de alterar o lead. Se qualquer etapa posterior
        -- falhar, esta insercao tambem sera desfeita pela mesma transacao.
        INSERT INTO prospect.webhook_eventos (
            empresa_instancia_id,
            mensagem_externa_id,
            evento
        )
        VALUES (
            v_empresa_instancia_id,
            v_mensagem_externa_id,
            v_evento_evolution
        )
        ON CONFLICT (empresa_instancia_id, mensagem_externa_id) DO NOTHING
        RETURNING id INTO v_webhook_evento_id;

        IF v_webhook_evento_id IS NULL THEN
            v_resultados := v_resultados || JSONB_BUILD_ARRAY(
                JSONB_BUILD_OBJECT(
                    'ok', TRUE,
                    'processado', FALSE,
                    'duplicado', TRUE,
                    'motivo', 'WEBHOOK_JA_PROCESSADO',
                    'instancia', v_instancia_nome,
                    'empresa_id', v_empresa_id,
                    'telefone_cliente', v_telefone,
                    'mensagem_id', v_mensagem_externa_id
                )
            );
            CONTINUE;
        END IF;

        -- O telefone recebido ja identifica o lead nesta empresa. Nao refazer
        -- a consulta usando outro ID: isso apagava v_lead quando o ID era NULL.
        BEGIN
            SELECT l.*
              INTO STRICT v_lead
              FROM prospect.leads AS l
             WHERE l.empresa_id = v_empresa_id
               AND l.telefone = v_telefone
             FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE EXCEPTION
                    'Lead nao encontrado: empresa_id=%, telefone_cliente=%, jid_cliente=%',
                    v_empresa_id, v_telefone, COALESCE(v_jid, '(ausente)');
            WHEN TOO_MANY_ROWS THEN
                RAISE EXCEPTION
                    'Mais de um lead com o mesmo telefone: empresa_id=%, telefone_cliente=%',
                    v_empresa_id, v_telefone;
        END;

         -- Toda mensagem recebida deixa o lead como não lido.
                IF NOT v_from_me THEN
                    UPDATE prospect.leads AS l
                    SET lido = FALSE
                    WHERE l.id = v_lead.id
                    AND l.empresa_id = v_empresa_id
                    RETURNING l.* INTO v_lead;
                END IF;

        v_payload_acao :=
    (
        v_item
        - 'mensagem_id'
        - 'mensagem_externa_id'
        - 'mensagem_template_id'
    )
    || JSONB_BUILD_OBJECT(
        'lead_id', v_lead.id,
        'canal', v_canal,
        'mensagem', v_mensagem,
        'evolution_message_id', v_mensagem_externa_id,
        'status_entrega', CASE
            WHEN v_from_me THEN UPPER(COALESCE(
                NULLIF(BTRIM(v_item->>'status_entrega'), ''),
                NULLIF(BTRIM(v_item->>'status'), ''),
                'SERVER_ACK'
            ))
            ELSE NULL
        END
    );

        -- Estados finais nao voltam automaticamente para prospeccao.
        IF v_lead.nao_contatar
           OR v_lead.status IN ('BLOQUEADO', 'CONVERTIDO', 'ENCERRADO') THEN
            v_resultados := v_resultados || JSONB_BUILD_ARRAY(
                JSONB_BUILD_OBJECT(
                    'ok', TRUE,
                    'processado', FALSE,
                    'motivo', 'LEAD_EM_ESTADO_FINAL',
                    'instancia', v_instancia_nome,
                    'empresa_id', v_empresa_id,
                    'lead_id', v_lead.id,
                    'status', v_lead.status,
                    'telefone_cliente', v_telefone,
                    'mensagem_id', v_mensagem_externa_id
                )
            );
            CONTINUE;
        END IF;
      

      IF NOT v_from_me THEN

    IF v_mensagem_automatica THEN

        v_acao := v_classificacao;

        INSERT INTO prospect.interacoes (
            empresa_id,
            lead_id,
            tipo,
            canal,
            mensagem,
            evolution_message_id,
            automatica,
            classificacao
        )
        VALUES (
            v_empresa_id,
            v_lead.id,
            'RESPOSTA',
            v_canal,
            v_mensagem,
            v_mensagem_externa_id,
            TRUE,
            v_classificacao
        );

        UPDATE prospect.leads AS l
        SET
            status = CASE
                WHEN v_classificacao = 'AUTOMATICA_MENU'
                    THEN 'AGUARDANDO_CLIENTE'
                WHEN v_classificacao = 'AUTOMATICA_ENCERRAMENTO'
                    THEN 'EM_CADENCIA'
                ELSE l.status
            END,
            proximo_contato_em = CASE
                WHEN v_classificacao = 'AUTOMATICA_MENU'
                    THEN NULL
                ELSE l.proximo_contato_em
            END,
            ultimo_contato_em = NOW()
        WHERE l.id = v_lead.id
          AND l.empresa_id = v_empresa_id
        RETURNING l.* INTO v_lead;

        v_retorno_acao := JSONB_BUILD_OBJECT(
            'ok', TRUE,
            'automatica', TRUE,
            'classificacao', v_classificacao,
            'lead', TO_JSONB(v_lead)
        );

    ELSE

        v_acao := 'REGISTRAR_RESPOSTA';

        v_retorno_acao := prospect.fn_registrar_resposta(
            v_empresa_id,
            v_payload_acao
        );

    END IF;

        ELSIF v_lead.status IN ('AGUARDANDO_MINHA_RESPOSTA', 'AGUARDANDO_CLIENTE') THEN
            -- Mensagem enviada dentro de uma conversa nao avanca a cadencia.
            v_acao := 'REGISTRAR_MENSAGEM_CONVERSA';
            v_retorno_acao := prospect.fn_registrar_mensagem_conversa(
                v_empresa_id,
                v_payload_acao
            );

        ELSE
            -- NOVO/EM_CADENCIA: o envio corresponde ao proximo passo da cadencia,
            -- desde que ainda exista uma mensagem ativa posterior.
            SELECT EXISTS (
                SELECT 1
                  FROM prospect.mensagens AS msg
                 WHERE msg.empresa_id = v_empresa_id
                   AND msg.ativo = TRUE
                   AND msg.ordem > v_lead.ultima_cadencia_enviada
            )
              INTO v_tem_proxima_cadencia;

            IF v_tem_proxima_cadencia THEN
                v_acao := 'REGISTRAR_ENVIO';
                v_retorno_acao := prospect.fn_registrar_envio(
                    v_empresa_id,
                    v_payload_acao
                );
            ELSE
                -- Nao perde um envio real caso a empresa nao tenha uma proxima
                -- mensagem de cadencia configurada.
                v_acao := 'REGISTRAR_ENVIO_SEM_CADENCIA';

                INSERT INTO prospect.interacoes (
                    empresa_id,
                    lead_id,
                    tipo,
                    canal,
                    mensagem,
                    evolution_message_id,
                    status_entrega,
                    enviada_em
                )
                VALUES (
                    v_empresa_id,
                    v_lead.id,
                    'ENVIO',
                    v_canal,
                    v_mensagem,
                    v_mensagem_externa_id,
                    UPPER(COALESCE(
                        NULLIF(BTRIM(v_item->>'status_entrega'), ''),
                        NULLIF(BTRIM(v_item->>'status'), ''),
                        'SERVER_ACK'
                    )),
                    NOW()
                );

                UPDATE prospect.leads AS l
                   SET status = 'EM_CADENCIA',
                       ultimo_contato_em = NOW(),
                       proximo_contato_em = NULL
                 WHERE l.id = v_lead.id
                   AND l.empresa_id = v_empresa_id
                RETURNING l.* INTO v_lead;

                v_retorno_acao := JSONB_BUILD_OBJECT(
                    'ok', TRUE,
                    'lead', TO_JSONB(v_lead)
                );
            END IF;
        END IF;

        v_resultados := v_resultados || JSONB_BUILD_ARRAY(
            JSONB_BUILD_OBJECT(
                'ok', TRUE,
                'processado', TRUE,
                'duplicado', FALSE,
                'acao', v_acao,
                'instancia', v_instancia_nome,
                'empresa_instancia_id', v_empresa_instancia_id,
                'empresa_id', v_empresa_id,
                'lead_id', v_lead.id,
                'telefone_cliente', v_telefone,
                'direcao', v_direcao,
                'mensagem_id', v_mensagem_externa_id,
                'resultado', v_retorno_acao
            )
        );
    END LOOP;

    RETURN JSONB_BUILD_OBJECT(
        'ok', TRUE,
        'quantidade', JSONB_ARRAY_LENGTH(v_itens),
        'resultados', v_resultados
    );
END;
$$;

COMMENT ON FUNCTION public.prospectflow_processar_webhook(JSONB) IS
'Processa eventos normalizados da Evolution API em uma unica transacao: resolve instancia, empresa e lead, impede duplicidade e atualiza a conversa.';

REVOKE ALL ON FUNCTION public.prospectflow_processar_webhook(JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prospectflow_processar_webhook(JSONB) TO service_role;

COMMIT;

