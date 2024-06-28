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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket, createHook} from "phoenix_live_view"
// window.LV_VSN="1.0.0-rc.6";import {LiveSocket, createHook} from "/Users/chris/oss/phoenix_live_view/assets/js/phoenix_live_view"
import topbar from "../vendor/topbar"
import Sortable from "../vendor/sortable"

class Counter extends HTMLElement {
  constructor() {
    super()
    let inc = (by) => this.innerText = parseInt(this.innerText) + by
    this.addEventListener("phx:lock:inc", () => inc(1))
    this.addEventListener("phx:lock:dec", () => inc(-1))
  }
}
customElements.define("tt-counter", Counter)

// wrap LV's createHook to prefetch all data-ref elements, and bind JS to the hook element
let prepareHook = (el, callbacks = {}) => {
  let hook = createHook(el, callbacks)
  let js = hook.js()
  let refs = {}
  el.querySelectorAll("[phx-ref]").forEach(el => refs[el.getAttribute("phx-ref")] = el)

  el.addEventListener("phx:call-hook", (e) => {
    e.stopPropagation()
    hook[e.detail.method](e, e.detail.extra)
  })

  return {hook, js, refs}
}

customElements.define("phx-optimistic-stream", class extends HTMLElement {
  connectedCallback() {
    if(this.hook){ return }
    this.hook = createHook(this, {})
    let js = this.hook.js()
    let onDismiss = this.getAttribute("on-dismiss")
    let form = this.querySelector("form[phx-submit]")
    let template = this.querySelector("template")
    let input = form.elements[0]
    let isSubmitting = false
    let insertInto = document.getElementById(this.getAttribute("insert-into"))

    let handleDismiss = () => {
      if(isSubmitting){
        isSubmitting = false
        return
      }
      if(onDismiss){ js.exec(onDismiss) }
    }

    this.addEventListener("blur", () => handleDismiss(), true)

    this.addEventListener("submit", e => {
      if(input.value.trim() === ""){
        e.preventDefault()
        e.stopImmediatePropagation()
        return
      }
      isSubmitting = true
    })

    this.addEventListener("phx:push", e => {
      if(e.target !== form){ return }
      console.log(e.target, e.detail)
      let {lock, unlock} = e.detail
      let pendingItem = this.insertPendingItem(insertInto, template, input)
      unlock([form, input])
      lock([pendingItem], () => pendingItem.remove())
      input.value = ""
      input.focus()
    })
    this.addEventListener("keydown", e => e.key === "Escape" && handleDismiss())
  }

  insertPendingItem(insertInto, template, input){
    console.log("inserting pending item")
    let pendingFragment = template.content.cloneNode(true)
    insertInto.appendChild(pendingFragment)
    let pendingItem = insertInto.lastElementChild
    pendingItem.inserted({input})
    return pendingItem
  }
})

customElements.define("pending-todo", class extends HTMLElement {
  inserted({input}){
    this.querySelector("input").value = input.value
  }
})



class TodoAdd extends HTMLElement {
  connectedCallback() {
    let {hook, js, refs} = prepareHook(this)
    console.log(refs)
    let {input, form, button, template} = refs
    let insertInto = document.getElementById(this.getAttribute("insertInto"))
    let submitTo = this.getAttribute("submitTo")

    hook.addTodoClicked = (e) => {
      input.value = ""
      js.show(form.parentElement)
      js.hide(button)
      requestAnimationFrame(() => input.focus())
    }

    hook.hideTodoForm = () => {
      js.hide(form.parentElement)
      js.show(button)
    }

    hook.todoFormSubmitted = (e) => {
      e.preventDefault()
      if(input.value.trim() === ""){ return }

      let pendingTodo = this.insertPendingTodo(insertInto, template, input.value)
      hook.pushEventTo(submitTo, "create", {title: input.value}, () => pendingTodo.remove())
      input.value = ""
    }
    input.addEventListener("keydown", e => e.key === "Escape" && hook.hideTodoForm(e))
  }

  insertPendingTodo(insertInto, template, todoText){
    let pendingTodo = template.content.cloneNode(true)
    pendingTodo.querySelector("input").value = todoText
    insertInto.appendChild(pendingTodo)
    return insertInto.lastElementChild
  }
}

customElements.define("tt-todo-add", TodoAdd)


import {LitElement, html, css} from 'lit';
      // <phx-hook localCount={@count}>
      //   <script>
      //     export default function(){
      //       this.localCount = 0
      //       this.addEventListener("phx-click:inc", () => this.localCount++)
      //       this.addEventListener("phx-click:dec", () => this.localCount--)
      //     }
      //   </script>
      //   <.header>The count is ${this.localCount}</.header>
      //   <button phx-click="dec">-</button>
      //   <button phx-click="inc">+</button>
      // </phx-hook>
class PhxHook extends HTMLElement {
  constructor() {
    super()
    this.attachShadow({ mode: 'open' })
    this.scriptImported = false
  }

  connectedCallback() {
    this.render()
    this.injectAndExecuteScript()

    // Dynamically observe attributes
    this.observedAttributes = Array.from(this.attributes).map(attr => attr.name)
  }

  static get observedAttributes() {
    return []
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (oldValue !== newValue) {
      this.render()
    }
  }

  async injectAndExecuteScript() {
    const script = this.querySelector('script')
    if (!script) return

    const scriptContent = script.textContent.trim()
    const module = await this.injectScript(scriptContent)
    if (module) {
      const defaultExport = module.default
      defaultExport.call(this)
    }
  }

  injectScript(scriptContent) {
    const script = document.createElement('script')
    script.type = 'module'
    const blob = new Blob([scriptContent], { type: 'application/javascript' })
    const url = URL.createObjectURL(blob)
    script.src = url
    script.setAttribute('nonce', 'YourNonceValue')

    document.body.appendChild(script)

    return new Promise((resolve, reject) => {
      script.onload = async () => {
        try {
          const module = await import(url)
          URL.revokeObjectURL(url)  // Cleanup the blob URL after importing
          resolve(module)
        } catch (err) {
          reject(err)
        } finally {
          document.body.removeChild(script)  // Clean up script tag
        }
      }
      script.onerror = (err) => {
        URL.revokeObjectURL(url)
        document.body.removeChild(script)  // Clean up script tag
        reject(err)
      }
    })
  }

  render() {
    const template = this.innerHTML
    let renderedContent = template

    Array.from(this.attributes).forEach(attr => {
      const attrName = attr.name
      const attrValue = this.getAttribute(attrName) || ''
      const regex = new RegExp(`\\$\\{${attrName}\\}`, 'g')
      renderedContent = renderedContent.replace(regex, attrValue)
    })

    this.shadowRoot.innerHTML = `
      <style>
        /* Add any styles you need here */
      </style>
      ${renderedContent}
    `
  }
}

customElements.define('phx-hook', PhxHook)
let Hooks = {}


Hooks.LocalTime = {
  mounted(){ this.updated() },
  updated() {
    let dt = new Date(this.el.textContent)
    let options = {hour: "2-digit", minute: "2-digit", hour12: true, timeZoneName: "short"}
    this.el.textContent = `${dt.toLocaleString('en-US', options)}`
    this.el.classList.remove("invisible")
  }
}

Hooks.Sortable = {
  mounted(){
    let group = this.el.dataset.group
    let isDragging = false
    this.el.addEventListener("focusout", e => isDragging && e.stopImmediatePropagation())
    let sorter = new Sortable(this.el, {
      group: group ? {name: group, pull: true, put: true} : undefined,
      animation: 150,
      dragClass: "drag-item",
      ghostClass: "drag-ghost",
      onStart: e => isDragging = true, // prevent phx-blur from firing while dragging
      onEnd: e => {
        isDragging = false
        let params = {old: e.oldIndex, new: e.newIndex, to: e.to.dataset, ...e.item.dataset}
        this.pushEventTo(this.el, this.el.dataset["drop"] || "reposition", params)
      }
    })
  }
}

Hooks.SortableInputsFor = {
  mounted(){
    let group = this.el.dataset.group
    let sorter = new Sortable(this.el, {
      group: group ? {name: group, pull: true, put: true} : undefined,
      animation: 150,
      dragClass: "drag-item",
      ghostClass: "drag-ghost",
      handle: "[data-handle]",
      forceFallback: true,
      onEnd: e => {
        this.el.closest("form").querySelector("input").dispatchEvent(new Event("input", {bubbles: true}))
      }
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
  dom: {jsQuerySelectorAll: (sourceEl, query) => {
    if(query.startsWith("$")){
      let scope = sourceEl.closest(`[data-scope]`) || sourceEl.closest(`[data-phx-session]`)
      let els = scope.querySelectorAll(`[data-ref="${query.slice(1)}"]`)
      if(els.length === 0){ console.error(`no ref ${query} found`, sourceEl) }
      return els
    } else {
      return document.querySelectorAll(query)
    }
  }}
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
