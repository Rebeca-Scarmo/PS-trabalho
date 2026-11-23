-- tests/01_testes.sql — testes de COMPONENTE (CT) e de SISTEMA (ST) no SGBD
-- Roda tudo em UMA transação e termina em ROLLBACK (o banco volta ao seed).
\set ON_ERROR_STOP on
\pset format aligned
BEGIN;
SET search_path = sgf, public;

\o :nulo
CREATE TEMP TABLE resultado (ordem serial, id text, nivel text, descricao text, esperado text, obtido text, ok boolean);

-- helper: espera que `sql` falhe com o SQLSTATE informado
CREATE FUNCTION pg_temp.espera_erro(p_id text, p_nivel text, p_desc text, p_sql text, p_estado text) RETURNS void AS $$
DECLARE v_estado text := 'nenhum erro';
BEGIN
  BEGIN
    EXECUTE p_sql;
    EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE';
  EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE;
  END;
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  INSERT INTO resultado(id,nivel,descricao,esperado,obtido,ok)
  VALUES (p_id,p_nivel,p_desc,'erro '||p_estado,v_estado, v_estado = p_estado);
END $$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.espera(p_id text, p_nivel text, p_desc text, p_esperado text, p_obtido text) RETURNS void AS $$
BEGIN
  INSERT INTO resultado(id,nivel,descricao,esperado,obtido,ok)
  VALUES (p_id,p_nivel,p_desc,p_esperado,p_obtido, COALESCE(p_esperado = p_obtido, false));
END $$ LANGUAGE plpgsql;

-- helper: cria requisição com 1 item (insumo por código) e devolve id_item_requisitado
CREATE FUNCTION pg_temp.nova_req(p_obra text, p_cod text, p_qtd numeric, OUT p_req int, OUT p_item int) AS $$
DECLARE v_ins int; v_prc numeric;
BEGIN
  SELECT id_insumo, preco_ref INTO v_ins, v_prc FROM insumo WHERE codigo = p_cod;
  INSERT INTO requisicao(id_obra,id_usuario_solicitante)
    VALUES ((SELECT id_obra FROM obra WHERE nome = p_obra),(SELECT id_usuario FROM usuario WHERE perfil='ENGENHEIRO'))
    RETURNING id_requisicao INTO p_req;
  INSERT INTO item_requisitado(id_requisicao,id_insumo,qtd_pedida,preco_aplicado)
    VALUES (p_req, v_ins, p_qtd, v_prc) RETURNING id_item_requisitado INTO p_item;
END $$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.conferir(p_req int, p_item int, p_rec numeric, p_apr numeric, p_st text) RETURNS int AS $$
DECLARE v_conf int;
BEGIN
  INSERT INTO conferencia(id_requisicao,id_usuario_almoxarife,nf_numero)
    VALUES (p_req,(SELECT id_usuario FROM usuario WHERE perfil='ALMOXARIFE'),'NF-TESTE') RETURNING id_conferencia INTO v_conf;
  INSERT INTO item_conferido(id_conferencia,id_item_requisitado,qtd_recebida,qtd_aprovada,status_item)
    VALUES (v_conf,p_item,p_rec,p_apr,p_st);
  RETURN v_conf;
END $$ LANGUAGE plpgsql;

-- =============== COMPONENTE (restrições, tipagem e triggers isolados) ===============
DO $$
DECLARE r record; c int; s numeric; n0 int;
BEGIN
  -- base para os testes de restrição: uma requisição de brita para o Hospital
  SELECT * INTO r FROM pg_temp.nova_req('Hospital','BRI-001',13);
  PERFORM set_config('t.req', r.p_req::text, true);
  PERFORM set_config('t.item', r.p_item::text, true);
END $$;

SELECT pg_temp.espera_erro('CT-01','Componente','TC-REG-03: aprovada (15) > recebida (12) é rejeitada (CHECK)',
 format($q$ SELECT pg_temp.conferir(%s,%s,12,15,'CONFERIDO') $q$, current_setting('t.req'), current_setting('t.item')),'23514');
SELECT pg_temp.espera_erro('CT-02','Componente','Quantidade recebida negativa é rejeitada (CHECK)',
 format($q$ SELECT pg_temp.conferir(%s,%s,-1,0,'CONFERIDO') $q$, current_setting('t.req'), current_setting('t.item')),'23514');
SELECT pg_temp.espera_erro('CT-03','Componente','Status de item fora do domínio é rejeitado (CHECK)',
 format($q$ SELECT pg_temp.conferir(%s,%s,12,12,'OK') $q$, current_setting('t.req'), current_setting('t.item')),'23514');
SELECT pg_temp.espera_erro('CT-04','Componente','AUSENTE com quantidade aprovada > 0 é rejeitado (CHECK)',
 format($q$ SELECT pg_temp.conferir(%s,%s,5,5,'AUSENTE') $q$, current_setting('t.req'), current_setting('t.item')),'23514');
SELECT pg_temp.espera_erro('CT-05','Componente','Código de insumo duplicado é rejeitado (UNIQUE)',
 $q$ INSERT INTO insumo(codigo,descricao,unidade_medida,preco_ref) VALUES ('CIM-001','Cimento duplicado','UN',1) $q$,'23505');
SELECT pg_temp.espera_erro('CT-06','Componente','Unidade suja ("M " / "PÇ") é rejeitada (CHECK de domínio)',
 $q$ INSERT INTO insumo(codigo,descricao,unidade_medida,preco_ref) VALUES ('X-1','Teste','PÇ',1) $q$,'23514');
SELECT pg_temp.espera_erro('CT-07','Componente','Preço de referência negativo é rejeitado (CHECK)',
 $q$ INSERT INTO insumo(codigo,descricao,unidade_medida,preco_ref) VALUES ('X-2','Teste','UN',-0.01) $q$,'23514');
SELECT pg_temp.espera_erro('CT-08','Componente','Quantidade pedida igual a zero é rejeitada (CHECK)',
 format($q$ INSERT INTO item_requisitado(id_requisicao,id_insumo,qtd_pedida,preco_aplicado) VALUES (%s,1,0,1) $q$, current_setting('t.req')),'23514');
SELECT pg_temp.espera_erro('CT-09','Componente','Mesmo insumo duas vezes na mesma requisição é rejeitado (UNIQUE)',
 format($q$ INSERT INTO item_requisitado(id_requisicao,id_insumo,qtd_pedida,preco_aplicado) VALUES (%s,(SELECT id_insumo FROM insumo WHERE codigo='BRI-001'),1,9) $q$, current_setting('t.req')),'23505');
SELECT pg_temp.espera_erro('CT-11','Componente','INSERT direto em SALDO_ESTOQUE é bloqueado (trigger T4)',
 $q$ INSERT INTO saldo_estoque(id_obra,id_insumo,qtd_atual) VALUES (1,1,50) $q$,'42501');
SELECT pg_temp.espera_erro('CT-12','Componente','Requisição sem item é rejeitada no commit (cardinalidade 1,N)',
 $q$ INSERT INTO requisicao(id_obra,id_usuario_solicitante) VALUES (1,1) $q$,'23514');

-- CT-13/14: trigger T3 acumula só a quantidade aprovada, duas conferências em requisições distintas
DO $$
DECLARE a record; b record; v_saldo numeric; v_conf int;
BEGIN
  SELECT * INTO a FROM pg_temp.nova_req('Colégio Municipal','ARE-001',100);
  v_conf := pg_temp.conferir(a.p_req,a.p_item,100,90,'AVARIADO');
  SELECT qtd_atual INTO v_saldo FROM saldo_estoque WHERE id_obra=(SELECT id_obra FROM obra WHERE nome='Colégio Municipal') AND id_insumo=(SELECT id_insumo FROM insumo WHERE codigo='ARE-001');
  PERFORM pg_temp.espera('CT-13','Componente','Trigger T3: recebida 100, aprovada 90 -> saldo = 90 (e não 100)','90.000',v_saldo::text);
  SELECT * INTO b FROM pg_temp.nova_req('Colégio Municipal','ARE-001',50);
  v_conf := pg_temp.conferir(b.p_req,b.p_item,50,50,'CONFERIDO');
  SELECT qtd_atual INTO v_saldo FROM saldo_estoque WHERE id_obra=(SELECT id_obra FROM obra WHERE nome='Colégio Municipal') AND id_insumo=(SELECT id_insumo FROM insumo WHERE codigo='ARE-001');
  PERFORM pg_temp.espera('CT-14','Componente','Trigger T3: segunda conferência acumula (90 + 50 = 140)','140.000',v_saldo::text);
END $$;

SELECT pg_temp.espera_erro('CT-10','Componente','UPDATE direto em SALDO_ESTOQUE é bloqueado (trigger T4; exige linha existente)',
 $q$ UPDATE saldo_estoque SET qtd_atual = 999 $q$,'42501');
SELECT pg_temp.espera_erro('CT-10b','Componente','DELETE direto em SALDO_ESTOQUE é bloqueado (trigger T4)',
 $q$ DELETE FROM saldo_estoque $q$,'42501');

-- CT-15/16: imutabilidade da trilha de auditoria (T5)
SELECT pg_temp.espera_erro('CT-15','Componente','UPDATE em ITEM_CONFERIDO é bloqueado (trigger T5)',
 $q$ UPDATE item_conferido SET qtd_aprovada = 0 $q$,'42501');
SELECT pg_temp.espera_erro('CT-16','Componente','DELETE em CONFERENCIA é bloqueado (trigger T5)',
 $q$ DELETE FROM conferencia $q$,'42501');

-- CT-17: tipagem monetária — DECIMAL soma exata; FLOAT não
DO $$
DECLARE v_num numeric; v_flt float8;
BEGIN
  SELECT SUM(0.10::numeric(12,2)) INTO v_num FROM generate_series(1,1000000);
  SELECT SUM(0.10::float8)        INTO v_flt FROM generate_series(1,1000000);
  PERFORM pg_temp.espera('CT-17','Componente','DECIMAL: 1.000.000 x R$ 0,10 = R$ 100000,00 exato','100000.00',v_num::text);
  PERFORM pg_temp.espera('CT-18','Componente','FLOAT8 (contraprova): a mesma soma NÃO fecha em 100000 exato','diferente de 100000',
     CASE WHEN v_flt = 100000 THEN '100000' ELSE 'diferente de 100000' END);
  RAISE NOTICE 'soma NUMERIC = %, soma FLOAT8 = %', v_num, v_flt;
END $$;

-- =============== SISTEMA (integridade entre tabelas, fluxo fim a fim, consultas) ===============
-- ST-01 TC-INT-01: requisição 999 inexistente — nada é gravado
DO $$
DECLARE n_conf0 int; n_it0 int; n_sal0 int; n_conf1 int; n_it1 int; n_sal1 int; v_estado text := 'nenhum erro';
BEGIN
  SELECT count(*) INTO n_conf0 FROM conferencia; SELECT count(*) INTO n_it0 FROM item_conferido; SELECT count(*) INTO n_sal0 FROM saldo_estoque;
  BEGIN
    INSERT INTO conferencia(id_requisicao,id_usuario_almoxarife,nf_numero) VALUES (999,(SELECT id_usuario FROM usuario WHERE perfil='ALMOXARIFE'),'NF-X');
  EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE; END;
  SELECT count(*) INTO n_conf1 FROM conferencia; SELECT count(*) INTO n_it1 FROM item_conferido; SELECT count(*) INTO n_sal1 FROM saldo_estoque;
  PERFORM pg_temp.espera('ST-01','Sistema','TC-INT-01: conferência da requisição 999 é recusada (erro 23503)','23503',v_estado);
  PERFORM pg_temp.espera('ST-02','Sistema','TC-INT-01: nenhum registro criado em CONFERENCIA/ITEM_CONFERIDO/SALDO_ESTOQUE','sem alteração',
     CASE WHEN (n_conf0,n_it0,n_sal0)=(n_conf1,n_it1,n_sal1) THEN 'sem alteração' ELSE 'alterou' END);
END $$;

-- ST-03: item de OUTRA requisição é rejeitado e a conferência não fica gravada pela metade
DO $$
DECLARE a record; b record; v_conf int; n0 int; n1 int; v_estado text := 'nenhum erro';
BEGIN
  SELECT * INTO a FROM pg_temp.nova_req('Armazém','CIM-001',10);
  SELECT * INTO b FROM pg_temp.nova_req('Armazém','COM-001',2);
  SELECT count(*) INTO n0 FROM conferencia;
  BEGIN
    PERFORM pg_temp.conferir(a.p_req, b.p_item, 2, 2, 'CONFERIDO');  -- item de b dentro da conferência de a
  EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE; END;
  SELECT count(*) INTO n1 FROM conferencia;
  PERFORM pg_temp.espera('ST-03','Sistema','TC-INT-01: item de outra requisição é rejeitado (23514)','23514',v_estado);
  PERFORM pg_temp.espera('ST-04','Sistema','Falha parcial desfaz a conferência inteira (atomicidade)','sem alteração',CASE WHEN n0=n1 THEN 'sem alteração' ELSE 'alterou' END);
END $$;

-- ST-05/06: requisição já conferida não pode ser conferida de novo
DO $$
DECLARE a record; v_conf int; v_estado text := 'nenhum erro'; v_status text;
BEGIN
  SELECT * INTO a FROM pg_temp.nova_req('Armazém','ARE-001',20);
  v_conf := pg_temp.conferir(a.p_req,a.p_item,20,20,'CONFERIDO');
  SELECT status INTO v_status FROM requisicao WHERE id_requisicao=a.p_req;
  PERFORM pg_temp.espera('ST-05','Sistema','Após conferir, a requisição vira CONFERIDA (trigger T6)','CONFERIDA',v_status);
  BEGIN PERFORM pg_temp.conferir(a.p_req,a.p_item,20,20,'CONFERIDO'); EXCEPTION WHEN OTHERS THEN v_estado := SQLSTATE; END;
  PERFORM pg_temp.espera('ST-06','Sistema','Segunda conferência da mesma requisição é recusada (23514)','23514',v_estado);
END $$;

-- ST-07/08: integridade referencial rígida (sem órfãos)
SELECT pg_temp.espera_erro('ST-07','Sistema','Excluir OBRA que possui requisições é recusado (FK)',
 $q$ DELETE FROM obra WHERE nome='Hospital' $q$,'23503');
SELECT pg_temp.espera_erro('ST-08','Sistema','Item requisitado com insumo inexistente é recusado (FK)',
 format($q$ INSERT INTO item_requisitado(id_requisicao,id_insumo,qtd_pedida,preco_aplicado) VALUES (%s,9999,1,1) $q$, current_setting('t.req')),'23503');
SELECT pg_temp.espera_erro('ST-09','Sistema','Excluir INSUMO que tem item requisitado é recusado (FK)',
 $q$ DELETE FROM insumo WHERE codigo='BRI-001' $q$,'23503');

-- ST-10..13: fluxo fim a fim TC-OP-02 (Hospital·Brotas, brita 13 kg, recebido 12, aprovado 12)
DO $$
DECLARE a record; v_conf int; v_saldo0 numeric; v_saldo1 numeric; v_div numeric; v_obra int; v_ins int;
BEGIN
  SELECT id_obra INTO v_obra FROM obra WHERE nome='Hospital';
  SELECT id_insumo INTO v_ins FROM insumo WHERE codigo='BRI-001';
  SELECT COALESCE((SELECT qtd_atual FROM saldo_estoque WHERE id_obra=v_obra AND id_insumo=v_ins),0) INTO v_saldo0;
  SELECT * INTO a FROM pg_temp.nova_req('Hospital','BRI-001',13);
  v_conf := pg_temp.conferir(a.p_req,a.p_item,12,12,'CONFERIDO');
  SELECT qtd_atual INTO v_saldo1 FROM saldo_estoque WHERE id_obra=v_obra AND id_insumo=v_ins;
  SELECT divergencia INTO v_div FROM v_divergencia WHERE id_conferencia=v_conf;
  PERFORM pg_temp.espera('ST-10','Sistema','TC-OP-02: saldo inicial de brita no Hospital = 0','0',v_saldo0::text);
  PERFORM pg_temp.espera('ST-11','Sistema','TC-OP-02: após conferir 12 kg aprovados o saldo = 12 (e não 13)','12.000',v_saldo1::text);
  PERFORM pg_temp.espera('ST-12','Sistema','TC-OP-02: divergência calculada (pedida - aprovada) = 1 kg','1.000',v_div::text);
END $$;

-- ST-13: consulta analítica — total da requisição calculado (não armazenado) = R$ 350,00 do protótipo
DO $$
DECLARE r int; v_total numeric;
BEGIN
  INSERT INTO requisicao(id_obra,id_usuario_solicitante) VALUES ((SELECT id_obra FROM obra WHERE nome='Armazém'),(SELECT id_usuario FROM usuario WHERE perfil='ENGENHEIRO')) RETURNING id_requisicao INTO r;
  INSERT INTO item_requisitado(id_requisicao,id_insumo,qtd_pedida,preco_aplicado) SELECT r,id_insumo,q,preco_ref FROM (VALUES ('CIM-001',5),('COM-001',1),('ARE-001',10)) v(cod,q) JOIN insumo ON codigo=cod;
  SELECT total INTO v_total FROM v_total_requisicao WHERE id_requisicao=r;
  PERFORM pg_temp.espera('ST-13','Sistema','View v_total_requisicao: 5 x 38,00 + 1 x 120,00 + 10 x 4,00 = 350.00','350.00',v_total::text);
END $$;

-- ST-15/16: critérios de aceite da issue #15
DO $$
DECLARE n_calc int; n_desc int; n_unq int;
BEGIN
  SELECT count(*) INTO n_calc FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name)
   WHERE c.table_schema='sgf' AND t.table_type='BASE TABLE' AND c.column_name ~ '(total|pct|percent|classe|diverg)';
  PERFORM pg_temp.espera('ST-15','Sistema','Issue #15: nenhuma tabela guarda valor total, %, classe ou divergência (colunas)','0',n_calc::text);
  SELECT count(*) INTO n_desc FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name)
   WHERE c.table_schema='sgf' AND t.table_type='BASE TABLE' AND c.column_name='descricao';
  SELECT count(*) INTO n_unq FROM pg_constraint WHERE conrelid='sgf.insumo'::regclass AND contype='u' AND conname='uq_insumo_codigo';
  PERFORM pg_temp.espera('ST-16','Sistema','Issue #15: cada insumo tem uma só descrição (coluna só em INSUMO + código UNIQUE)','1 tabela; 1 UNIQUE',n_desc||' tabela; '||n_unq||' UNIQUE');
END $$;

-- ST-14: invariante — SALDO_ESTOQUE.qtd_atual = soma das qtd_aprovada (por obra e insumo)
DO $$
DECLARE n_div int;
BEGIN
  SELECT count(*) INTO n_div FROM (
    SELECT s.id_obra, s.id_insumo, s.qtd_atual, COALESCE(x.soma,0) AS soma
      FROM saldo_estoque s
      LEFT JOIN (SELECT r.id_obra, ir.id_insumo, SUM(ic.qtd_aprovada) soma
                   FROM item_conferido ic JOIN item_requisitado ir USING (id_item_requisitado)
                   JOIN requisicao r USING (id_requisicao) GROUP BY 1,2) x USING (id_obra,id_insumo)
     WHERE s.qtd_atual <> COALESCE(x.soma,0)) d;
  PERFORM pg_temp.espera('ST-14','Sistema','Invariante: qtd_atual == soma(qtd_aprovada) em todas as linhas de saldo','0 divergências',n_div||' divergências'::text);
END $$;

\o
SELECT row_number() OVER (ORDER BY id) AS "#", id, nivel, descricao, esperado, obtido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado FROM resultado ORDER BY id;
SELECT count(*) FILTER (WHERE ok) AS pass, count(*) FILTER (WHERE NOT ok) AS fail, count(*) AS total FROM resultado;
ROLLBACK;
