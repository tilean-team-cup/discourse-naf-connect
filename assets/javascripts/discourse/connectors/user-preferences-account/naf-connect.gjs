import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class NafConnect extends Component {
  @tracked loading = true;
  @tracked connected = false;
  @tracked nafId = null;
  @tracked nafName = null;

  constructor(owner, args) {
    super(owner, args);
    this.loadStatus();
  }

  async loadStatus() {
    try {
      const data = await ajax("/naf/status");
      this.connected = data.connected;
      this.nafId = data.naf_id;
      this.nafName = data.naf_name;
    } catch {
      this.connected = false;
    } finally {
      this.loading = false;
    }
  }

  @action
  async connectNaf() {
    try {
      // AJAX per ottenere l'URL NAF (salva lo state in sessione lato server)
      // poi navighiamo direttamente verso il dominio esterno: Ember non intercetta URL esterni
      const { url } = await ajax("/naf/auth_url");
      window.location.replace(url);
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async disconnectNaf() {
    try {
      await ajax("/naf/disconnect", { type: "DELETE" });
      this.connected = false;
      this.nafId = null;
      this.nafName = null;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  <template>
    <div class="control-group naf-connect-section">
      <label class="control-label">Account NAF</label>
      <div class="controls">
        {{#if this.loading}}
          <span class="loading-placeholder">Caricamento...</span>
        {{else if this.connected}}
          <div class="naf-connected-info">
            <span class="naf-badge">
              ✅ Collegato come <strong>{{this.nafName}}</strong>
              <small>(NAF ID: {{this.nafId}})</small>
            </span>
            <button
              class="btn btn-danger btn-small naf-disconnect-btn"
              {{on "click" this.disconnectNaf}}
            >
              Scollega
            </button>
          </div>
        {{else}}
          <button class="btn btn-primary" {{on "click" this.connectNaf}}>
            Collega Account NAF
          </button>
          <p class="hint">
            Collega il tuo account NAF per accedere al forum con le credenziali NAF.
            Il tuo nome coach verrà sincronizzato automaticamente.
          </p>
        {{/if}}
      </div>
    </div>

    <style>
      .naf-connect-section { margin-top: 1em; }
      .naf-connected-info { display: flex; align-items: center; gap: 1em; }
      .naf-badge small { color: var(--primary-medium); margin-left: 0.4em; }
      .naf-disconnect-btn { margin-left: 0.5em; }
    </style>
  </template>
}
