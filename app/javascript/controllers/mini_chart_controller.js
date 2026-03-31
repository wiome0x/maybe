import { Controller } from "@hotwired/stimulus";

// Renders a TradingView Mini Chart widget inline
export default class extends Controller {
  static values = { symbol: String };

  connect() {
    if (this.element.dataset.loaded) return;
    this.element.dataset.loaded = "true";
    this.render();
  }

  render() {
    const id = `mini-chart-${this.symbolValue.replace(/[^a-zA-Z0-9]/g, "")}`;
    this.element.innerHTML = `<div id="${id}" class="h-full w-full"></div>`;

    const config = {
      symbol: this.symbolValue,
      width: "100%",
      height: "100%",
      locale: document.documentElement.lang === "zh-CN" ? "zh_CN" : "en",
      dateRange: "3M",
      colorTheme: document.documentElement.dataset.theme === "dark" ? "dark" : "light",
      isTransparent: true,
      autosize: true,
      largeChartUrl: "",
      chartOnly: true,
      noTimeScale: true,
    };

    const script = document.createElement("script");
    script.src = "https://s3.tradingview.com/external-embedding/embed-widget-mini-symbol-overview.js";
    script.type = "text/javascript";
    script.async = true;
    script.textContent = JSON.stringify(config);

    document.getElementById(id).appendChild(script);
  }
}
