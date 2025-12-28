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
