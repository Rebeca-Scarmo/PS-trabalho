-- tests/02_decimal_vs_float.sql — impacto da tipagem monetária (demonstração reprodutível)
\pset format aligned
SELECT (0.1::float8 + 0.2::float8) = 0.3::float8       AS float8_0_1_mais_0_2_igual_0_3,
       (0.1::numeric + 0.2::numeric) = 0.3::numeric    AS numeric_0_1_mais_0_2_igual_0_3;
SELECT 'FLOAT8'  AS tipo, SUM(0.10::float8)::text                  AS soma_1e6_x_R$_0_10 FROM generate_series(1,1000000)
UNION ALL
SELECT 'FLOAT4',          SUM(0.10::float4)::text                  FROM generate_series(1,1000000)
UNION ALL
SELECT 'NUMERIC(12,2)',   SUM(0.10::numeric(12,2))::text           FROM generate_series(1,1000000);
-- 3 itens a R$ 19,99 com desconto de 10%: arredondamento explícito vs float
SELECT (3 * 19.99::float8 * 0.9)::text AS float8_total, round((3 * 19.99::numeric * 0.9),2)::text AS numeric_total_2casas;
