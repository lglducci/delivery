-- =====================================================================
-- 01_contab_grants.sql
-- Grants para Supabase (roles padrão): postgres, service_role, authenticated, anon
-- Nota: Recomenda-se usar RLS (Row Level Security) nas tabelas e POLICIES.
-- Aqui concedemos privilégios básicos seguros para authenticated e service_role.
-- =====================================================================
BEGIN;

-- Garantir schema e search_path
CREATE SCHEMA IF NOT EXISTS contab;
SET search_path = contab, public;

-- ---------------------------------------------------------------------
-- REVOKE + GRANT de schema
-- ---------------------------------------------------------------------
-- (Ajuste conforme sua política de segurança)
REVOKE ALL ON SCHEMA contab FROM PUBLIC;
GRANT USAGE ON SCHEMA contab TO postgres, service_role, authenticated;
GRANT ALL   ON SCHEMA contab TO postgres, service_role;

-- ---------------------------------------------------------------------
-- GRANT nas tabelas existentes (contas, parceiros, diario, modelos, modelos_linhas, lancamentos)
-- ---------------------------------------------------------------------
-- authenticated: CRUD básico
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  contas, parceiros, diario, modelos, modelos_linhas, lancamentos
TO authenticated;

-- service_role: acesso total (usar com cuidado em funções backend)
GRANT ALL ON TABLE
  contas, parceiros, diario, modelos, modelos_linhas, lancamentos
TO service_role;

-- anon: sem acesso por padrão (remova comentário se quiser abrir leitura)
-- GRANT SELECT ON TABLE
--   contas, parceiros, diario, modelos, modelos_linhas, lancamentos
-- TO anon;

-- ---------------------------------------------------------------------
-- SEQUENCES (para INSERT funcionar com authenticated)
-- ---------------------------------------------------------------------
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA contab TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA contab TO service_role;

-- ---------------------------------------------------------------------
-- DEFAULT PRIVILEGES: futuros objetos no schema herdam privilégios
-- (execute com um role proprietário do schema para surtir efeito)
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES IN SCHEMA contab
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA contab
GRANT ALL ON TABLES TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA contab
GRANT USAGE, SELECT ON SEQUENCES TO authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA contab
GRANT USAGE, SELECT ON SEQUENCES TO service_role;

-- ---------------------------------------------------------------------
-- RLS (opcional): habilitar e deixar políticas para outro script
-- ---------------------------------------------------------------------
-- ALTER TABLE contas ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE parceiros ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE diario ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE modelos ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE modelos_linhas ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE lancamentos ENABLE ROW LEVEL SECURITY;

COMMIT;
