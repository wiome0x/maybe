import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

// Connects to data-controller="audit-bar-chart"
export default class extends Controller {
  static values = {
    data: { type: Array, default: [] },
  };

  _svg = null;
  _resizeObserver = null;

  connect() {
    this._draw();
    document.addEventListener("turbo:load", this._redraw);
    this._setupResizeObserver();
  }

  disconnect() {
    this._teardown();
    document.removeEventListener("turbo:load", this._redraw);
    this._resizeObserver?.disconnect();
  }

  _redraw = () => {
    this._teardown();
    this._draw();
  };

  _teardown() {
    this._svg = null;
    d3.select(this.element).selectAll("*").remove();
  }

  _draw() {
    const data = this.dataValue.map((d) => ({
      provider_name: d.provider_name,
      total: d.total,
      error_count: d.error_count,
      success_count: d.total - d.error_count,
    }));

    if (data.length === 0) {
      this._drawEmpty();
      return;
    }

    const containerWidth = this.element.clientWidth;
    const containerHeight = this.element.clientHeight;
    const margin = { top: 16, right: 16, bottom: 40, left: 48 };
    const width = containerWidth - margin.left - margin.right;
    const height = containerHeight - margin.top - margin.bottom;

    if (width <= 0 || height <= 0) return;

    this._svg = d3
      .select(this.element)
      .append("svg")
      .attr("width", containerWidth)
      .attr("height", containerHeight)
      .attr("viewBox", [0, 0, containerWidth, containerHeight]);

    const g = this._svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    const color = d3.scaleOrdinal(d3.schemeTableau10);

    // Scales
    const x = d3
      .scaleBand()
      .domain(data.map((d) => d.provider_name))
      .range([0, width])
      .padding(0.3);

    const yMax = d3.max(data, (d) => d.total);
    const y = d3
      .scaleLinear()
      .domain([0, Math.max(yMax * 1.1, 1)])
      .nice()
      .range([height, 0]);

    // Y axis with grid lines
    g.append("g")
      .call(d3.axisLeft(y).ticks(5).tickSize(-width))
      .call((g) => g.select(".domain").remove())
      .call((g) =>
        g
          .selectAll(".tick line")
          .attr("stroke", "var(--color-gray-200)")
          .attr("stroke-opacity", 0.5)
      )
      .selectAll("text")
      .attr("fill", "var(--color-secondary)")
      .style("font-size", "11px");

    // X axis
    g.append("g")
      .attr("transform", `translate(0,${height})`)
      .call(d3.axisBottom(x).tickSize(0))
      .call((g) => g.select(".domain").remove())
      .selectAll("text")
      .attr("fill", "var(--color-secondary)")
      .style("font-size", "11px")
      .attr("text-anchor", "end")
      .attr("transform", "rotate(-20)");

    // Stacked bars: success portion (bottom) + error portion (top)
    data.forEach((d) => {
      // Success portion
      g.append("rect")
        .attr("x", x(d.provider_name))
        .attr("y", y(d.total))
        .attr("width", x.bandwidth())
        .attr("height", Math.max(0, y(0) - y(d.success_count)))
        .attr("fill", color(d.provider_name))
        .attr("rx", 2);

      // Error portion stacked on top
      if (d.error_count > 0) {
        g.append("rect")
          .attr("x", x(d.provider_name))
          .attr("y", y(d.total))
          .attr("width", x.bandwidth())
          .attr("height", Math.max(0, y(0) - y(d.error_count)))
          .attr("fill", "var(--color-destructive)")
          .attr("rx", 2);
      }
    });

    // Legend
    this._drawLegend(margin, containerWidth);
  }

  _drawEmpty() {
    const containerWidth = this.element.clientWidth;
    const containerHeight = this.element.clientHeight;

    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("width", containerWidth)
      .attr("height", containerHeight);

    svg
      .append("text")
      .attr("x", containerWidth / 2)
      .attr("y", containerHeight / 2)
      .attr("text-anchor", "middle")
      .attr("fill", "var(--color-secondary)")
      .style("font-size", "14px")
      .text("No provider data to display");
  }

  _drawLegend(margin, containerWidth) {
    const legend = this._svg
      .append("g")
      .attr("transform", `translate(${containerWidth - margin.right}, ${margin.top - 8})`);

    // Error legend
    legend
      .append("rect")
      .attr("x", -80)
      .attr("y", -6)
      .attr("width", 12)
      .attr("height", 12)
      .attr("fill", "var(--color-destructive)")
      .attr("rx", 2);

    legend
      .append("text")
      .attr("x", -64)
      .attr("y", 0)
      .attr("dy", "0.35em")
      .attr("fill", "var(--color-secondary)")
      .style("font-size", "12px")
      .text("Errors");
  }

  _setupResizeObserver() {
    this._resizeObserver = new ResizeObserver(() => {
      this._redraw();
    });
    this._resizeObserver.observe(this.element);
  }
}
