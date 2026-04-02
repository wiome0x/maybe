import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

const parseLocalDate = d3.timeParse("%Y-%m-%d");
const formatDate = d3.timeFormat("%b %d");

// Connects to data-controller="audit-line-chart"
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
      date: parseLocalDate(d.date),
      total: d.total,
      success_count: d.success_count,
      error_count: d.error_count,
    }));

    if (data.length < 2) {
      this._drawEmpty();
      return;
    }

    const containerWidth = this.element.clientWidth;
    const containerHeight = this.element.clientHeight;
    const margin = { top: 16, right: 16, bottom: 32, left: 40 };
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

    // Scales
    const x = d3
      .scaleTime()
      .domain(d3.extent(data, (d) => d.date))
      .range([0, width]);

    const yMax = d3.max(data, (d) => Math.max(d.success_count, d.error_count));
    const y = d3
      .scaleLinear()
      .domain([0, Math.max(yMax * 1.1, 1)])
      .nice()
      .range([height, 0]);

    // X axis
    const tickCount = Math.min(data.length, Math.floor(width / 60));
    g.append("g")
      .attr("transform", `translate(0,${height})`)
      .call(d3.axisBottom(x).ticks(tickCount).tickFormat(formatDate).tickSize(0))
      .call((g) => g.select(".domain").remove())
      .selectAll("text")
      .attr("fill", "var(--color-secondary)")
      .style("font-size", "11px");

    // Y axis
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

    // Success line
    const successLine = d3
      .line()
      .x((d) => x(d.date))
      .y((d) => y(d.success_count))
      .curve(d3.curveMonotoneX);

    g.append("path")
      .datum(data)
      .attr("fill", "none")
      .attr("stroke", "var(--color-success)")
      .attr("stroke-width", 2)
      .attr("stroke-linejoin", "round")
      .attr("stroke-linecap", "round")
      .attr("d", successLine);

    // Error line
    const errorLine = d3
      .line()
      .x((d) => x(d.date))
      .y((d) => y(d.error_count))
      .curve(d3.curveMonotoneX);

    g.append("path")
      .datum(data)
      .attr("fill", "none")
      .attr("stroke", "var(--color-destructive)")
      .attr("stroke-width", 2)
      .attr("stroke-linejoin", "round")
      .attr("stroke-linecap", "round")
      .attr("d", errorLine);

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
      .text("Not enough data to display chart");
  }

  _drawLegend(margin, containerWidth) {
    const legend = this._svg
      .append("g")
      .attr("transform", `translate(${containerWidth - margin.right}, ${margin.top - 8})`);

    // Success legend
    legend
      .append("line")
      .attr("x1", -120)
      .attr("x2", -105)
      .attr("y1", 0)
      .attr("y2", 0)
      .attr("stroke", "var(--color-success)")
      .attr("stroke-width", 2);

    legend
      .append("text")
      .attr("x", -100)
      .attr("y", 0)
      .attr("dy", "0.35em")
      .attr("fill", "var(--color-secondary)")
      .style("font-size", "12px")
      .text("Success");

    // Error legend
    legend
      .append("line")
      .attr("x1", -50)
      .attr("x2", -35)
      .attr("y1", 0)
      .attr("y2", 0)
      .attr("stroke", "var(--color-destructive)")
      .attr("stroke-width", 2);

    legend
      .append("text")
      .attr("x", -30)
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
