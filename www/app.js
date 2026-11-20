(function () {
  "use strict";

  var RETRY_MS = 5000;
  var DEFAULT_CONFIG = { name: "0", title: "Live Stream" };

  function getFallbackName() {
    var params = new URLSearchParams(window.location.search);
    var requested = params.get("stream");
    return requested ? requested : DEFAULT_CONFIG.name;
  }

  function loadConfig() {
    return fetch("/stream.json", { cache: "no-store" })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("stream.json returned " + response.status);
        }
        return response.json();
      })
      .catch(function () {
        return { name: getFallbackName(), title: DEFAULT_CONFIG.title };
      });
  }

  function playlistUrl(name) {
    return "/live/" + encodeURIComponent(name) + ".m3u8";
  }

  function init(config) {
    var name = config && config.name ? String(config.name) : getFallbackName();
    var title = config && config.title ? String(config.title) : DEFAULT_CONFIG.title;
    var source = playlistUrl(name);
    var status = document.getElementById("status");
    var titleNode = document.getElementById("title");
    var retryTimer = null;

    document.title = title;
    titleNode.textContent = title;

    var player = videojs("player", {
      controls: true,
      autoplay: true,
      muted: true,
      liveui: true,
      fluid: true,
      responsive: true,
      playsinline: true,
      preload: "auto",
      sources: [{ src: source, type: "application/vnd.apple.mpegurl" }]
    });

    function setStatus(message) {
      status.textContent = message;
    }

    function startPlayback() {
      var promise = player.play();
      if (promise && typeof promise.catch === "function") {
        promise.catch(function (err) {
          if (player.error()) {
            return;
          }
          if (err && err.name === "AbortError") {
            return;
          }
          status.classList.remove("is-live");
          setStatus("Click play to start");
        });
      }
    }

    function scheduleRetry() {
      if (retryTimer) {
        return;
      }
      retryTimer = window.setTimeout(function () {
        retryTimer = null;
        player.src({ src: source, type: "application/vnd.apple.mpegurl" });
        startPlayback();
      }, RETRY_MS);
    }

    player.on("playing", function () {
      if (player.paused()) {
        return;
      }
      setStatus("Live");
      status.classList.add("is-live");
    });

    player.on("waiting", function () {
      if (!player.paused()) {
        setStatus("Buffering…");
      }
    });

    player.on("error", function () {
      status.classList.remove("is-live");
      setStatus("Stream offline — retrying…");
      scheduleRetry();
    });

    player.on("dispose", function () {
      if (retryTimer) {
        window.clearTimeout(retryTimer);
      }
    });

    player.ready(function () {
      startPlayback();
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    loadConfig().then(init);
  });
})();
