-- =====================================================================
-- 02_contab_rls_policies.sql
-- Row Level Security (RLS) para Supabase
-- IMPORTANTE: O seu schema atual NÃO possui colunas de tenant/owner (ex.: org_id, user_id).
-- Estas políticas abaixo são PERMISSIVAS (USING true) apenas para demonstrar a ativação.
-- Em produção, substitua por políticas com filtros por organização/usuário.
-- =====================================================================
BEGIN;

SET search_path = contab, public;

-- Habilitar RLS nas tabelas

 ALTER TABLE contab.contas           ENABLE ROW LEVEL SECURITY; 
ALTER TABLE contab.diario           ENABLE ROW LEVEL SECURITY;
ALTER TABLE contab.modelos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE contab.modelos_linhas   ENABLE ROW LEVEL SECURITY;
ALTER TABLE contab.lancamentos      ENABLE ROW LEVEL SECURITY; 
ALTER TABLE contab.vinculos_modelo ENABLE ROW LEVEL SECURITY;


-- Remover políticas antigas (se existirem) para evitar conflitos ao re-rodar
 
 DROP POLICY IF EXISTS contab.contas_all_authenticated     ON contas;
 
DROP POLICY IF EXISTS contab.diario_all_authenticated     ON diario;
DROP POLICY IF EXISTS contab.modelos_all_authenticated    ON modelos;
DROP POLICY IF EXISTS contab.modelos_linhas_all_auth      ON modelos_linhas;
DROP POLICY IF EXISTS contab.lancamentos_all_authenticated ON lancamentos;

DROP POLICY IF EXISTS contab.contas_all_service           ON contas;
 
DROP POLICY IF EXISTS contab.diario_all_service           ON diario;
DROP POLICY IF EXISTS contab.modelos_all_service          ON modelos;
DROP POLICY IF EXISTS contab.modelos_linhas_all_service   ON modelos_linhas;
DROP POLICY IF EXISTS contab.lancamentos_all_service      ON lancamentos;

 



-- Políticas PERMISSIVAS para authenticated (ajuste depois com filtros reais)
CREATE POLICY contas_all_authenticated
  ON contab.contas FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);
 

CREATE POLICY diario_all_authenticated
  ON contab.diario FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY  modelos_all_authenticated
  ON contab.modelos FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY  modelos_linhas_all_auth
  ON contab.modelos_linhas FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

CREATE POLICY lancamentos_all_authenticated
  ON contab.lancamentos FOR ALL
  TO authenticated
  USING (true) WITH CHECK (true);

-- Políticas amplas para service_role (uso backend)
CREATE POLICY contas_all_service
  ON contab.contas FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);
 

CREATE POLICY diario_all_service
  ON contab.diario FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY modelos_all_service
  ON contab.modelos FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY modelos_linhas_all_service
  ON contab.modelos_linhas FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY lancamentos_all_service
  ON contab.lancamentos FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

COMMIT;

 
 

COMMIT;

-- NOTA:
-- Para multi-tenant adequado, adicione colunas como org_id nas tabelas e crie
-- políticas do tipo: USING (org_id = auth.jwt() ->> 'org_id') com as claims corretas.
