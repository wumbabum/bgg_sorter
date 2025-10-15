// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/web"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
// Hook to preserve mobile search state across LiveView updates
const mobileSearchHook = {
  mounted() {
    this.restoreMobileSearchState();
  },
  updated() {
    this.restoreMobileSearchState();
  },
  restoreMobileSearchState() {
    // Check if we should restore mobile search state
    const form = this.el.querySelector('.search-form');
    const headerContent = this.el.querySelector('.global-header-content');
    
    if (form && window.innerWidth <= 768) {
      // If there was a search just performed, briefly restore the open state
      // to allow smooth closing animation
      const urlParams = new URLSearchParams(window.location.search);
      const hasUsername = window.location.pathname.includes('/collection/');
      
      if (hasUsername && sessionStorage.getItem('mobileSearchWasOpen') === 'true') {
        // Restore the open state briefly, then close it smoothly
        form.setAttribute('data-mobile-search-open', 'true');
        headerContent?.classList.add('mobile-search-active');
        
        setTimeout(() => {
          form.removeAttribute('data-mobile-search-open');
          headerContent?.classList.remove('mobile-search-active');
          sessionStorage.removeItem('mobileSearchWasOpen');
        }, 50); // Brief delay to allow for smooth close
      }
    }
  }
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, MobileSearchHook: mobileSearchHook},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Mobile search behavior: expand input on first click, submit on second click
window.handleMobileSearch = function(event, button) {
  const isMobileState = window.innerWidth <= 768;
  
  // On desktop, always allow form submission
  if (!isMobileState) {
    return; // Let normal form submission happen on desktop
  }
  
  // Mobile state: track toggle state with data attribute
  const form = button.parentElement;
  const searchInput = form.querySelector('.search-input');
  const isToggled = form.hasAttribute('data-mobile-search-open');
  const headerContent = document.querySelector('.global-header-content');
  
  if (!isToggled) {
    // Mobile state AND not toggled: prevent submission, just open input
    event.preventDefault();
    event.stopPropagation();
    
    // Mark as toggled and focus input to trigger CSS expansion
    form.setAttribute('data-mobile-search-open', 'true');
    headerContent?.classList.add('mobile-search-active');
    searchInput.focus();
    
    return false;
  } else {
    // Mobile state AND toggled: check if input has value
    const inputValue = searchInput.value.trim();
    
    if (inputValue === '') {
      // Empty input: close the search instead of submitting
      event.preventDefault();
      event.stopPropagation();
      
      console.log('Mobile search: Closing empty input');
      
      // Blur first to ensure focus styles don't interfere
      searchInput.blur();
      
      // Small delay to ensure blur completes before starting close animation
      setTimeout(() => {
        // Remove the toggle state to close the search
        form.removeAttribute('data-mobile-search-open');
        headerContent?.classList.remove('mobile-search-active');
        
        // Clear the input value after animation completes for clean state
        setTimeout(() => {
          searchInput.value = '';
          console.log('Mobile search: Input cleared and animation complete');
        }, 150); // Match the CSS transition duration
      }, 10); // Small delay to ensure blur is processed
      
      return false;
    } else {
      // Has input value: allow submission
      // Save that mobile search was open for restoration after navigation
      sessionStorage.setItem('mobileSearchWasOpen', 'true');
      
      // Remove the toggle state for next interaction
      form.removeAttribute('data-mobile-search-open');
      headerContent?.classList.remove('mobile-search-active');
      
      // Let the form submit normally
      return true;
    }
  }
}

// Close mobile search when clicking outside or losing focus
document.addEventListener('click', function(event) {
  if (window.innerWidth <= 768) {
    const searchForms = document.querySelectorAll('.search-form[data-mobile-search-open]');
    const headerContent = document.querySelector('.global-header-content');
    searchForms.forEach(function(form) {
      // Don't close if clicking on the Advanced button or other nav elements
      const isAdvancedButton = event.target.closest('.nav-button');
      const isWithinForm = form.contains(event.target);
      
      // If click is outside the form AND not on the Advanced button, close it
      if (!isWithinForm && !isAdvancedButton) {
        form.removeAttribute('data-mobile-search-open');
        headerContent?.classList.remove('mobile-search-active');
        const input = form.querySelector('.search-input');
        if (input) {
          input.blur();
          // Clear the input value after animation completes for clean state
          setTimeout(() => {
            input.value = '';
          }, 150); // Match the CSS transition duration
        }
      }
    });
  }
});

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

