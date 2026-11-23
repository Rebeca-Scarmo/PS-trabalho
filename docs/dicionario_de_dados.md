# Dicionário de dados — SGF · Almoxarifado e Canteiro (U2)

Gerado a partir do banco real (`information_schema` e `pg_constraint`) após executar `db/01_schema.sql`; descrições redigidas pelos autores. SGBD: PostgreSQL 16, esquema `sgf`.

Convenções: valores monetários `NUMERIC(12,2)`; quantidades `NUMERIC(12,3)`; derivados (total do pedido, divergência) não são armazenados e saem das views `v_total_requisicao` e `v_divergencia`.

## OBRA

Local onde se pede e se estoca (contexto do pedido).

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_obra | INTEGER | não | PK | Identificador da obra. |
| nome | VARCHAR(80) | não | UNIQUE (composta) | Nome da obra (ex.: Hospital). |
| bairro | VARCHAR(60) | não | UNIQUE (composta) | Bairro da obra (ex.: Brotas). |

Restrições CHECK/UNIQUE completas:

- `UNIQUE (nome, bairro)`

## USUARIO

Pessoa que pede ou confere. Modela os perfis; a autenticação (login) segue pendente.

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_usuario | INTEGER | não | PK | Identificador. |
| nome | VARCHAR(80) | não |  | Nome do usuário. |
| perfil | VARCHAR(12) | não | CHECK | ENGENHEIRO, ALMOXARIFE ou ENCARREGADO. |

Restrições CHECK/UNIQUE completas:

- `CHECK (((perfil)::text = ANY ((ARRAY['ENGENHEIRO'::character varying, 'ALMOXARIFE'::character varying, 'ENCARREGADO'::character varying])::text[])))`

## INSUMO

Cadastro/dado mestre do material (o que a planilha repete em cada linha).

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_insumo | INTEGER | não | PK | Identificador técnico. |
| codigo | VARCHAR(20) | não | UNIQUE | Código do insumo; único (planilha: 227 códigos distintos). |
| descricao | VARCHAR(120) | não |  | Descrição normalizada. |
| unidade_medida | VARCHAR(3) | não | CHECK | Domínio controlado (UN, KG, M, M2, M3, CJ, SC). |
| preco_ref | NUMERIC(12,2) | não | CHECK | Preço de referência atual, em reais (DECIMAL). |

Restrições CHECK/UNIQUE completas:

- `CHECK (((unidade_medida)::text = ANY ((ARRAY['UN'::character varying, 'KG'::character varying, 'M'::character varying, 'M2'::character varying, 'M3'::character varying, 'CJ'::character varying, 'SC'::character varying])::text[])))`
- `CHECK ((preco_ref >= (0)::numeric))`
- `UNIQUE (codigo)`

## REQUISICAO

Evento: pedido do engenheiro (US01).

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_requisicao | INTEGER | não | PK | Identificador. |
| id_obra | INTEGER | não | FK→sgf.obra(id_obra) | Obra de destino. |
| id_usuario_solicitante | INTEGER | não | FK→sgf.usuario(id_usuario) | Quem pediu. |
| data_emissao | TIMESTAMP | não | DEFAULT now() | Instante da emissão. |
| status | VARCHAR(10) | não | CHECK; DEFAULT 'EMITIDA'::character varying | EMITIDA ou CONFERIDA; barra conferência repetida. |

Restrições CHECK/UNIQUE completas:

- `CHECK (((status)::text = ANY ((ARRAY['EMITIDA'::character varying, 'CONFERIDA'::character varying])::text[])))`

## ITEM_REQUISITADO

Ocorrência do insumo numa requisição, com a quantidade pedida.

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_item_requisitado | INTEGER | não | PK | Identificador (evita chave composta propagada). |
| id_requisicao | INTEGER | não | UNIQUE (composta); FK→sgf.requisicao(id_requisicao) | Requisição dona do item. |
| id_insumo | INTEGER | não | UNIQUE (composta); FK→sgf.insumo(id_insumo) | Insumo pedido. |
| qtd_pedida | NUMERIC(12,3) | não | CHECK | Quantidade pedida (> 0). |
| preco_aplicado | NUMERIC(12,2) | não | CHECK | Preço no momento do pedido (histórico; não é dependência transitiva). |

Restrições CHECK/UNIQUE completas:

- `CHECK ((qtd_pedida > (0)::numeric))`
- `CHECK ((preco_aplicado >= (0)::numeric))`
- `UNIQUE (id_requisicao, id_insumo)`

## CONFERENCIA

Evento: recebimento físico conferido pelo almoxarife (US02).

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_conferencia | INTEGER | não | PK | Identificador. |
| id_requisicao | INTEGER | não | FK→sgf.requisicao(id_requisicao) | Requisição conferida. |
| id_usuario_almoxarife | INTEGER | não | FK→sgf.usuario(id_usuario) | Quem conferiu. |
| nf_numero | VARCHAR(20) | não |  | Número da nota fiscal. |
| data_hora | TIMESTAMP | não | DEFAULT now() | Instante da conferência. |

Restrições CHECK/UNIQUE completas:


## ITEM_CONFERIDO

Ocorrência da conferência: confronta pedido e recebido (RF3, RF4).

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_item_conferido | INTEGER | não | PK | Identificador. |
| id_conferencia | INTEGER | não | UNIQUE (composta); FK→sgf.conferencia(id_conferencia) | Conferência dona. |
| id_item_requisitado | INTEGER | não | UNIQUE (composta); FK→sgf.item_requisitado(id_item_requisitado) | Item pedido que foi conferido. |
| qtd_recebida | NUMERIC(12,3) | não | CHECK | Quantidade que chegou (medida física). |
| qtd_aprovada | NUMERIC(12,3) | não | CHECK | Quantidade aceita (<= recebida); só ela entra no saldo. |
| status_item | VARCHAR(10) | não | CHECK | CONFERIDO, AVARIADO ou AUSENTE. |
| observacao | VARCHAR(200) | sim |  | Texto livre opcional. |

Restrições CHECK/UNIQUE completas:

- `CHECK ((qtd_recebida >= (0)::numeric))`
- `CHECK (((qtd_aprovada >= (0)::numeric) AND (qtd_aprovada <= qtd_recebida)))`
- `CHECK (((status_item)::text = ANY ((ARRAY['CONFERIDO'::character varying, 'AVARIADO'::character varying, 'AUSENTE'::character varying])::text[])))`
- `CHECK ((((status_item)::text <> 'AUSENTE'::text) OR (qtd_aprovada = (0)::numeric)))`
- `UNIQUE (id_conferencia, id_item_requisitado)`

## SALDO_ESTOQUE

Estado atual do estoque por obra e insumo (US03, RF5). Redundância controlada.

| Coluna | Tipo | Nulo | Restrições | Descrição |
|---|---|---|---|---|
| id_obra | INTEGER | não | PK; FK→sgf.obra(id_obra) | Obra (parte da PK). |
| id_insumo | INTEGER | não | PK; FK→sgf.insumo(id_insumo) | Insumo (parte da PK). |
| qtd_atual | NUMERIC(12,3) | não | CHECK; DEFAULT 0 | Soma das qtd_aprovada; só muda via trigger T3. |
| data_atualizacao | TIMESTAMP | não | DEFAULT now() | Última alteração. |

Restrições CHECK/UNIQUE completas:

- `CHECK ((qtd_atual >= (0)::numeric))`
