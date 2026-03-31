import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="market-chart"
// Toggles an inline TradingView chart below the market row
export default class extends Controller {
  static values = { symbol: String, name: String, expanded: { type: Boolean, default: false } };
  static targets = ["row", "chart", "details"];

  toggle() {
    if (this.expandedValue) {
      this.collapse();
    } else {
      this.expand();
    }
  }

  expand() {
    this.expandedValue = true;

    // Hide detail columns, keep name + price
    this.detailsTargets.forEach((el) => (el.hidden = true));

    // Show chart container
    this.chartTarget.hidden = false;
    this.chartTarget.style.height = "400px";

    // Load TradingView widget if not already loaded
    if (!this.chartTarget.dataset.loaded) {
      this.loadWidget();
      this.chartTarget.dataset.loaded = "true";
    }
  }

  collapse() {
    this.expandedValue = false;

    // Restore detail columns
    this.detailsTargets.forEach((el) => (el.hidden = false));

    // Hide chart
    this.chartTarget.hidden = true;
  }

  loadWidget() {
    const containerId = `tv-chart-${this.symbolValue.replace(/[^a-zA-Z0-9]/g, "")}`;
    this.chartTarget.innerHTML = `<div id="${containerId}" class="h-full w-full"></div>`;

    const script = document.createElement("script");
    script.src = "https://s3.tradingview.com/tv.js";
    script.onload = () => {
      if (typeof TradingView === "undefined") return;

      new TradingView.widget({
        container_id: containerId,
        autosize: true,
        symbol: this.symbolValue,
        interval: "D",
        timezone: "Etc/UTC",
        theme:
          document.documentElement.dataset.theme === "dark" ? "dark" : "light",
        style: "1",
        locale:
          document.documentElement.lang === "zh-CN" ? "zh_CN" : "en",
        toolbar_bg: "transparent",
        enable_publishing: false,
        hide_top_toolbar: false,
        hide_legend: false,
        save_image: false,
        studies: ["MASimple@tv-basicstudies"],
      });
    };

    // Only load script once globally
    if (!document.querySelector('script[src*="tradingview.com/tv.js"]')) {
      document.head.appendChild(script);
    } else if (typeof TradingView !== "undefined") {
      script.onload();
    } else {
      // Script exists but not loaded yet, wait for it
      const check = setInterval(() => {
        if (typeof TradingView !== "undefined") {
          clearInterval(check);
          script.onload();
        }
      }, 100);
    }
  }
}
