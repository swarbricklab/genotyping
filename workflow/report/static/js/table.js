/* CNA report — vendored, dependency-free interactivity: table sort + filter,
   tabs, and an image zoom modal. No network, works from file:// offline. */
(function () {
  "use strict";

  // ---- Sortable tables -------------------------------------------------------
  function cellValue(row, idx) {
    var cell = row.cells[idx];
    if (!cell) return "";
    return (cell.getAttribute("data-sort") || cell.textContent || "").trim();
  }

  function sortTable(table, idx, asc) {
    var tbody = table.tBodies[0];
    if (!tbody) return;
    var rows = Array.prototype.slice.call(tbody.rows);
    rows.sort(function (a, b) {
      var x = cellValue(a, idx), y = cellValue(b, idx);
      var nx = parseFloat(x.replace(/,/g, "")), ny = parseFloat(y.replace(/,/g, ""));
      var cmp;
      if (!isNaN(nx) && !isNaN(ny) && x !== "" && y !== "") {
        cmp = nx - ny;
      } else if (x === "" && y !== "") {
        cmp = 1;            // blanks sort last
      } else if (y === "" && x !== "") {
        cmp = -1;
      } else {
        cmp = x.toLowerCase().localeCompare(y.toLowerCase());
      }
      return asc ? cmp : -cmp;
    });
    rows.forEach(function (r) { tbody.appendChild(r); });
  }

  function initSortable(table) {
    var ths = table.tHead ? table.tHead.rows[0].cells : [];
    Array.prototype.forEach.call(ths, function (th, idx) {
      th.addEventListener("click", function () {
        var asc = !(th.classList.contains("sort-asc"));
        Array.prototype.forEach.call(ths, function (h) {
          h.classList.remove("sort-asc", "sort-desc");
        });
        th.classList.add(asc ? "sort-asc" : "sort-desc");
        sortTable(table, idx, asc);
      });
    });
  }

  // ---- Filtering -------------------------------------------------------------
  function applyFilters(tableId) {
    var table = document.getElementById(tableId);
    if (!table || !table.tBodies[0]) return;
    var text = "";
    var textInput = document.querySelector('[data-filter="' + tableId + '"]');
    if (textInput) text = textInput.value.trim().toLowerCase();

    var selects = document.querySelectorAll('[data-filter-select="' + tableId + '"]');
    var rows = table.tBodies[0].rows;
    var shown = 0;
    Array.prototype.forEach.call(rows, function (row) {
      var ok = text === "" || row.textContent.toLowerCase().indexOf(text) !== -1;
      Array.prototype.forEach.call(selects, function (sel) {
        if (!ok || !sel.value) return;
        var col = parseInt(sel.getAttribute("data-col"), 10);
        var cellTxt = (row.cells[col] ? row.cells[col].textContent : "").trim();
        if (cellTxt !== sel.value) ok = false;
      });
      row.style.display = ok ? "" : "none";
      if (ok) shown++;
    });
    var counter = document.querySelector('[data-count="' + tableId + '"]');
    if (counter) counter.textContent = shown + " shown";
  }

  function initFilters() {
    document.querySelectorAll("[data-filter]").forEach(function (el) {
      el.addEventListener("input", function () { applyFilters(el.getAttribute("data-filter")); });
    });
    document.querySelectorAll("[data-filter-select]").forEach(function (el) {
      el.addEventListener("change", function () { applyFilters(el.getAttribute("data-filter-select")); });
    });
  }

  // ---- Tabs ------------------------------------------------------------------
  function initTabs() {
    document.querySelectorAll(".tabs").forEach(function (tabBar) {
      var group = tabBar.getAttribute("data-tabs");
      tabBar.querySelectorAll("button").forEach(function (btn) {
        btn.addEventListener("click", function () {
          var target = btn.getAttribute("data-target");
          tabBar.querySelectorAll("button").forEach(function (b) { b.classList.remove("active"); });
          btn.classList.add("active");
          document.querySelectorAll('.tab-panel[data-group="' + group + '"]').forEach(function (p) {
            p.classList.toggle("active", p.id === target);
          });
        });
      });
    });
  }

  // ---- Image zoom modal ------------------------------------------------------
  function initModal() {
    var modal = document.createElement("div");
    modal.id = "img-modal";
    modal.innerHTML = '<span class="close">&times;</span><img alt="enlarged figure">';
    document.body.appendChild(modal);
    var modalImg = modal.querySelector("img");

    function open(src) { modalImg.src = src; modal.classList.add("open"); }
    function close() { modal.classList.remove("open"); modalImg.src = ""; }

    modal.addEventListener("click", close);
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") close(); });

    document.querySelectorAll("[data-zoom]").forEach(function (el) {
      el.addEventListener("click", function (e) {
        e.preventDefault();
        open(el.getAttribute("data-zoom"));
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("table.sortable").forEach(initSortable);
    initFilters();
    initTabs();
    initModal();
  });
})();
