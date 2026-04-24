import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

const parseLocalDate = d3.timeParse("%Y-%m-%d");

export default class extends Controller {
  static values = {
    data: Object,
    xAxisDateFormat: { type: String, default: "%b %d" },
  };

  connect() {
    this.draw();
    document.addEventListener("turbo:load", this.redraw);
    this.resizeObserver = new ResizeObserver(this.redraw);
    this.resizeObserver.observe(this.element);
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.redraw);
    this.resizeObserver?.disconnect();
    this.clear();
  }

  redraw = () => {
    this.clear();
    this.draw();
  };

  clear() {
    d3.select(this.element).selectAll("*").remove();
  }

  draw() {
    const chartData = this.normalizedSeries;
    if (chartData.length === 0) return;

    const width = this.element.clientWidth;
    const height = this.element.clientHeight;
    const margin = { top: 20, right: 8, bottom: 20, left: 8 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const allPoints = chartData.flatMap((series) => series.values);
    if (allPoints.length < 2) return;

    const xScale = d3
      .scaleTime()
      .range([0, innerWidth])
      .domain(d3.extent(allPoints, (point) => point.date));

    const yValues = allPoints.map((point) => point.value);
    const yMin = d3.min(yValues);
    const yMax = d3.max(yValues);
    const padding = yMin === yMax ? Math.max(Math.abs(yMax) * 0.3, 100) : (yMax - yMin) * 0.15;

    const yScale = d3
      .scaleLinear()
      .range([innerHeight, 0])
      .domain([yMin - padding, yMax + padding]);

    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height]);

    const chart = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    chart
      .append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(
        d3.axisBottom(xScale)
          .tickValues(this.tickValues(chartData))
          .tickSize(0)
          .tickFormat(d3.timeFormat(this.xAxisDateFormatValue)),
      )
      .call((axis) => axis.select(".domain").remove())
      .call((axis) =>
        axis
          .selectAll(".tick text")
          .attr("class", "fg-gray")
          .style("font-size", "12px")
          .style("font-weight", "500"),
      );

    const line = d3
      .line()
      .x((point) => xScale(point.date))
      .y((point) => yScale(point.value));

    chartData.forEach((series) => {
      chart
        .append("path")
        .datum(series.values)
        .attr("fill", "none")
        .attr("stroke", series.color)
        .attr("stroke-width", series.strokeWidth || 2)
        .attr("stroke-linejoin", "round")
        .attr("stroke-linecap", "round")
        .attr("d", line);
    });

    const tooltip = d3
      .select(this.element)
      .append("div")
      .attr(
        "class",
        "bg-container text-sm font-sans absolute p-3 border border-secondary rounded-lg pointer-events-none opacity-0 w-72 shadow-lg",
      );

    const bisectDate = d3.bisector((point) => point.date).left;

    chart
      .append("rect")
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .on("mousemove", (event) => {
        const [x] = d3.pointer(event);
        const hoveredDate = xScale.invert(x);
        const points = chartData.map((series) => {
          const index = bisectDate(series.values, hoveredDate, 1);
          const left = series.values[index - 1];
          const right = series.values[index] || left;
          const point =
            x - xScale(left.date) > xScale(right.date) - x ? right : left;

          return { ...series, point };
        });

        chart.selectAll(".weekly-report-hover-line").remove();
        chart.selectAll(".weekly-report-hover-point").remove();

        chart
          .append("line")
          .attr("class", "weekly-report-hover-line")
          .attr("x1", xScale(points[0].point.date))
          .attr("x2", xScale(points[0].point.date))
          .attr("y1", 0)
          .attr("y2", innerHeight)
          .attr("stroke", "var(--color-gray-300)")
          .attr("stroke-dasharray", "4, 4");

        points.forEach((series) => {
          chart
            .append("circle")
            .attr("class", "weekly-report-hover-point")
            .attr("cx", xScale(series.point.date))
            .attr("cy", yScale(series.point.value))
            .attr("r", series.id === "total" ? 4 : 3)
            .attr("fill", series.color)
            .attr("stroke", "white")
            .attr("stroke-width", 1.5);
        });

        tooltip
          .html(this.tooltipTemplate(points))
          .style("opacity", 1)
          .style("left", `${event.pageX + 12}px`)
          .style("top", `${event.pageY - 12}px`);
      })
      .on("mouseleave", () => {
        chart.selectAll(".weekly-report-hover-line").remove();
        chart.selectAll(".weekly-report-hover-point").remove();
        tooltip.style("opacity", 0);
      });
  }

  tickValues(chartData) {
    const values = chartData[0]?.values || [];
    if (values.length <= 2) return values.map((point) => point.date);

    return [values[0], values[Math.floor((values.length - 1) / 2)], values[values.length - 1]].map(
      (point) => point.date,
    );
  }

  tooltipTemplate(seriesList) {
    const dateLabel = seriesList[0]?.point?.dateFormatted || "";

    return `
      <div style="margin-bottom: 8px; color: var(--color-gray-500);">
        ${this.escapeHtml(dateLabel)}
      </div>
      <div class="space-y-2">
        ${seriesList
          .map(
            (series) => `
              <div class="flex items-center justify-between gap-3">
                <div class="flex items-center gap-2 text-primary">
                  <span style="width: 8px; height: 8px; border-radius: 9999px; background-color: ${series.color}; flex-shrink: 0;"></span>
                  <span>${this.escapeHtml(series.label)}</span>
                </div>
                <span class="text-primary">${this.escapeHtml(series.point.formattedValue)}</span>
              </div>
            `,
          )
          .join("")}
      </div>
    `;
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  get normalizedSeries() {
    return (this.dataValue.series || []).map((series) => ({
      id: series.id,
      label: series.label,
      color: series.color,
      strokeWidth: series.stroke_width,
      values: (series.values || []).map((point) => ({
        date: parseLocalDate(point.date),
        dateFormatted: point.date_formatted,
        value: this.numericValue(point.value),
        formattedValue: this.formattedValue(point.value),
      })),
    }));
  }

  numericValue(value) {
    if (typeof value === "object" && value && "amount" in value) {
      return Number(value.amount);
    }

    return Number(value);
  }

  formattedValue(value) {
    if (typeof value === "object" && value && "formatted" in value) {
      return value.formatted;
    }

    return String(value);
  }
}
