import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static values = { symbol: String, name: String, expanded: { type: Boolean, default: false } };
  static targets = ["chart"];

  toggle() {
    if (this.expandedValue) {
      this.collapse();
    } else {
      this.expand();
    }
  }

  expand() {
    this.expandedValue = true;
    this.chartTarget.hidden = false;
    this.chartTarget.style.height = "450px";

    if (!this.chartTarget.dataset.loaded) {
      this.loadWidget();
      this.chartTarget.dataset.loaded = "true";
    }
  }

  collapse() {
    this.expandedValue = false;
    this.chartTarget.hidden = true;
  }

  loadWidget() {
    const containerId = `tv-chart-${this.symbolValue.replace(/[^a-zA-Z0-9]/g, "")}`;
    this.chartTarget.innerHTML = `<div id="${containerId}" class="h-full w-full rounded-lg overflow-hidden"></div>`;

    const doInit = () => {
      new TradingView.widget({
        container_id: containerId,
        autosize: true,
        symbol: this.symbolValue,
        interval: "D",
        timezone: "Etc/UTC",
        theme: document.documentElement.dataset.theme === "dark" ? "dark" : "light",
        style: "1",
        locale: document.documentElement.lang === "zh-CN" ? "zh_CN" : "en",
        toolbar_bg: "transparent",
        enable_publishing: false,
        hide_top_toolbar: false,
        hide_legend: false,
        save_image: false,
        studies: ["MASimple@tv-basicstudies"],
      });
    };

    if (typeof TradingView !== "undefined") {
      doInit();
    } else {
      const script = document.createElement("script");
      script.src = "https://s3.tradingview.com/tv.js";
      script.onload = doInit;
      document.head.appendChild(script);
    }
  }
}
