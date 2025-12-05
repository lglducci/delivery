INSERT INTO "public"."empresas" ( "nome", "tipo", "documento", "criado_em") 
VALUES ( 'Dona Ivone Massas', 'MEI', 'TESTE', '2025-12-03 17:28:27.291616');


INSERT INTO "public"."usuarios" ( "empresa_id", "nome", "email", "senha_hash", "criado_em") 
VALUES (1,  'Rinaldo Vianna Piedade', 'rinaldo@hotmail.com', 'admin', '2025-12-03 17:28:03.021648');


INSERT INTO "public"."usuario_empresa" ("empresa_id", "usuario_id",   "role", "escolha") 
VALUES ('1', '1',  'admin', 'true');