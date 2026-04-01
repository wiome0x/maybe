import { Controller } from "@hotwired/stimulus";

// Ticker search that loads trend chart data via Turbo Frame on button click
export default class extends Controller {
  static targets = ["input", "startDate", "endDate"];

  search() {
    const ticker = this.inputTarget.value.trim().toUpperCase();
    if (!ticker) return;

    const url = new URL("/data_tracking/trend", window.location.origin);
    url.searchParams.set("ticker", ticker);

    if (this.hasStartDateTarget && this.startDateTarget.value) {
      url.searchParams.set("start_date", this.startDateTarget.value);
    }

    if (this.hasEndDateTarget && this.endDateTarget.value) {
      url.searchParams.set("end_date", this.endDateTarget.value);
    }

    const frame = document.getElementById("trend_chart");
    if (frame) {
      frame.src = url.toString();
    }
  }
}
