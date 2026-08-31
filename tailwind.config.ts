import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        navy: { DEFAULT: "#0F1B33", 2: "#152443", border: "#233457", text: "#AEB9CF" },
        brand: { bg: "#F4F5F8", card: "#FFFFFF", border: "#E5E7EE", text: "#161B27", muted: "#6B7383", slate: "#8A93A6" },
        accent: { DEFAULT: "#E2672B", dark: "#C1531F", bg: "#FCEBE1" },
        good: { DEFAULT: "#2F8F5B", bg: "#E7F5EC" },
        warn: { DEFAULT: "#C4880C", bg: "#FCF1D8" },
        bad: { DEFAULT: "#D8433A", bg: "#FBEAE8" },
      },
      borderRadius: { xl2: "16px" },
    },
  },
  plugins: [],
};
export default config;
