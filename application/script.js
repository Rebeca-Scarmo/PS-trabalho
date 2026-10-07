// Só o front: navegação, contadores e feedbacks visuais. Sem regra de negócio.

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
}

function mostrarAviso(texto) {
  var toast = document.getElementById("toast");
  toast.textContent = texto;
  toast.classList.add("on");
  setTimeout(function () { toast.classList.remove("on"); }, 1800);
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

  // escolha de obra (chips)
  if (botao && botao.classList.contains("pick")) {
    botao.parentNode.querySelectorAll(".pick").forEach(function (p) {
      p.classList.remove("on");
      p.setAttribute("aria-checked", "false");
    });
    botao.classList.add("on");
    botao.setAttribute("aria-checked", "true");
    return;
  }

  var alvo = e.target.closest("[data-toast]");
  if (alvo && !alvo.disabled) mostrarAviso(alvo.getAttribute("data-toast"));

  var destino = e.target.closest("[data-go]");
  if (destino) irPara(destino.getAttribute("data-go"));
});

// busca simples nas listas
document.querySelectorAll("[data-filtro]").forEach(function (campo) {
  campo.addEventListener("input", function () {
    var termo = campo.value.toLowerCase();
    document.querySelectorAll("#" + campo.getAttribute("data-filtro") + " .item").forEach(function (item) {
      var nome = item.querySelector("strong").textContent.toLowerCase();
      item.style.display = nome.indexOf(termo) === -1 ? "none" : "";
    });
  });
});

// desativa o "-" quando o valor inicial é 0
document.querySelectorAll(".stepper").forEach(function (s) {
  s.querySelector(".minus").disabled = parseInt(s.querySelector("output").textContent, 10) === 0;
});

// index.html#todas mostra as 6 telas lado a lado
if (location.hash === "#todas") document.body.classList.add("todas");
else irPara("tela1");
