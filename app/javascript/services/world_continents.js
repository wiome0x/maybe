export default {
  type: "FeatureCollection",
  features: [
    {
      type: "Feature",
      properties: { name: "North America" },
      geometry: {
        type: "Polygon",
        coordinates: [[
          [-168, 71], [-155, 75], [-138, 73], [-121, 71], [-108, 66],
          [-99, 60], [-91, 53], [-84, 46], [-76, 41], [-66, 47],
          [-61, 56], [-66, 63], [-79, 68], [-95, 71], [-116, 72],
          [-138, 72], [-154, 70], [-168, 71]
        ]]
      }
    },
    {
      type: "Feature",
      properties: { name: "South America" },
      geometry: {
        type: "Polygon",
        coordinates: [[
          [-81, 13], [-75, 7], [-69, -5], [-63, -15], [-59, -27],
          [-56, -40], [-54, -51], [-47, -53], [-43, -44], [-41, -33],
          [-43, -18], [-48, -4], [-55, 6], [-64, 15], [-72, 18],
          [-81, 13]
        ]]
      }
    },
    {
      type: "Feature",
      properties: { name: "Europe" },
      geometry: {
        type: "Polygon",
        coordinates: [[
          [-11, 36], [-6, 43], [1, 49], [10, 57], [18, 60],
          [28, 60], [37, 57], [34, 48], [24, 43], [14, 39],
          [6, 38], [-2, 37], [-11, 36]
        ]]
      }
    },
    {
      type: "Feature",
      properties: { name: "Africa" },
      geometry: {
        type: "Polygon",
        coordinates: [[
          [-18, 34], [-8, 29], [2, 23], [10, 14], [19, 5],
          [27, -7], [31, -20], [28, -32], [20, -35], [10, -31],
          [2, -24], [-4, -12], [-10, 2], [-15, 17], [-18, 34]
        ]]
      }
    },
    {
      type: "Feature",
      properties: { name: "Asia" },
      geometry: {
        type: "Polygon",
        coordinates: [[
          [26, 7], [37, 15], [49, 22], [62, 28], [76, 33],
          [88, 41], [104, 48], [118, 52], [134, 56], [145, 50],
          [151, 40], [143, 31], [131, 24], [118, 18], [107, 13],
          [96, 7], [86, 1], [73, -1], [61, 2], [50, 6],
          [39, 8], [26, 7]
        ]]
      }
    },
    {
      type: "Feature",
      properties: { name: "Australia" },
      geometry: {
        type: "Polygon",
        coordinates: [[
          [111, -11], [119, -14], [130, -18], [140, -24], [147, -34],
          [142, -42], [130, -43], [118, -39], [111, -31], [106, -22],
          [111, -11]
        ]]
      }
    },
    {
      type: "Feature",
      properties: { name: "Greenland" },
      geometry: {
        type: "Polygon",
        coordinates: [[
          [-53, 60], [-46, 67], [-36, 73], [-29, 73], [-25, 66],
          [-31, 58], [-42, 55], [-53, 60]
        ]]
      }
    }
  ]
};
