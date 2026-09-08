INSERT INTO "contab"."conta_classificacao" ("empresa_id", "conta_codigo", "tipo_dre", "fixo_variavel", "natureza", "tipo_contab", "nome") 
VALUES ('1', '4.1', 'RECEITA_BRUTA', null, 'C', 'RECEITA', 'Vendas'), ('1', '4.1.9', 'DED_RECEITA', null, 'D', 'RECEITA', 'Impostos s/ venda'), 
('1', '5.1', 'CMV_CSP', 'VARIAVEL', 'D', 'CUSTO', 'CMV Bebidas'), ('1', '5.2', 'CMV_CSP', 'VARIAVEL', 'D', 'CUSTO', 'CMV Refeições'), 
('1', '6.1', 'DESPESA_FIXA', 'FIXO', 'D', 'DESPESA', 'Pessoal'), ('1', '6.3', 'DESPESA_FIXA', 'FIXO', 'D', 'DESPESA', 'Administrativo'), 
('1', '6.4', 'DESPESA_VARIAVEL', 'VARIAVEL', 'D', 'DESPESA', 'Marketing');