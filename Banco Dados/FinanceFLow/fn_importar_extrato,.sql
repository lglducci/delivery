 CREATE OR REPLACE FUNCTION public.fn_importar_extrato(
    p_empresa_id bigint,
    p_conta_financeira_id bigint,
    p_lancamentos jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_item jsonb;
    v_data date;
    v_historico text;
    v_valor numeric(14,2);
   v_cnpj text;
    v_tipo varchar(10);
    v_forma varchar(30);
    v_classificacao varchar(50);
    v_tipo_evento varchar(30);
    v_categoria_id bigint;
    v_fornecedor_id bigint;
    v_modelo_codigo varchar(50);
    v_tipo_destino varchar(30);
    v_destino_id bigint;
    v_nome_fornecedor   text;
    v_chave_importacao text;
    v_duplicado boolean;
      v_lote_conciliacao_id bigint;
    v_qtd integer := 0;
BEGIN

 v_lote_conciliacao_id := nextval('public.conciliacao_lote_seq');

INSERT INTO public.lote_conciliacao (
  empresa_id,
  conta_financeira_id,
  data_ini,
  data_fim,
  status
)
VALUES (
  p_empresa_id,
  p_conta_financeira_id,
  null,
  null,
  'aberto'
)
RETURNING id INTO v_lote_conciliacao_id;
 
/*DELETE FROM public.transferencia_mesma_titularidade_pendente t
USING public.conciliacao_financeira c
WHERE t.empresa_id = c.empresa_id
  AND t.conciliacao_id = c.id
  AND c.empresa_id = p_empresa_id
  AND c.conta_financeira_id = p_conta_financeira_id
  AND COALESCE(c.status_conciliacao, 'pendente') IN ('pendente', 'rejeitado', 'ok')
  AND c.transacao_id IS NULL;*/


    DELETE FROM public.conciliacao_financeira
    WHERE empresa_id = p_empresa_id
      AND conta_financeira_id = p_conta_financeira_id
      AND COALESCE(status_conciliacao, 'pendente') IN ('pendente', 'rejeitado', 'ok')
      AND transacao_id IS NULL;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_lancamentos)
    LOOP
        v_data := (v_item->>'data')::date;
        v_historico := trim(coalesce(v_item->>'historico', '')); 
       -- extrai CNPJ do texto
       v_cnpj := substring(
       v_historico from '\d{2}\.?\d{3}\.?\d{3}[\s\/]?\d{4}-?\d{2}');

       v_cnpj := public.fn_limpa_cnpj(v_cnpj);
        v_valor := coalesce((v_item->>'valor')::numeric, 0);
        -- IGNORA LINHAS DE SALDO DO EXTRATO
       IF unaccent(upper(v_historico)) LIKE '%SALDO%' THEN
             CONTINUE;
        END IF;
        v_categoria_id := NULL;
        v_fornecedor_id := NULL;
        v_modelo_codigo := NULL;
        v_tipo_destino := NULL;
        v_destino_id := NULL;

        IF v_valor >= 0 THEN
            v_tipo := 'entrada';
        ELSE
            v_tipo := 'saida';
        END IF;

        IF upper(v_historico) LIKE '%PIX%' THEN
            v_forma := 'pix';
        ELSIF upper(v_historico) LIKE '%BOLETO%' THEN
            v_forma := 'boleto';
       ELSIF upper(v_historico) LIKE '%CHEQUE%' THEN
            v_forma := 'avista';
        ELSIF upper(v_historico) LIKE '%CARTAO%'
           OR upper(v_historico) LIKE '%CARD%' THEN
            v_forma := 'cartao_credito';
        ELSIF upper(v_historico) LIKE '%DEBITO%' THEN
            v_forma := 'cartao_debito';
        ELSIF upper(v_historico) LIKE '%EMPRESTIMO%'
           OR upper(v_historico) LIKE '%FINANCIAMENTO%' THEN
            v_forma := 'aprazo';
        ELSE
            v_forma := 'avista';
        END IF;

        IF v_tipo = 'entrada' THEN
            v_classificacao := 'receita';
        ELSE
            v_classificacao := 'despesa';
        END IF;

        IF upper(v_historico) LIKE '%RENDIMENTO%'
           OR upper(v_historico) LIKE '%JUROS%'
           OR upper(v_historico) LIKE '%IOF%' THEN
            v_tipo_evento := 'juros';

        ELSIF upper(v_historico) LIKE '%PAGAMENTO CARTAO%'
           OR upper(v_historico) LIKE '%FAT.CARTAO%'
           OR upper(v_historico) LIKE '%FAT CARTAO%'
           OR upper(v_historico) LIKE '%MASTER CARD%'
           OR upper(v_historico) LIKE '%VISA%' THEN
            v_tipo_evento := 'pagar_fatura';

        ELSIF upper(v_historico) LIKE '%GETNET%'
           OR upper(v_historico) LIKE '%ANTECIPACAO GETNET%' THEN
            v_tipo_evento := 'receber_cartao';

        ELSIF v_tipo = 'saida'
           AND (
                upper(v_historico) LIKE '%PAGAMENTO%'
                OR upper(v_historico) LIKE '%BOLETO%'
                OR upper(v_historico) LIKE '%DEBITO AUT%'
                OR upper(v_historico) LIKE '%EMPRESTIMO%'
                OR upper(v_historico) LIKE '%FINANCIAMENTO%'
                OR upper(v_historico) LIKE '%BENEFI%'
           ) THEN
            v_tipo_evento := 'pagar';

        ELSIF v_tipo = 'entrada'
           AND (
                upper(v_historico) LIKE '%PIX RECEBIDO%'
                OR upper(v_historico) LIKE '%TED RECEBIDA%'
                OR upper(v_historico) LIKE '%TRANSFERENCIA RECEBIDA%'
           ) THEN
            v_tipo_evento := 'receber';

        ELSE
            v_tipo_evento := 'financeiro';
        END IF;

        -- BLOQUEIO DE TRANSFERÊNCIA ENTRE CONTAS
       IF   upper(v_historico) LIKE '%TRANSF%'
          OR upper(v_historico) LIKE '%TRANSFER%'
          OR upper(v_historico) LIKE '%TED%'
        OR upper(v_historico) LIKE '%DOC%' THEN
            v_tipo_evento := 'transferencia';
           v_classificacao := 'financeiro';
      END IF;


 

      -- PRIORIDADE: buscar por CNPJ
     IF v_cnpj IS NOT NULL AND length(v_cnpj) = 14 THEN
              SELECT id
                   INTO v_fornecedor_id
              FROM public.pessoa
           WHERE empresa_id = p_empresa_id
                AND public.fn_limpa_cnpj(cpf_cnpj) = v_cnpj
               LIMIT 1;
       END IF;

        v_nome_fornecedor := trim(
        regexp_replace(
            v_historico,
            '.*\d{2}\.?\d{3}\.?\d{3}[\s\/]?\d{4}-?\d{2}',
            '',
            'g'
        )
        );

            IF v_nome_fornecedor IS NULL OR length(v_nome_fornecedor) < 3 THEN
            v_nome_fornecedor := left(v_historico, 80);
            END IF;

        IF v_fornecedor_id IS NULL and length(v_cnpj) = 14 THEN
       	   INSERT INTO pessoa (empresa_id, nome, cpf_cnpj, tipo)
       		  VALUES (p_empresa_id,  v_nome_fornecedor  , v_cnpj, 'fornecedor')
		    RETURNING id INTO v_fornecedor_id;
	    END IF;
        
     -- 1) procura por CNPJ/CPF primeiro
        IF v_cnpj IS NOT NULL AND length(v_cnpj) IN (11, 14) THEN
            SELECT p.id
            INTO v_fornecedor_id
            FROM public.pessoa p
            WHERE p.empresa_id = p_empresa_id
            AND regexp_replace(coalesce(p.cpf_cnpj, ''), '\D', '', 'g') = v_cnpj
            LIMIT 1;
        END IF;

            -- 2) se não achou, procura por nome
            IF v_fornecedor_id IS NULL THEN
                SELECT x.id
                INTO v_fornecedor_id
                FROM (
                    SELECT
                        p.id,
                        p.nome,
                        CASE
                            WHEN unaccent(upper(v_historico)) LIKE '%' || unaccent(upper(p.nome)) || '%'
                                THEN 100
                            WHEN unaccent(upper(p.nome)) LIKE '%' || unaccent(upper(v_historico)) || '%'
                                THEN 90
                            ELSE similarity(
                                unaccent(lower(v_historico)),
                                unaccent(lower(p.nome))
                            ) * 100
                        END AS score
                    FROM public.pessoa p
                    WHERE p.empresa_id = p_empresa_id
                    AND coalesce(trim(p.nome), '') <> ''
                ) x
                WHERE x.score >= 45
                ORDER BY x.score DESC, length(x.nome) DESC
                LIMIT 1;
            END IF;

        SELECT c.id
        INTO v_categoria_id
        FROM public.categorias_gerenciais c
        WHERE c.empresa_id = p_empresa_id
          AND upper(v_historico) LIKE '%' || upper(c.nome) || '%'
        ORDER BY length(c.nome) DESC
        LIMIT 1;

        v_chave_importacao := md5(
            p_empresa_id::text || '|' ||
            p_conta_financeira_id::text || '|' ||
            v_data::text || '|' ||
            upper(trim(regexp_replace(coalesce(v_historico, ''), '\s+', ' ', 'g'))) || '|' ||
            round(v_valor::numeric, 2)::text
        );

        SELECT EXISTS (
            SELECT 1
            FROM public.conciliacao_financeira ja
            WHERE ja.chave_importacao = v_chave_importacao
        )
        INTO v_duplicado;

        -- BLOQUEIO SOMENTE SE EXISTIR NA CONFIGURAÇÃO DE MESMA TITULARIDADE
  -- TRANSFERÊNCIA MESMA TITULARIDADE
IF EXISTS (
  SELECT 1
  FROM public.regras_mesma_titularidade r
  WHERE r.empresa_id = p_empresa_id
    AND r.ativo = true
    AND (
      (
        length(public.fn_limpa_cnpj(coalesce(r.cpf_cnpj,''))) = 14
        AND length(public.fn_limpa_cnpj(coalesce(v_cnpj,''))) = 14
        AND public.fn_limpa_cnpj(r.cpf_cnpj) = public.fn_limpa_cnpj(v_cnpj)
      )
      OR (
        coalesce(trim(r.nome), '') <> ''
        AND length(trim(r.nome)) >= 8
        AND unaccent(upper(v_historico)) LIKE '%' || unaccent(upper(trim(r.nome))) || '%'
      )
      OR (
        coalesce(trim(r.apelido), '') <> ''
        AND length(trim(r.apelido)) >= 5
        AND unaccent(upper(v_historico)) LIKE '%' || unaccent(upper(trim(r.apelido))) || '%'
      )
    )
) THEN
    v_tipo_evento := 'transf_mesma_tit';
    v_classificacao := 'financeiro';
END IF;

        INSERT INTO public.conciliacao_financeira (
            empresa_id,
            conta_financeira_id,
            data_mov,
            historico,
            valor,
            tipo,
            forma,
            classificacao,
            categoria_id,
            fornecedor_id,
            modelo_codigo,
            tipo_evento,
            tipo_destino,
            destino_id,
            chave_importacao,
            importar,
            status_conciliacao,
            mensagem_conciliacao ,
            lote_conciliacao_id
        )
        VALUES (
            p_empresa_id,
            p_conta_financeira_id,
            v_data,
            v_historico,
            v_valor,
            v_tipo,
            v_forma,
            v_classificacao,
            v_categoria_id,
            v_fornecedor_id,
            v_modelo_codigo,
            v_tipo_evento,
            v_tipo_destino,
            v_destino_id,
            v_chave_importacao,

            CASE
                WHEN v_tipo_evento = 'transf_mesma_tit' THEN false
                WHEN v_duplicado THEN false
                ELSE true
            END,

        CASE 
           WHEN v_duplicado THEN 'rejeitado'
             WHEN v_tipo_evento = 'transf_mesma_tit' THEN 'rejeitado'
            ELSE 'pendente'
        END,
         CASE
                WHEN v_duplicado = true THEN
                    'Registro duplicado: esta linha já foi importada anteriormente'

                WHEN v_tipo_evento = 'transf_mesma_tit'
                    AND COALESCE(v_duplicado, false) = false THEN
                    'Transferência entre contas: lançar manualmente informando conta origem e destino'

                ELSE
                    'Linha importada para revisão'
            END,
            v_lote_conciliacao_id
        );

        v_qtd := v_qtd + 1;
    END LOOP;
 
 UPDATE public.lote_conciliacao l
SET
  data_ini = x.data_ini,
  data_fim = x.data_fim,
  total_linhas = x.total_linhas,
  total_valor = x.total_valor
FROM (
  SELECT
    lote_conciliacao_id,
    MIN(data_mov)::date AS data_ini,
    MAX(data_mov)::date AS data_fim,
    COUNT(*)::integer AS total_linhas,
    COALESCE(SUM(valor), 0)::numeric(15,2) AS total_valor
  FROM public.conciliacao_financeira
  WHERE empresa_id = p_empresa_id
    AND conta_financeira_id = p_conta_financeira_id
    AND lote_conciliacao_id = v_lote_conciliacao_id
  GROUP BY lote_conciliacao_id
) x
WHERE l.id = x.lote_conciliacao_id
  AND l.empresa_id = p_empresa_id
  AND l.conta_financeira_id = p_conta_financeira_id;
   

    RETURN jsonb_build_object(
        'ok', true,
        'empresa_id', p_empresa_id,
        'conta_financeira_id', p_conta_financeira_id,
        'linhas_processadas', v_qtd
    );
END;
$$;