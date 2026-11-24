# db/ — camada de dados do módulo Almoxarifado e Canteiro (U2)

Banco de dados relacional (PostgreSQL) do módulo Almoxarifado e Canteiro do SGF (aplicativo InsumoStack). Contém o esquema, as regras de integridade e os testes. Não há API: a interface em `application/` continua com dados mockados.

## Requisitos
- PostgreSQL 14 ou mais novo (testado na 16.15 e na 19.0), com `psql`, `createdb` e `dropdb` no PATH.
- Usuário com permissão de criar banco.

## Como rodar
```bash
cd db
export PGUSER=postgres
export PGPASSWORD="sua-senha"
bash run_tests.sh        # cria o banco sgf_u2, aplica schema, gatilhos e seed, e roda os testes
```
- No Windows, use o Git Bash. Se `psql` não for encontrado, acrescente a pasta `bin` do PostgreSQL ao PATH, por exemplo `export PATH="/c/Program Files/PostgreSQL/16/bin:$PATH"`.
- Resultado esperado: 35 testes, 35 PASS, 0 FAIL. Os testes terminam em ROLLBACK e não alteram o banco. No Windows, os acentos podem aparecer trocados no terminal, o que não afeta o resultado.

## Arquivos
| Arquivo | Conteúdo |
|---|---|
| `01_schema.sql` | DDL: 8 tabelas e 2 views (`v_total_requisicao`, `v_divergencia`) |
| `02_triggers.sql` | Regras T1 a T7: conferência só de requisição EMITIDA, item da mesma requisição, saldo atualizado pela conferência, bloqueio de escrita direta no saldo, imutabilidade, estado da requisição e cardinalidade (1,N) |
| `03_seed.sql` | Dados de demonstração |
| `tests/01_testes.sql` | 19 testes de componente e 16 de sistema |
| `tests/02_decimal_vs_float.sql` | Comparação NUMERIC x FLOAT |

## Documentação relacionada
- Dicionário de dados: `docs/dicionario_de_dados.md`
- DER, sequência e C4: `docs/figuras/` (PNG e `.drawio`)
- Evidências de execução: `docs/evidencias/`
