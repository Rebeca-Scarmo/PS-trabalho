package com.insumostack;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.core.NestedExceptionUtils;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * API mínima: só repassa os dados ao banco. As regras (saldo só com o aprovado,
 * conferência única, etc.) continuam nos gatilhos de db/02_triggers.sql.
 * Sem login: pedido e conferência usam os usuários de demonstração do seed.
 */
@RestController
@RequestMapping("/api")
public class ApiController {

    public record ItemPedido(int idInsumo, BigDecimal qtd) {}
    public record Pedido(int idObra, List<ItemPedido> itens) {}
    public record ItemConferencia(int idItemRequisitado, BigDecimal qtdRecebida, BigDecimal qtdAprovada) {}
    public record Conferencia(int idRequisicao, String nf, List<ItemConferencia> itens) {}

    private final JdbcTemplate jdbc;

    public ApiController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // RF05 / US03: saldo real da obra (insumos sem entrada aparecem com 0)
    @GetMapping("/saldo")
    public List<Map<String, Object>> saldo(@RequestParam("obra") int obra) {
        return jdbc.queryForList(
            "SELECT i.descricao, i.unidade_medida AS unidade, COALESCE(s.qtd_atual, 0) AS qtd "
          + "FROM insumo i LEFT JOIN saldo_estoque s ON s.id_insumo = i.id_insumo AND s.id_obra = ? "
          + "ORDER BY i.id_insumo", obra);
    }

    // RF02: emite a requisição (cabeçalho + itens na mesma transação)
    @PostMapping("/requisicoes")
    @Transactional
    public Map<String, Object> emitir(@RequestBody Pedido pedido) {
        if (pedido.itens() == null || pedido.itens().isEmpty()) {
            throw new IllegalArgumentException("Selecione ao menos um item.");
        }
        Integer id = jdbc.queryForObject(
            "INSERT INTO requisicao (id_obra, id_usuario_solicitante) "
          + "VALUES (?, (SELECT id_usuario FROM usuario WHERE perfil = 'ENGENHEIRO' ORDER BY id_usuario LIMIT 1)) "
          + "RETURNING id_requisicao", Integer.class, pedido.idObra());
        for (ItemPedido item : pedido.itens()) {
            jdbc.update(
                "INSERT INTO item_requisitado (id_requisicao, id_insumo, qtd_pedida, preco_aplicado) "
              + "SELECT ?, id_insumo, ?, preco_ref FROM insumo WHERE id_insumo = ?",
                id, item.qtd(), item.idInsumo());
        }
        return Map.of("idRequisicao", id);
    }

    // requisição EMITIDA mais antiga da obra, com os itens a conferir (204 se não houver)
    @GetMapping("/requisicoes/pendente")
    public ResponseEntity<Map<String, Object>> pendente(@RequestParam("obra") int obra) {
        List<Integer> ids = jdbc.queryForList(
            "SELECT id_requisicao FROM requisicao WHERE id_obra = ? AND status = 'EMITIDA' "
          + "ORDER BY id_requisicao LIMIT 1", Integer.class, obra);
        if (ids.isEmpty()) {
            return ResponseEntity.noContent().build();
        }
        Map<String, Object> resposta = new LinkedHashMap<>();
        resposta.put("idRequisicao", ids.get(0));
        resposta.put("itens", jdbc.queryForList(
            "SELECT ir.id_item_requisitado AS id, i.descricao, i.unidade_medida AS unidade, ir.qtd_pedida AS qtd "
          + "FROM item_requisitado ir JOIN insumo i USING (id_insumo) "
          + "WHERE ir.id_requisicao = ? ORDER BY ir.id_item_requisitado", ids.get(0)));
        return ResponseEntity.ok(resposta);
    }

    // RF03 / RF04 / RF05: grava a conferência; o gatilho T3 atualiza o saldo com o aprovado
    @PostMapping("/conferencias")
    @Transactional
    public Map<String, Object> conferir(@RequestBody Conferencia conf) {
        if (conf.nf() == null || conf.nf().isBlank()) {
            throw new IllegalArgumentException("Informe o número da NF.");
        }
        if (conf.itens() == null || conf.itens().isEmpty()) {
            throw new IllegalArgumentException("Conferência sem itens.");
        }
        Integer id = jdbc.queryForObject(
            "INSERT INTO conferencia (id_requisicao, id_usuario_almoxarife, nf_numero) "
          + "VALUES (?, (SELECT id_usuario FROM usuario WHERE perfil = 'ALMOXARIFE' ORDER BY id_usuario LIMIT 1), ?) "
          + "RETURNING id_conferencia", Integer.class, conf.idRequisicao(), conf.nf().trim());
        for (ItemConferencia item : conf.itens()) {
            String status = item.qtdAprovada().signum() == 0 && item.qtdRecebida().signum() == 0 ? "AUSENTE"
                          : item.qtdAprovada().compareTo(item.qtdRecebida()) < 0 ? "AVARIADO"
                          : "CONFERIDO";
            jdbc.update(
                "INSERT INTO item_conferido (id_conferencia, id_item_requisitado, qtd_recebida, qtd_aprovada, status_item) "
              + "VALUES (?, ?, ?, ?, ?)",
                id, item.idItemRequisitado(), item.qtdRecebida(), item.qtdAprovada(), status);
        }
        return Map.of("idConferencia", id);
    }

    // devolve a mensagem do banco (ex.: "Requisição 3 já foi conferida") em vez de uma página de erro
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> erro(Exception e) {
        String msg = NestedExceptionUtils.getMostSpecificCause(e).getMessage();
        if (msg == null) msg = "Erro inesperado.";
        msg = msg.split("\n")[0].replaceFirst("^ERROR:\\s*", "");
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("erro", msg));
    }
}
