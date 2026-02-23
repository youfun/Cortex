import "vite/modulepreload-polyfill";
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "topbar"
import "../css/app.css"

const Hooks = {
  ScrollToBottom: {
    mounted() {
      this.scrollToBottom();
    },
    updated() {
      this.scrollToBottom();
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight;
    }
  },

  MessageInput: {
    mounted() {
      this.adjustHeight();
      
      this.onKeyDown = (e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          const form = this.el.form;
          if (form) {
            form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
          }
        }
      };
      
      this.onInput = () => {
        this.adjustHeight();
      };
      
      this.el.addEventListener("keydown", this.onKeyDown);
      this.el.addEventListener("input", this.onInput);
    },
    
    adjustHeight() {
      this.el.style.height = 'auto';
      this.el.style.height = Math.min(this.el.scrollHeight, 120) + 'px';
    },
    
    destroyed() {
      this.el.removeEventListener("keydown", this.onKeyDown);
      this.el.removeEventListener("input", this.onInput);
    }
  },

  LocalTime: {
    mounted() {
      this.convertToLocalTime();
    },
    updated() {
      this.convertToLocalTime();
    },
    convertToLocalTime() {
      const utcTime = this.el.dataset.utcTime;
      if (!utcTime) return;
      
      try {
        const date = new Date(utcTime);
        const hours = date.getHours().toString().padStart(2, '0');
        const minutes = date.getMinutes().toString().padStart(2, '0');
        this.el.textContent = `${hours}:${minutes}`;
      } catch (e) {
        console.error("Failed to parse time:", e);
      }
    }
  }
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#0d9488"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

window.addEventListener("phx:play_audio", (e) => {
  const url = e.detail.url;
  if (url) {
    const audio = new Audio(url);
    audio.play().catch(err => {
      console.error("Audio playback failed:", err);
    });
  }
});

// expose liveSocket on window for web console debug logs and latency simulation:
window.liveSocket = liveSocket