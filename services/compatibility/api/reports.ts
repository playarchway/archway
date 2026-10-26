import { createHandlers } from '../src/handlers.js';
import { databaseStore } from '../src/store.js';

export default {
  fetch(request: Request): Promise<Response> {
    const url = process.env.DATABASE_URL;
    if (!url) return Promise.resolve(Response.json({ error: 'Submission unavailable' }, { status: 503 }));
    return createHandlers(databaseStore(url), process.env.RATE_LIMIT_SECRET ?? '').reports(request);
  },
};
