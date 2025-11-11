const fetch = require('node-fetch');

module.exports = async function callApi({ payload, meta, helpers }) {
  const { url, method = 'GET', body } = payload ?? {};
  if (!url) {
    throw new Error('callApi payload requires "url"');
  }
  helpers.logger.info({ jobId: meta.jobId, url }, 'callApi handler invoking remote API');
  const res = await fetch(url, {
    method,
    body: body ? JSON.stringify(body) : undefined,
    headers: { 'Content-Type': 'application/json' },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`API ${url} failed with status ${res.status}`);
  }
  helpers.logger.info({ jobId: meta.jobId, status: res.status }, 'callApi handler success');
  return { status: res.status, body: text };
};
