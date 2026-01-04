import { describe, expect, it } from 'vitest';

import { APIError, handleFetchError, parseError } from '$lib/utils/errorHandling';

describe('errorHandling', () => {
  it('parseError returns APIError details', () => {
    const error = new APIError({ message: 'Bad', status: 400, code: 'BAD' });
    const parsed = parseError(error);

    expect(parsed).toEqual({
      message: 'Bad',
      status: 400,
      code: 'BAD',
      context: undefined
    });
  });

  it('parseError normalizes generic errors', () => {
    const parsed = parseError(new Error('Boom'));
    expect(parsed).toEqual({ message: 'Boom', status: 500 });
  });

  it('handleFetchError throws APIError', async () => {
    const response = new Response(JSON.stringify({ error: 'Nope' }), { status: 404 });

    await expect(handleFetchError(response)).rejects.toMatchObject({
      name: 'APIError',
      message: 'Nope',
      status: 404
    });
  });
});
