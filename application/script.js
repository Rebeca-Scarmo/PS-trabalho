// Front: navegação, contadores e feedbacks visuais. Sem regra de negócio:
// pedido, conferência e saldo (telas 4, 5 e 6) vão e vêm da API (mesma origem, sem CORS).
// As telas 2 e 3 (obras e últimos pedidos) continuam com dados fixos.

var circulos = {
  t1: [[40, 70, 50], [300, 60, 44], [330, 130, 22], [70, 150, 80], [260, 700, 60], [40, 640, 34]],
  t2: [[250, 40, 40], [290, 55, 26], [30, 700, 60], [300, 640, 80], [330, 690, 30]],
  t3: [[290, 30, 44], [320, 50, 26], [20, 720, 50], [320, 700, 40]],
  t4: [[270, 36, 34], [300, 20, 18], [330, 690, 40]],
  t5: [[270, 36, 34], [300, 20, 18], [20, 700, 70], [70, 740, 34]],
  t6: [[300, 30, 40], [330, 60, 20], [10, 720, 50]]
};

var icones = {
  obras: '<svg viewBox="0 0 24 24"><path d="M3 21V9l9-6 9 6v12M9 21v-7h6v7"/></svg>',
  pedidos: '<svg viewBox="0 0 24 24"><path d="M9 4h6v3H9zM7 5H5v16h14V5h-2M9 12h6M9 16h4"/></svg>',
  almoxarifado: '<svg viewBox="0 0 24 24"><path d="M3 8l9-5 9 5v9l-9 5-9-5zM3 8l9 5 9-5M12 13v9"/></svg>'
};

function adicionarCirculos(tela) {
  var lista = circulos[tela.getAttribute("data-circles")] || [];
  lista.forEach(function (c) {
    var el = document.createElement("i");
    el.className = "c";
    el.style.left = c[0] + "px";
    el.style.top = c[1] + "px";
    el.style.width = c[2] + "px";
    el.style.height = c[2] + "px";
    tela.insertBefore(el, tela.firstChild);
  });
}

function criarMenu(tela) {
  var tab = tela.getAttribute("data-tab");
  if (!tab) return;
  var nav = document.createElement("nav");
  nav.className = "nav";
  var itens = [["obras", "Obras", "tela2"], ["pedidos", "Pedidos", "tela4"], ["almoxarifado", "Almoxarifado", "tela5"]];
  itens.forEach(function (item) {
    var a = document.createElement("a");
    a.innerHTML = icones[item[0]] + "<span>" + item[1] + "</span>";
    a.setAttribute("data-go", item[2]);
    if (item[0] === tab) a.className = "on";
    nav.appendChild(a);
  });
  tela.appendChild(nav);
}

function irPara(id) {
  document.querySelectorAll(".screen").forEach(function (s) {
    s.classList.remove("active");
  });
  var tela = document.getElementById(id);
  tela.classList.add("active");
  var conteudo = tela.querySelector(".content");
  if (conteudo) conteudo.scrollTop = 0;
  if (id === "tela5") carregarSaldo();
  if (id === "tela6") carregarPendente();
}

function mostrarAviso(texto) {
  var toast = document.getElementById("toast");
  toast.textContent = texto;
  toast.classList.add("on");
  setTimeout(function () { toast.classList.remove("on"); }, 1800);
}

// ---------- API ----------
function api(url, corpo) {
  var opcoes = corpo ? { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(corpo) } : {};
  return fetch(url, opcoes).then(function (r) {
    if (r.status === 204) return null;
    return r.json().catch(function () { return {}; }).then(function (dados) {
      if (!r.ok) throw new Error(dados.erro || "Erro no servidor");
      return dados;
    });
  });
}

function erroAviso(e) {
  mostrarAviso(e instanceof TypeError ? "Servidor indisponível" : e.message);
}

function esc(texto) {
  return String(texto).replace(/[&<>"]/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
  });
}

function obraDa(telaId) {
  return document.querySelector("#" + telaId + " .pick.on").getAttribute("data-obra");
}

// tela 5: saldo real da obra escolhida
function carregarSaldo() {
  api("/api/saldo?obra=" + obraDa("tela5")).then(function (lista) {
    document.getElementById("saldo5").innerHTML = lista.map(function (i) {
      var qtd = Number(i.qtd).toLocaleString("pt-BR", { maximumFractionDigits: 3 });
      return '<li><div><strong>' + esc(i.descricao) + '</strong></div><span class="qtd">' + qtd + " " + esc(i.unidade.toLowerCase()) + "</span></li>";
    }).join("");
  }).catch(erroAviso);
}

// tela 6: itens da requisição EMITIDA mais antiga da obra (a quantidade já vem preenchida com a pedida)
var requisicaoPendente = null;

function carregarPendente() {
  var lista = document.getElementById("lista6");
  var aviso = document.getElementById("aviso6");
  var botao = document.getElementById("entrada");
  requisicaoPendente = null;
  botao.disabled = true;
  lista.innerHTML = "";
  document.getElementById("nf").value = "";
  api("/api/requisicoes/pendente?obra=" + obraDa("tela5")).then(function (req) {
    if (!req) {
      aviso.textContent = "Nenhuma requisição aguardando conferência nesta obra.";
      return;
    }
    requisicaoPendente = req.idRequisicao;
    aviso.textContent = "Requisição nº " + req.idRequisicao + " · informe o que chegou";
    lista.innerHTML = req.itens.map(function (i) {
      return '<li class="item" data-item="' + i.id + '"><div class="info"><strong>' + esc(i.descricao) + "</strong><small>" + esc(i.unidade.toLowerCase()) + '</small></div>' +
        '<div class="stepper"><button class="minus" aria-label="Diminuir">−</button><output>' + Number(i.qtd) + '</output><button class="plus" aria-label="Aumentar">+</button></div></li>';
    }).join("");
    lista.querySelectorAll(".stepper").forEach(function (s) {
      s.querySelector(".minus").disabled = parseInt(s.querySelector("output").textContent, 10) === 0;
    });
    botao.disabled = false;
  }).catch(erroAviso);
}

// tela 4: emite a requisição
function finalizarPedido() {
  var itens = [];
  document.querySelectorAll("#lista4 .item").forEach(function (item) {
    var qtd = parseInt(item.querySelector("output").textContent, 10);
    if (qtd > 0) itens.push({ idInsumo: Number(item.getAttribute("data-insumo")), qtd: qtd });
  });
  api("/api/requisicoes", { idObra: Number(obraDa("tela4")), itens: itens }).then(function () {
    mostrarAviso("Pedido enviado!");
    limparPedido();
  }).catch(erroAviso);
}

// tela 6: grava a conferência (recebido = aprovado); o banco atualiza o saldo
function registrarEntrada() {
  var nf = document.getElementById("nf").value.trim();
  if (!nf) { mostrarAviso("Informe o número da NF"); return; }
  var itens = [];
  document.querySelectorAll("#lista6 .item").forEach(function (item) {
    var qtd = parseInt(item.querySelector("output").textContent, 10);
    itens.push({ idItemRequisitado: Number(item.getAttribute("data-item")), qtdRecebida: qtd, qtdAprovada: qtd });
  });
  var botao = document.getElementById("entrada");
  botao.disabled = true;
  api("/api/conferencias", { idRequisicao: requisicaoPendente, nf: nf, itens: itens }).then(function () {
    mostrarAviso("Entrada registrada!");
    irPara("tela5");
  }).catch(function (e) {
    botao.disabled = false;
    erroAviso(e);
  });
}

// pedido: conta os itens e habilita o botão
function atualizarPedido() {
  var total = 0;
  document.querySelectorAll("#lista4 .item").forEach(function (item) {
    var qtd = parseInt(item.querySelector("output").textContent, 10);
    total += qtd;
    item.classList.toggle("ativo", qtd > 0);
  });
  document.getElementById("contagem").textContent = total > 0 ? total : "";
  document.getElementById("finalizar").disabled = total === 0;
}

// depois de finalizar, zera as quantidades para começar um novo pedido
function limparPedido() {
  document.querySelectorAll("#lista4 .item").forEach(function (item) {
    item.querySelector("output").textContent = "0";
    item.querySelector(".minus").disabled = true;
  });
  atualizarPedido();
}

document.querySelectorAll(".screen").forEach(function (tela) {
  adicionarCirculos(tela);
  criarMenu(tela);
});

// itens clicáveis também funcionam pelo teclado
document.querySelectorAll("[data-go]").forEach(function (el) {
  if (el.tagName !== "BUTTON") {
    el.setAttribute("tabindex", "0");
    el.setAttribute("role", "button");
    el.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        irPara(el.getAttribute("data-go"));
      }
    });
  }
});

document.addEventListener("click", function (e) {
  var botao = e.target.closest("button");

  // contadores
  if (botao && botao.closest(".stepper")) {
    var saida = botao.parentNode.querySelector("output");
    var valor = parseInt(saida.textContent, 10);
    valor = botao.classList.contains("plus") ? valor + 1 : Math.max(0, valor - 1);
    saida.textContent = valor;
    botao.parentNode.querySelector(".minus").disabled = valor === 0;
    atualizarPedido();
    return;
  }

  if (botao && botao.id === "finalizar") { if (!botao.disabled) finalizarPedido(); return; }
  if (botao && botao.id === "entrada") { if (!botao.disabled) registrarEntrada(); return; }

  // escolha de obra (chips)
  if (botao && botao.classList.contains("pick")) {
    botao.parentNode.querySelectorAll(".pick").forEach(function (p) {
      p.classList.remove("on");
      p.setAttribute("aria-checked", "false");
    });
    botao.classList.add("on");
    botao.setAttribute("aria-checked", "true");
    if (botao.closest("#tela5")) carregarSaldo();
    return;
  }

  var alvo = e.target.closest("[data-toast]");
   if (alvo && !alvo.disabled) {
    mostrarAviso(alvo.getAttribute("data-toast"));
    if (alvo.id === "finalizar") limparPedido();
  }

  var destino = e.target.closest("[data-go]");
  if (destino) irPara(destino.getAttribute("data-go"));
});

// busca nas listas: ignora acentos e maiúsculas, e avisa quando nada é encontrado
function normalizar(texto) {
  return texto.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

document.querySelectorAll("[data-filtro]").forEach(function (campo) {
  var lista = document.getElementById(campo.getAttribute("data-filtro"));

  var aviso = document.createElement("p");
  aviso.textContent = "Nenhum item encontrado.";
  aviso.style.cssText = "display:none; padding:18px 4px; color:#b9ccd3; font-size:16px;";
  lista.parentNode.insertBefore(aviso, lista.nextSibling);

  campo.addEventListener("input", function () {
    var termo = normalizar(campo.value.trim());
    var visiveis = 0;
    lista.querySelectorAll(".item").forEach(function (item) {
      var nome = normalizar(item.querySelector("strong").textContent);
      var mostrar = nome.indexOf(termo) !== -1;
      item.style.display = mostrar ? "" : "none";
      if (mostrar) visiveis++;
    });
    aviso.style.display = visiveis === 0 ? "block" : "none";
  });
});

// desativa o "-" quando o valor inicial é 0
document.querySelectorAll(".stepper").forEach(function (s) {
  s.querySelector(".minus").disabled = parseInt(s.querySelector("output").textContent, 10) === 0;
});

// index.html#todas mostra as 6 telas lado a lado
if (location.hash === "#todas") { document.body.classList.add("todas"); carregarSaldo(); carregarPendente(); }
else irPara("tela1");
