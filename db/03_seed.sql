-- 03_seed.sql — dados de demonstração extraídos do protótipo (application/index.html)
-- obras: Armazém·Amaralina, Hospital·Brotas, Colégio Municipal·Nazaré
-- insumos/preços: atributos data-preco das linhas 77-80 do index.html
SET search_path = sgf;
INSERT INTO obra (nome, bairro) VALUES
 ('Armazém','Amaralina'),('Hospital','Brotas'),('Colégio Municipal','Nazaré');
INSERT INTO usuario (nome, perfil) VALUES
 ('Engenheiro Demo','ENGENHEIRO'),('Almoxarife Demo','ALMOXARIFE'),('Encarregado Demo','ENCARREGADO');
INSERT INTO insumo (codigo, descricao, unidade_medida, preco_ref) VALUES
 ('CIM-001','Saco de cimento','UN',38.00),
 ('BRI-001','Brita','KG',9.00),
 ('ARE-001','Areia','KG',4.00),
 ('COM-001','Compensado 50x200','UN',120.00);
