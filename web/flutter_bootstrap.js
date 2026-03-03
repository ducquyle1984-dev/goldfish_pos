{{flutter_js}}
{{flutter_build_config}}

// Register the service worker in the background for subsequent visits,
// but do NOT block Flutter startup waiting for it to activate.
// This removes the ~4-second wait that causes the spinner on first load.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker
    .register("flutter_service_worker.js?v={{flutter_service_worker_version}}")
    .then(function (reg) {
      // Activate any waiting SW immediately so new deploys take effect fast.
      if (reg.waiting) {
        reg.waiting.postMessage({ type: "SKIP_WAITING" });
      }
      reg.addEventListener("updatefound", function () {
        var newSW = reg.installing;
        if (newSW) {
          newSW.addEventListener("statechange", function () {
            if (
              newSW.state === "installed" &&
              navigator.serviceWorker.controller
            ) {
              newSW.postMessage({ type: "SKIP_WAITING" });
            }
          });
        }
      });
    })
    .catch(function (e) {
      console.warn("[goldfish_pos] Service worker registration failed:", e);
    });
}

// Start Flutter immediately -- do not wait for the service worker to be ready.
_flutter.loader.load();