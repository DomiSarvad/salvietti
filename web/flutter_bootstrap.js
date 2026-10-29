{{flutter_js}}
{{flutter_build_config}}

// El motor de dibujo (CanvasKit) se sirve desde la propia app y no desde
// gstatic.com: sin internet, bajarlo del CDN fallaba y la ventana quedaba en blanco.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
