type IngestionJobLike = {
  status: string | null;
  stage: string | null;
  user_message?: string | null;
  error_message?: string | null;
};

function formatStage(value: string): string {
  return value.replace(/_/g, ' ');
}

export function buildIngestionStatusMessage(job?: IngestionJobLike): string {
  if (!job) return 'Preparing file…';
  if (job.status === 'failed') {
    return job.user_message || job.error_message || 'File processing failed.';
  }
  if (job.user_message) {
    return job.user_message;
  }
  const stage = job.stage || job.status || 'processing';
  if (stage === 'queued') {
    return 'Processing…';
  }
  const label = formatStage(stage);
  return `${label.charAt(0).toUpperCase() + label.slice(1)}…`;
}
