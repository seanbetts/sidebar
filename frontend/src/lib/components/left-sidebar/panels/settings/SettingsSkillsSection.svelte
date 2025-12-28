<script lang="ts">
  import { Loader2 } from 'lucide-svelte';

  export let isLoadingSkills = false;
  export let skillsError = '';
  export let skills: Array<{ id: string; name: string; description: string; category?: string }> = [];
  export let groupSkills: (
    list: Array<{ id: string; name: string; description: string; category?: string }>
  ) => Array<[string, Array<{ id: string; name: string; description: string; category?: string }>]>;
  export let enabledSkills: string[] = [];
  export let allSkillsEnabled = false;
  export let toggleAllSkills: (enabled: boolean) => void;
  export let toggleSkill: (id: string, enabled: boolean) => void;
</script>

<h3>Skills</h3>
<div class="skills-header">
  <p>Manage installed skills and permissions here.</p>
  <label class="skill-toggle">
    <input
      type="checkbox"
      checked={allSkillsEnabled}
      on:change={(event) => toggleAllSkills((event.currentTarget as HTMLInputElement).checked)}
    />
    <span class="skill-switch" aria-hidden="true"></span>
    <span class="skill-toggle-label">Enable all</span>
  </label>
</div>

<style>
  h3 {
    margin: 0 0 0.5rem;
  }

  .skills-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    color: var(--color-muted-foreground);
    font-size: 0.85rem;
    margin-bottom: 1rem;
  }

  .skills-header p {
    margin: 0;
  }

  .skills-panel {
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .skills-category {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .skills-category-title {
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color-muted-foreground);
  }

  .skills-grid {
    display: grid;
    gap: 0.75rem;
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  @media (max-width: 1200px) {
    .skills-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (max-width: 820px) {
    .skills-grid {
      grid-template-columns: minmax(0, 1fr);
    }
  }

  .skill-row {
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    padding: 0.75rem 0.85rem;
    background: var(--color-sidebar-accent);
  }

  .skill-row-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  .skill-name {
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--color-foreground);
  }

  .skill-description {
    margin-top: 0.35rem;
    font-size: 0.8rem;
    line-height: 1.4;
    color: var(--color-muted-foreground);
  }

  .skill-toggle {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
    user-select: none;
  }

  .skill-toggle input {
    position: absolute;
    opacity: 0;
    width: 1px;
    height: 1px;
  }

  .skill-switch {
    width: 36px;
    height: 20px;
    border-radius: 999px;
    background: var(--color-border);
    position: relative;
    transition: background 0.2s ease;
  }

  .skill-switch::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: var(--color-background);
    transition: transform 0.2s ease;
  }

  .skill-toggle input:checked + .skill-switch {
    background: var(--color-primary);
  }

  .skill-toggle input:checked + .skill-switch::after {
    transform: translateX(16px);
  }

  .skill-toggle input:focus-visible + .skill-switch {
    outline: 2px solid var(--color-ring);
    outline-offset: 2px;
  }

  .skill-toggle-label {
    font-size: 0.8rem;
    color: var(--color-foreground);
  }
</style>
<div class="skills-panel">
  {#if isLoadingSkills}
    <div class="settings-meta">
      <Loader2 size={16} class="spin" />
      Loading skills...
    </div>
  {:else if skillsError}
    <div class="settings-error">{skillsError}</div>
  {:else if skills.length === 0}
    <div class="settings-meta">No skills found.</div>
  {:else}
    {#each groupSkills(skills) as [category, categorySkills]}
      <div class="skills-category">
        <div class="skills-category-title">{category}</div>
        <div class="skills-grid">
          {#each categorySkills as skill}
            <div class="skill-row">
              <div class="skill-row-header">
                <div class="skill-name">{skill.name}</div>
                <label class="skill-toggle">
                  <input
                    type="checkbox"
                    checked={enabledSkills.includes(skill.id)}
                    on:change={(event) =>
                      toggleSkill(skill.id, (event.currentTarget as HTMLInputElement).checked)
                    }
                  />
                  <span class="skill-switch" aria-hidden="true"></span>
                </label>
              </div>
              <div class="skill-description">{skill.description}</div>
            </div>
          {/each}
        </div>
      </div>
    {/each}
  {/if}
</div>
