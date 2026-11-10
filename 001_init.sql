CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE role_kind AS ENUM ('DESENVOLVEDOR','ADMINISTRACAO','PORTARIA');
CREATE TYPE bond_kind AS ENUM ('PROPRIETARIO','INQUILINO','FAMILIAR');
CREATE TYPE phone_kind AS ENUM ('CELULAR','TELEFONE');
CREATE TYPE phone_label AS ENUM ('PRINCIPAL','CONJUGE','FAMILIAR','OUTRO');
CREATE TYPE occurrence_status AS ENUM ('ABERTA','EM_ANALISE','RESOLVIDA');

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), username text NOT NULL, email text, full_name text NOT NULL,
  password_hash text NOT NULL, role role_kind NOT NULL, active boolean NOT NULL DEFAULT true,
  locked_until timestamptz, failed_attempts int NOT NULL DEFAULT 0, last_login_at timestamptz,
  created_by uuid REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);
CREATE UNIQUE INDEX users_username_uq ON users (lower(username)) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_email_uq ON users (lower(email)) WHERE email IS NOT NULL AND deleted_at IS NULL;

CREATE TABLE sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE, ip text, user_agent text, created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL, revoked_at timestamptz
);
CREATE INDEX sessions_user_idx ON sessions (user_id);

CREATE TABLE login_attempts (
  id bigserial PRIMARY KEY, identifier text NOT NULL, ip text, success boolean NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_attempts_idx ON login_attempts (lower(identifier), created_at DESC);

CREATE TABLE password_resets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE, expires_at timestamptz NOT NULL, used_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE permissions (code text PRIMARY KEY, description text NOT NULL, grp text NOT NULL);
CREATE TABLE role_permissions (
  role role_kind NOT NULL, permission_code text NOT NULL REFERENCES permissions(code) ON DELETE CASCADE,
  allowed boolean NOT NULL DEFAULT true, updated_by uuid REFERENCES users(id), updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (role, permission_code)
);

CREATE TABLE blocks (id serial PRIMARY KEY, name text NOT NULL, active boolean NOT NULL DEFAULT true, deleted_at timestamptz);
CREATE UNIQUE INDEX blocks_name_uq ON blocks (lower(name)) WHERE deleted_at IS NULL;
CREATE TABLE units (
  id serial PRIMARY KEY, block_id int NOT NULL REFERENCES blocks(id), number text NOT NULL, notes text,
  active boolean NOT NULL DEFAULT true, deleted_at timestamptz
);
CREATE UNIQUE INDEX units_block_number_uq ON units (block_id, lower(number)) WHERE deleted_at IS NULL;

CREATE TABLE residents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), unit_id int NOT NULL REFERENCES units(id), full_name text NOT NULL,
  cpf_encrypted text, email text, bond bond_kind NOT NULL DEFAULT 'PROPRIETARIO', active boolean NOT NULL DEFAULT true,
  admin_note text, created_by uuid REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);
CREATE INDEX residents_unit_idx ON residents (unit_id) WHERE deleted_at IS NULL;
CREATE INDEX residents_name_trgm ON residents USING gin (lower(full_name) gin_trgm_ops);

CREATE TABLE phones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), resident_id uuid NOT NULL REFERENCES residents(id) ON DELETE CASCADE,
  owner_name text NOT NULL, ddd text NOT NULL CHECK (ddd ~ '^[0-9]{2}$'), number text NOT NULL CHECK (number ~ '^[0-9]{8,9}$'),
  kind phone_kind NOT NULL DEFAULT 'CELULAR', label phone_label NOT NULL DEFAULT 'PRINCIPAL',
  is_priority boolean NOT NULL DEFAULT false, shared_with_unit boolean NOT NULL DEFAULT false, active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);
CREATE INDEX phones_resident_idx ON phones (resident_id) WHERE deleted_at IS NULL;
CREATE INDEX phones_digits_idx ON phones ((ddd || number) text_pattern_ops) WHERE deleted_at IS NULL;
CREATE INDEX phones_number_idx ON phones (number text_pattern_ops) WHERE deleted_at IS NULL;

CREATE FUNCTION enforce_max_phones() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.deleted_at IS NULL AND (SELECT count(*) FROM phones WHERE resident_id = NEW.resident_id AND deleted_at IS NULL AND id <> NEW.id) >= 4 THEN
    RAISE EXCEPTION 'Limite de 4 telefones por morador' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER phones_max_4 BEFORE INSERT OR UPDATE ON phones FOR EACH ROW EXECUTE FUNCTION enforce_max_phones();

CREATE TABLE observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), resident_id uuid REFERENCES residents(id), unit_id int REFERENCES units(id),
  category text NOT NULL, body text NOT NULL, created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz, deleted_at timestamptz,
  CHECK (resident_id IS NOT NULL OR unit_id IS NOT NULL)
);
CREATE INDEX observations_unit_idx ON observations (unit_id, created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX observations_resident_idx ON observations (resident_id, created_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE occurrences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), category text NOT NULL, description text NOT NULL,
  unit_id int REFERENCES units(id), status occurrence_status NOT NULL DEFAULT 'ABERTA', photo_url text,
  occurred_at timestamptz NOT NULL DEFAULT now(), created_by uuid NOT NULL REFERENCES users(id),
  resolved_by uuid REFERENCES users(id), resolved_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);
CREATE INDEX occurrences_status_idx ON occurrences (status, occurred_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE attendance_log (
  id bigserial PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id), resident_id uuid REFERENCES residents(id),
  unit_id int REFERENCES units(id),
  action text NOT NULL CHECK (action IN ('CONSULTA','WHATSAPP','LIGACAO_WHATSAPP','COPIAR_TELEFONE')),
  phone_id uuid REFERENCES phones(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX attendance_user_idx ON attendance_log (user_id, created_at DESC);
CREATE INDEX attendance_created_idx ON attendance_log (created_at DESC);

CREATE TABLE audit_logs (
  id bigserial PRIMARY KEY, user_id uuid REFERENCES users(id), action text NOT NULL, entity text NOT NULL, entity_id text,
  before_data jsonb, after_data jsonb, ip text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_created_idx ON audit_logs (created_at DESC);
CREATE INDEX audit_entity_idx ON audit_logs (entity, entity_id);
CREATE INDEX audit_user_idx ON audit_logs (user_id, created_at DESC);

INSERT INTO permissions (code, description, grp) VALUES
 ('residents.search','Buscar moradores','Portaria'),
 ('residents.view_phones','Ver telefones','Portaria'),
 ('residents.manage','Cadastrar e editar moradores','Cadastros'),
 ('residents.delete','Excluir moradores','Cadastros'),
 ('units.manage','Gerenciar blocos e apartamentos','Cadastros'),
 ('observations.create','Registrar observações','Portaria'),
 ('observations.edit','Editar observações','Portaria'),
 ('observations.delete','Excluir observações','Portaria'),
 ('occurrences.create','Registrar ocorrências','Portaria'),
 ('occurrences.manage','Acompanhar e resolver ocorrências','Administração'),
 ('import.run','Importar planilha de moradores','Administração'),
 ('reports.view','Ver relatórios','Administração'),
 ('audit.view','Ver histórico de ações','Administração'),
 ('users.manage_portaria','Gerenciar contas da Portaria','Usuários'),
 ('users.manage_all','Gerenciar todas as contas','Usuários'),
 ('permissions.manage','Configurar permissões dos perfis','Usuários');

INSERT INTO role_permissions (role, permission_code, allowed) SELECT 'DESENVOLVEDOR', code, true FROM permissions;
INSERT INTO role_permissions (role, permission_code, allowed) SELECT 'ADMINISTRACAO', code, code <> 'users.manage_all' FROM permissions;
INSERT INTO role_permissions (role, permission_code, allowed) SELECT 'PORTARIA', code,
  code IN ('residents.search','residents.view_phones','observations.create','occurrences.create') FROM permissions;
