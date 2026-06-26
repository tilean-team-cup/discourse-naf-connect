import Component from "@glimmer/component";

export default class NafProfile extends Component {
  get nafId() {
    return this.args.outletArgs?.model?.naf_id;
  }

  get nafName() {
    return this.args.outletArgs?.model?.naf_name;
  }

  <template>
    {{#if this.nafId}}
      <div class="naf-profile-info">
        <span class="naf-profile-badge" title="Numero NAF">
          🏈 NAF #{{this.nafId}}
          {{#if this.nafName}}
            &mdash; {{this.nafName}}
          {{/if}}
        </span>
      </div>

      <style>
        .naf-profile-info {
          margin-top: 0.5em;
        }
        .naf-profile-badge {
          display: inline-flex;
          align-items: center;
          gap: 0.3em;
          font-size: 0.9em;
          color: var(--primary-medium);
          background: var(--primary-very-low);
          border: 1px solid var(--primary-low);
          border-radius: 4px;
          padding: 2px 8px;
        }
      </style>
    {{/if}}
  </template>
}
