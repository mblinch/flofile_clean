(function () {
  var toggle = document.querySelector(".nav-toggle");
  var nav = document.querySelector(".nav");
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }

  // Keep copyright year current when JS is available; static HTML already has the year.
  var year = String(new Date().getFullYear());
  document.querySelectorAll(".footer-year").forEach(function (el) {
    el.textContent = year;
  });
})();
