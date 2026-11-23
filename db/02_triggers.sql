-- 02_triggers.sql — regras de integridade que o SGBD impõe
SET search_path = sgf;

-- T1: a conferência só é aceita para requisição existente e ainda EMITIDA
CREATE FUNCTION fn_conferencia_valida() RETURNS trigger AS $$
DECLARE v_status TEXT;
BEGIN
  SELECT status INTO v_status FROM requisicao WHERE id_requisicao = NEW.id_requisicao;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Requisição % inexistente', NEW.id_requisicao USING ERRCODE = '23503';
  ELSIF v_status <> 'EMITIDA' THEN
    RAISE EXCEPTION 'Requisição % já foi conferida', NEW.id_requisicao USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_conferencia_valida BEFORE INSERT ON conferencia
  FOR EACH ROW EXECUTE FUNCTION fn_conferencia_valida();

-- T2: o item conferido precisa pertencer à MESMA requisição da conferência
CREATE FUNCTION fn_item_conferido_valida() RETURNS trigger AS $$
DECLARE v_req_conf INT; v_req_item INT;
BEGIN
  SELECT id_requisicao INTO v_req_conf FROM conferencia WHERE id_conferencia = NEW.id_conferencia;
  SELECT id_requisicao INTO v_req_item FROM item_requisitado WHERE id_item_requisitado = NEW.id_item_requisitado;
  IF v_req_conf IS DISTINCT FROM v_req_item THEN
    RAISE EXCEPTION 'Item % não pertence à requisição % da conferência %',
      NEW.id_item_requisitado, v_req_conf, NEW.id_conferencia USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_item_conferido_valida BEFORE INSERT ON item_conferido
  FOR EACH ROW EXECUTE FUNCTION fn_item_conferido_valida();

-- T3: RF5 — o saldo só cresce com a quantidade APROVADA (mesma transação)
CREATE FUNCTION fn_saldo_incrementa() RETURNS trigger AS $$
DECLARE v_obra INT; v_insumo INT;
BEGIN
  SELECT r.id_obra, ir.id_insumo INTO v_obra, v_insumo
    FROM item_requisitado ir JOIN requisicao r USING (id_requisicao)
   WHERE ir.id_item_requisitado = NEW.id_item_requisitado;
  INSERT INTO saldo_estoque (id_obra, id_insumo, qtd_atual, data_atualizacao)
       VALUES (v_obra, v_insumo, NEW.qtd_aprovada, now())
  ON CONFLICT (id_obra, id_insumo)
  DO UPDATE SET qtd_atual = saldo_estoque.qtd_atual + EXCLUDED.qtd_atual,
                data_atualizacao = now();
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_saldo_incrementa AFTER INSERT ON item_conferido
  FOR EACH ROW EXECUTE FUNCTION fn_saldo_incrementa();

-- T4: o saldo NÃO pode ser alterado diretamente; só via T3 (profundidade >= 2)
CREATE FUNCTION fn_saldo_guarda() RETURNS trigger AS $$
BEGIN
  IF pg_trigger_depth() < 2 THEN
    RAISE EXCEPTION 'SALDO_ESTOQUE só pode ser alterado por uma conferência' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_saldo_guarda BEFORE INSERT OR UPDATE OR DELETE ON saldo_estoque
  FOR EACH ROW EXECUTE FUNCTION fn_saldo_guarda();

-- T5: conferência e itens conferidos são trilha de auditoria (imutáveis)
CREATE FUNCTION fn_imutavel() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION '% é imutável (trilha de auditoria)', TG_TABLE_NAME USING ERRCODE = '42501';
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_conferencia_imutavel BEFORE UPDATE OR DELETE ON conferencia
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel();
CREATE TRIGGER trg_item_conferido_imutavel BEFORE UPDATE OR DELETE ON item_conferido
  FOR EACH ROW EXECUTE FUNCTION fn_imutavel();

-- T6: ao registrar a conferência completa, a requisição passa a CONFERIDA
CREATE FUNCTION fn_fecha_requisicao() RETURNS trigger AS $$
BEGIN
  UPDATE requisicao SET status = 'CONFERIDA' WHERE id_requisicao = NEW.id_requisicao;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_fecha_requisicao AFTER INSERT ON conferencia
  FOR EACH ROW EXECUTE FUNCTION fn_fecha_requisicao();

-- T7: cardinalidades mínimas (1,N) do DER, verificadas no COMMIT
--     requisição precisa ter >= 1 item; conferência precisa ter >= 1 item conferido
CREATE FUNCTION fn_requisicao_tem_item() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM item_requisitado WHERE id_requisicao = NEW.id_requisicao) THEN
    RAISE EXCEPTION 'Requisição % sem itens (cardinalidade mínima 1,N)', NEW.id_requisicao USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE CONSTRAINT TRIGGER ctg_requisicao_tem_item AFTER INSERT ON requisicao
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION fn_requisicao_tem_item();

CREATE FUNCTION fn_conferencia_tem_item() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM item_conferido WHERE id_conferencia = NEW.id_conferencia) THEN
    RAISE EXCEPTION 'Conferência % sem itens (cardinalidade mínima 1,N)', NEW.id_conferencia USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE CONSTRAINT TRIGGER ctg_conferencia_tem_item AFTER INSERT ON conferencia
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION fn_conferencia_tem_item();
