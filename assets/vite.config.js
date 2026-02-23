import path from "path";
import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig(({ command }) => {
  const isDev = command !== "build";

  return {
    base: isDev ? undefined : "/assets",
    publicDir: "static",
    server: {
      port: 5173,
      strictPort: true,
      host: "0.0.0.0",
      cors: true,
      hmr: {
        host: "localhost",
      },
    },
    plugins: [
      tailwindcss(),
    ],
    resolve: {
      alias: {
        "phoenix": path.resolve(__dirname, "../deps/phoenix"),
        "phoenix_html": path.resolve(__dirname, "../deps/phoenix_html"),
        "phoenix_live_view": path.resolve(__dirname, "../deps/phoenix_live_view"),
      },
    },
    optimizeDeps: {
      include: ["phoenix", "phoenix_html", "phoenix_live_view"],
    },
    build: {
      target: "es2020",
      outDir: "../priv/static/assets",
      emptyOutDir: true,
      sourcemap: isDev,
      rollupOptions: {
        input: {
          app: path.resolve(__dirname, "./js/app.js"),
        },
        output: {
          entryFileNames: "[name].js",
          chunkFileNames: "[name].js",
          assetFileNames: "[name][extname]",
        },
      },
    },
  };
});
