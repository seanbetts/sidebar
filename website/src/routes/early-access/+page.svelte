<script lang="ts">
  import Seo from '$lib/components/Seo.svelte';

  const deviceOptions = ['iPhone', 'iPad', 'Mac'] as const;
  const feedbackOptions = [
    { value: 'yes', label: 'Yes, happy to share feedback' },
    { value: 'maybe', label: 'Possibly, depending on time' },
    { value: 'no', label: 'Not right now' }
  ] as const;

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: 'Early Access',
    url: 'https://trysidebar.ai/early-access',
    description:
      'Join the sideBar early access list to hear about beta invites and launch updates.'
  };

  let name = $state('');
  let email = $state('');
  let heardAbout = $state('');
  let useCase = $state('');
  let feedback = $state('yes');
  let selectedDevices = $state<string[]>([]);

  function toggleDevice(device: (typeof deviceOptions)[number], checked: boolean) {
    selectedDevices = checked
      ? [...selectedDevices, device]
      : selectedDevices.filter((entry) => entry !== device);
  }

  const submissionHref = $derived.by(() => {
    const body = [
      `Name: ${name.trim()}`,
      `Email: ${email.trim()}`,
      `Devices (iPhone, iPad, Mac): ${
        selectedDevices.length > 0 ? selectedDevices.join(', ') : 'Not specified'
      }`,
      `How you heard about sideBar: ${heardAbout.trim() || 'Not specified'}`,
      `How you hope to use it: ${useCase.trim() || 'Not specified'}`,
      `Open to sharing feedback during beta: ${feedback}`
    ].join('\n');

    return `mailto:support@trysidebar.ai?subject=${encodeURIComponent(
      'sideBar early access'
    )}&body=${encodeURIComponent(body)}`;
  });
</script>

<Seo
  title="Early Access"
  description="Join the sideBar early access list to hear about beta invites and launch updates."
  url="https://trysidebar.ai/early-access"
  {jsonLd}
/>

<div class="page">
  <section class="intro">
    <div class="page-shell page-shell--wide intro-shell">
      <div class="intro-copy">
        <p class="eyebrow">Early access</p>
        <h1>Join the early access list</h1>
        <p class="lead">
          sideBar is still in its pre-launch phase. The early access list is how
          you register interest, hear about progress, and put yourself in the
          running for a small invite-only beta.
        </p>
        <p class="supporting">
          Joining the list does not mean immediate access. Beta invites will be
          selective, and the current priority is people who can try sideBar on
          iPhone, iPad, and Mac, where the experience is strongest today.
        </p>
      </div>
    </div>
  </section>

  <section class="details">
    <div class="page-shell page-shell--wide details-shell">
      <form class="form-card" aria-label="Early access form">
        <div class="form-header">
          <h2>Tell us a little bit about yourself</h2>
          <p>
            This first version still sends your request through email, but you can
            complete the details here instead of writing it from scratch.
          </p>
        </div>

        <label class="field">
          <span>Name</span>
          <input bind:value={name} name="name" autocomplete="name" />
        </label>

        <label class="field">
          <span>Email</span>
          <input bind:value={email} name="email" type="email" autocomplete="email" />
        </label>

        <fieldset class="field fieldset">
          <p class="fieldset-label">Which devices do you want to use sideBar on?</p>
          <div class="choice-grid">
            {#each deviceOptions as device}
              <label class="choice">
                <input
                  type="checkbox"
                  checked={selectedDevices.includes(device)}
                  onchange={(event) => {
                    toggleDevice(device, (event.currentTarget as HTMLInputElement).checked);
                  }}
                />
                <span>{device}</span>
              </label>
            {/each}
          </div>
        </fieldset>

        <label class="field">
          <span>How did you hear about sideBar?</span>
          <input bind:value={heardAbout} name="heard-about" />
        </label>

        <label class="field">
          <span>How do you hope to use it?</span>
          <textarea bind:value={useCase} name="use-case" rows="5"></textarea>
        </label>

        <fieldset class="field fieldset">
          <p class="fieldset-label">Are you open to sharing feedback during beta?</p>
          <div class="feedback-list">
            {#each feedbackOptions as option}
              <label class="choice choice--radio">
                <input bind:group={feedback} type="radio" value={option.value} name="feedback" />
                <span>{option.label}</span>
              </label>
            {/each}
          </div>
        </fieldset>

        <div class="cta-row">
          <a class="action action-primary" href={submissionHref}>Send request</a>
          <a class="action action-secondary" href="/pricing">See planned pricing</a>
        </div>
      </form>

      <article class="detail-card detail-card--wide">
        <h2>What happens next</h2>
        <ul>
          <li>Everyone on the list can receive launch updates</li>
          <li>A small number of people will be invited into beta before launch</li>
          <li>Beta access is free and uses a separate tester role</li>
          <li>If you are not invited into beta, you can still hear when sideBar launches publicly</li>
        </ul>
      </article>
    </div>
  </section>
</div>

<style>
  .page {
    --page-width: 78rem;
    --page-gutter: 1.5rem;
    --page-body-size: clamp(1.02rem, 1vw + 0.82rem, 1.125rem);
    --page-display-size: clamp(2.25rem, 4.8vw, 4.5rem);
    --page-heading-size: clamp(1.4rem, 2vw + 1rem, 2rem);
    --page-body-leading: 1.7;
    padding: clamp(2.75rem, 6vw, 5rem) 0 0;
  }

  .intro,
  .details {
    position: relative;
  }

  .intro {
    padding-bottom: clamp(2.5rem, 5vw, 3.5rem);
  }

  .details {
    padding-bottom: clamp(3.5rem, 7vw, 5rem);
  }

  .page-shell {
    margin: 0 auto;
    padding: 0 var(--page-gutter);
  }

  .page-shell--wide {
    max-width: var(--page-width);
  }

  .intro-shell {
    max-width: 52rem;
  }

  .intro-copy {
    display: grid;
    gap: 1rem;
    max-width: 42rem;
  }

  .eyebrow {
    margin: 0;
    font-size: 0.78rem;
    font-weight: 600;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--color-muted-foreground);
  }

  h1,
  h2,
  p,
  ul {
    margin: 0;
  }

  h1,
  h2 {
    color: var(--color-foreground);
  }

  h1 {
    font-size: var(--page-display-size);
    font-weight: var(--font-display-weight);
    line-height: var(--font-display-leading);
    letter-spacing: var(--font-display-tracking);
    text-wrap: balance;
    max-width: 11ch;
  }

  .lead,
  .supporting,
  .form-header p,
  .detail-card li {
    font-size: var(--page-body-size);
    line-height: var(--page-body-leading);
    color: var(--color-muted-foreground);
  }

  .supporting {
    max-width: 40rem;
  }

  .cta-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
    align-items: center;
    margin-top: 0.25rem;
  }

  .action {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 3rem;
    padding: 0.75rem 1.25rem;
    border: 1px solid var(--color-border);
    border-radius: 999px;
    font-size: 0.95rem;
    font-weight: 600;
    text-decoration: none;
    white-space: nowrap;
    transition:
      background-color 0.15s ease,
      color 0.15s ease,
      border-color 0.15s ease;
  }

  .action-primary {
    background: var(--color-primary);
    border-color: var(--color-primary);
    color: var(--color-primary-foreground);
  }

  .action-primary:hover {
    background: var(--color-foreground);
    border-color: var(--color-foreground);
    color: var(--color-background);
  }

  .action-secondary {
    background: transparent;
    color: var(--color-foreground);
  }

  .action-secondary:hover {
    background: var(--color-secondary);
    border-color: var(--color-border);
  }

  .form-card,
  .detail-card {
    padding: 1.35rem;
    border: 1px solid var(--color-border);
    border-radius: calc(var(--radius) * 1.4);
    background: var(--color-card);
    box-shadow: 0 24px 60px -36px var(--shadow-color);
  }

  .detail-card ul {
    padding-left: 1.2rem;
  }

  .detail-card li + li {
    margin-top: 0.6rem;
  }

  .details-shell {
    max-width: 52rem;
  }

  .form-card {
    display: grid;
    gap: 1rem;
  }

  .form-header {
    display: grid;
    gap: 0.4rem;
  }

  .detail-card {
    display: grid;
    gap: 0.85rem;
    margin-top: 1rem;
  }

  .form-card h2,
  .detail-card h2 {
    font-size: var(--page-heading-size);
    font-weight: var(--font-display-weight);
    line-height: 1;
    letter-spacing: var(--font-display-compact-tracking);
  }

  .field {
    display: grid;
    gap: 0.45rem;
  }

  .field > span,
  .fieldset-label {
    font-size: 0.92rem;
    font-weight: 600;
    color: var(--color-foreground);
  }

  .field > input,
  .field > textarea {
    width: 100%;
    border: 1px solid var(--color-border);
    border-radius: 1rem;
    background: var(--color-background);
    color: var(--color-foreground);
    font: inherit;
    font-size: 0.98rem;
    line-height: 1.5;
    padding: 0.9rem 1rem;
    transition:
      border-color 0.15s ease,
      box-shadow 0.15s ease;
  }

  .field > textarea {
    resize: vertical;
    min-height: 8rem;
  }

  .field > input:focus,
  .field > textarea:focus {
    outline: none;
    border-color: var(--color-foreground);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--color-foreground) 10%, transparent);
  }

  .fieldset {
    border: 0;
    padding: 0;
    margin: 0 0 0.55rem;
  }

  .fieldset-label {
    margin: 0 0 0.45rem;
  }

  .choice-grid,
  .feedback-list {
    display: grid;
    gap: 0.6rem;
  }

  .choice-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }

  .choice {
    display: flex;
    align-items: center;
    gap: 0.65rem;
    min-height: 3rem;
    padding: 0.8rem 0.95rem;
    border: 1px solid var(--color-border);
    border-radius: 1rem;
    background: var(--color-background);
    color: var(--color-foreground);
  }

  .choice--radio {
    align-items: flex-start;
  }

  .choice input {
    width: auto;
    margin: 0;
    padding: 0;
    border: 0;
    border-radius: 0;
    box-shadow: none;
    background: transparent;
    accent-color: var(--color-foreground);
    flex: 0 0 auto;
  }

  .choice span {
    font-size: 0.98rem;
    font-weight: 500;
    line-height: 1.4;
    color: var(--color-foreground);
  }

  .choice--radio span {
    max-width: 26rem;
  }

  @media (max-width: 760px) {
    .choice-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 640px) {
    .page {
      --page-gutter: 1rem;
    }

    .action {
      width: 100%;
    }
  }
</style>
