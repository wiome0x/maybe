import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="market-chart"
export default class extends Controller {
  static values = { symbol: String, name: String };

  open() {
    const dialog = document.createElement("dialog");
    dialog.className =
      "fixed inset-0 z-50 w-[90vw] max-w-5xl h-[80vh] rounded-xl shadow-xl bg-container p-0 backdrop:bg-black/50";

    dialog.innerHTML = `
      <div class="flex flex-col h-full">
        <div class="flex items-center justify-between px-4 py-3 border-b border-secondary">
          <h3 class="text-primary font-medium">${this.nameValue}</h3>
          <button class="p-1.5 rounded-md hover:bg-surface-hover text-secondary" data-action="click->market-chart#close">
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
          </button>
        </div>
        <div class="grow" id="tradingview-widget-container"></div>
      </div>
    `;

    document.body.appendChild(dialog);
    dialog.showModal();

    dialog.addEventListener("click", (e) => {
      if (e.target === dialog) dialog.close();
    });

    dialog.addEventListener("close", () => {
      dialog.remove();
    });

    // Load TradingView widget
    const script = document.createElement("script");
    script.src = "https://s3.tradingview.com/tv.js";
    script.onload = () => {
      new TradingView.widget({
        container_id: "tradingview-widget-container",
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
    document.head.appendChild(script);
  }

  close() {
    const dialog = document.querySelector("dialog[open]");
    if (dialog) dialog.close();
  }
}
