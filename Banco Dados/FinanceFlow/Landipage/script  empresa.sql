BEGIN;

-- confira antes
SELECT 'transacoes' tabela, count(*) FROM public.transacoes WHERE empresa_id = 5
UNION ALL
SELECT 'conciliacao_financeira', count(*) FROM public.conciliacao_financeira WHERE empresa_id = 5
UNION ALL
SELECT 'contas_a_pagar', count(*) FROM public.contas_a_pagar WHERE empresa_id = 5
UNION ALL
SELECT 'contas_recorrentes', count(*) FROM public.contas_recorrentes WHERE empresa_id = 5;

-- =========================
-- LIMPEZA EMPRESA 5
-- =========================

DELETE FROM public.transferencia_contas WHERE empresa_id = 5;

DELETE FROM public.conta_pagar_receber_conciliacao WHERE empresa_id = 5;
DELETE FROM public.conciliacao_cartoes WHERE empresa_id = 5;
DELETE FROM public.conciliacao_financeira WHERE empresa_id = 5;
DELETE FROM public.lote_conciliacao WHERE empresa_id = 5;
DELETE FROM public.cartao_importacoes WHERE empresa_id = 5;

DELETE FROM public.contas_recorrentes_geradas WHERE empresa_id = 5;
DELETE FROM public.contas_recorrentes WHERE empresa_id = 5;

DELETE FROM public.cartoes_transacoes WHERE empresa_id = 5;
DELETE FROM public.cartoes_compras WHERE empresa_id = 5;
DELETE FROM public.cartoes_faturas WHERE empresa_id = 5;
DELETE FROM public.cartoes WHERE empresa_id = 5;

DELETE FROM public.contas_a_pagar WHERE empresa_id = 5;
DELETE FROM public.contas_a_receber WHERE empresa_id = 5;
DELETE FROM public.transacoes WHERE empresa_id = 5;

DELETE FROM public.config_meios_recebimento WHERE empresa_id = 5;
DELETE FROM public.regras_classificacao_contabil WHERE empresa_id = 5;
DELETE FROM public.regras_mesma_titularidade WHERE empresa_id = 5;

DELETE FROM public.ia_consumo WHERE empresa_id = 5;
DELETE FROM public.ia_historico WHERE empresa_id = 5;

DELETE FROM public.contas_financeiras WHERE empresa_id = 5;
DELETE FROM public.categorias_gerenciais WHERE empresa_id = 5;
DELETE FROM public.pessoa WHERE empresa_id = 5;

-- =========================
-- CONTÁBIL
-- =========================

DELETE FROM contab.tributos_apuracoes_itens WHERE empresa_id = 5;
DELETE FROM contab.tributos_apuracoes WHERE empresa_id = 5;
DELETE FROM contab.tributo_apuracao WHERE empresa_id = 5;
DELETE FROM contab.tributo_obrigacoes WHERE empresa_id = 5;
DELETE FROM contab.tributos_regras_contabeis WHERE empresa_id = 5;
DELETE FROM contab.tributos_vigencias WHERE empresa_id = 5;
DELETE FROM contab.tributo_aliquotas WHERE empresa_id = 5;
DELETE FROM contab.tributos WHERE empresa_id = 5;

DELETE FROM contab.lancamentos WHERE empresa_id = 5;
DELETE FROM contab.apuracoes_resultado WHERE empresa_id = 5;
DELETE FROM contab.saldos_iniciais WHERE empresa_id = 5;
DELETE FROM contab.controle_fechamento WHERE empresa_id = 5;
DELETE FROM contab.lembretes WHERE empresa_id = 5;
DELETE FROM contab.diario_staging WHERE empresa_id = 5;
DELETE FROM contab.diario WHERE empresa_id = 5;

DELETE FROM contab.modelos_linhas WHERE empresa_id = 5;
DELETE FROM contab.modelos WHERE empresa_id = 5;
DELETE FROM contab.contas WHERE empresa_id = 5;

-- =========================
-- SAAS / VÍNCULOS
-- =========================

DELETE FROM saas_vendas.pagamentos WHERE empresa_id = 5;
DELETE FROM saas_vendas.cobrancas WHERE empresa_id = 5;
DELETE FROM saas_vendas.assinaturas WHERE empresa_id = 5;

DELETE FROM public.empresa_perfil WHERE empresa_id = 5;
DELETE FROM public.usuario_empresa WHERE empresa_id = 5;

-- só apague a empresa se quiser remover ela de verdade
-- DELETE FROM public.empresas WHERE id = 5;

COMMIT;