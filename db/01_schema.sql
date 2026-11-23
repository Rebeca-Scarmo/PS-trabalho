-- ============================================================
-- SGF · Módulo Almoxarifado e Canteiro · U2 (Plan-Driven)
-- 01_schema.sql — DDL físico do DER mínimo (8 entidades, 3FN)
-- SGBD alvo: PostgreSQL 16. Ordem: executar antes dos demais.
-- Decisões (ver docs/dicionario_de_dados.md):
--   * valores monetários  -> NUMERIC(12,2)  (nunca FLOAT/DOUBLE)
--   * quantidades         -> NUMERIC(12,3)  (kg/m3 admitem fração)
--   * totais, %, divergência -> calculados (views), não armazenados
--   * SALDO_ESTOQUE.qtd_atual -> redundância controlada (trigger)
-- ============================================================
DROP SCHEMA IF EXISTS sgf CASCADE;
CREATE SCHEMA sgf;
SET search_path = sgf;

CREATE TABLE obra (
  id_obra     SERIAL PRIMARY KEY,
  nome        VARCHAR(80) NOT NULL,
  bairro      VARCHAR(60) NOT NULL,
  CONSTRAINT uq_obra_nome_bairro UNIQUE (nome, bairro)
);

CREATE TABLE usuario (
  id_usuario  SERIAL PRIMARY KEY,
  nome        VARCHAR(80) NOT NULL,
  perfil      VARCHAR(12) NOT NULL,
  CONSTRAINT ck_usuario_perfil
    CHECK (perfil IN ('ENGENHEIRO','ALMOXARIFE','ENCARREGADO'))
);

CREATE TABLE insumo (
  id_insumo       SERIAL PRIMARY KEY,
  codigo          VARCHAR(20)  NOT NULL,
  descricao       VARCHAR(120) NOT NULL,
  unidade_medida  VARCHAR(3)   NOT NULL,
  preco_ref       NUMERIC(12,2) NOT NULL,
  CONSTRAINT uq_insumo_codigo UNIQUE (codigo),
  CONSTRAINT ck_insumo_unidade
    CHECK (unidade_medida IN ('UN','KG','M','M2','M3','CJ','SC')),
  CONSTRAINT ck_insumo_preco CHECK (preco_ref >= 0)
);

CREATE TABLE requisicao (
  id_requisicao         SERIAL PRIMARY KEY,
  id_obra               INTEGER NOT NULL REFERENCES obra(id_obra),
  id_usuario_solicitante INTEGER NOT NULL REFERENCES usuario(id_usuario),
  data_emissao          TIMESTAMP NOT NULL DEFAULT now(),
  status                VARCHAR(10) NOT NULL DEFAULT 'EMITIDA',
  CONSTRAINT ck_requisicao_status CHECK (status IN ('EMITIDA','CONFERIDA'))
);

CREATE TABLE item_requisitado (
  id_item_requisitado SERIAL PRIMARY KEY,
  id_requisicao  INTEGER NOT NULL REFERENCES requisicao(id_requisicao),
  id_insumo      INTEGER NOT NULL REFERENCES insumo(id_insumo),
  qtd_pedida     NUMERIC(12,3) NOT NULL,
  preco_aplicado NUMERIC(12,2) NOT NULL,
  CONSTRAINT uq_item_req_insumo UNIQUE (id_requisicao, id_insumo),
  CONSTRAINT ck_item_qtd_pedida CHECK (qtd_pedida > 0),
  CONSTRAINT ck_item_preco CHECK (preco_aplicado >= 0)
);

CREATE TABLE conferencia (
  id_conferencia        SERIAL PRIMARY KEY,
  id_requisicao         INTEGER NOT NULL REFERENCES requisicao(id_requisicao),
  id_usuario_almoxarife INTEGER NOT NULL REFERENCES usuario(id_usuario),
  nf_numero             VARCHAR(20) NOT NULL,
  data_hora             TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE item_conferido (
  id_item_conferido   SERIAL PRIMARY KEY,
  id_conferencia      INTEGER NOT NULL REFERENCES conferencia(id_conferencia),
  id_item_requisitado INTEGER NOT NULL REFERENCES item_requisitado(id_item_requisitado),
  qtd_recebida  NUMERIC(12,3) NOT NULL,
  qtd_aprovada  NUMERIC(12,3) NOT NULL,
  status_item   VARCHAR(10)   NOT NULL,
  observacao    VARCHAR(200),
  CONSTRAINT uq_item_conf UNIQUE (id_conferencia, id_item_requisitado),
  CONSTRAINT ck_conf_recebida CHECK (qtd_recebida >= 0),
  CONSTRAINT ck_conf_aprovada CHECK (qtd_aprovada >= 0 AND qtd_aprovada <= qtd_recebida),
  CONSTRAINT ck_conf_status CHECK (status_item IN ('CONFERIDO','AVARIADO','AUSENTE')),
  CONSTRAINT ck_conf_ausente CHECK (status_item <> 'AUSENTE' OR qtd_aprovada = 0)
);

CREATE TABLE saldo_estoque (
  id_obra        INTEGER NOT NULL REFERENCES obra(id_obra),
  id_insumo      INTEGER NOT NULL REFERENCES insumo(id_insumo),
  qtd_atual      NUMERIC(12,3) NOT NULL DEFAULT 0,
  data_atualizacao TIMESTAMP NOT NULL DEFAULT now(),
  PRIMARY KEY (id_obra, id_insumo),
  CONSTRAINT ck_saldo_nao_negativo CHECK (qtd_atual >= 0)
);

-- Índices nas FKs usadas nas consultas do fluxo
CREATE INDEX ix_req_obra        ON requisicao(id_obra);
CREATE INDEX ix_itemreq_req     ON item_requisitado(id_requisicao);
CREATE INDEX ix_conf_req        ON conferencia(id_requisicao);
CREATE INDEX ix_itemconf_conf   ON item_conferido(id_conferencia);

-- Derivados: calculados na consulta, nunca armazenados
CREATE VIEW v_total_requisicao AS
  SELECT r.id_requisicao, r.id_obra,
         SUM(i.qtd_pedida * i.preco_aplicado)::NUMERIC(14,2) AS total
  FROM requisicao r JOIN item_requisitado i USING (id_requisicao)
  GROUP BY r.id_requisicao, r.id_obra;

CREATE VIEW v_divergencia AS
  SELECT c.id_conferencia, c.id_requisicao, ir.id_insumo,
         ir.qtd_pedida, ic.qtd_recebida, ic.qtd_aprovada, ic.status_item,
         (ir.qtd_pedida - ic.qtd_aprovada) AS divergencia
  FROM item_conferido ic
  JOIN conferencia c USING (id_conferencia)
  JOIN item_requisitado ir USING (id_item_requisitado);
