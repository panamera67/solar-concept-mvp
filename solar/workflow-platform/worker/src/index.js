require('dotenv').config();
const db = require('./lib/db');
const pino = require('pino');

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

const POLL_INTERVAL = parseInt(process.env.WORKER_POLL_INTERVAL_MS || '3000', 10);
const MAX_RETRIES = parseInt(process.env.WORKER_MAX_RETRIES || '3', 10);

const handlers = {
  sendEmail: require('./handlers/sendEmail'),
  callApi: require('./handlers/callApi'),
};

const makeHelpers = () => ({
  logger,
  db,
});

async function fetchPendingJob(client) {
  const pickQuery = `
    WITH picked AS (
      SELECT id
      FROM workflow_jobs
      WHERE status = 'pending'
        AND scheduled_at <= NOW()
      ORDER BY scheduled_at ASC
      FOR UPDATE SKIP LOCKED
      LIMIT 1
    )
    UPDATE workflow_jobs AS jobs
    SET status = 'in_progress', updated_at = NOW()
    FROM picked
    WHERE jobs.id = picked.id
    RETURNING jobs.*;
  `;

  const res = await client.query(pickQuery);
  return res.rows[0];
}

async function processJob(job) {
  const { id, name, payload, attempt, max_attempts, workflow_id } = job;
  const handler = handlers[name];

  if (!handler) {
    throw new Error(`No handler registered for job "${name}"`);
  }

  const helpers = makeHelpers();

  try {
    await handler({ payload, meta: { jobId: id, workflowId: workflow_id }, helpers });
    await db.query(
      'UPDATE workflow_jobs SET status = $1, updated_at = NOW() WHERE id = $2',
      ['success', id]
    );

    const remaining = await db.query(
      `SELECT COUNT(*) FROM workflow_jobs WHERE workflow_id = $1 AND status NOT IN ('success', 'failed')`,
      [workflow_id]
    );

    if (Number(remaining.rows[0].count) === 0) {
      await db.query(
        'UPDATE workflows SET status = $1, updated_at = NOW() WHERE id = $2',
        ['completed', workflow_id]
      );
    }

    helpers.logger.info({ jobId: id, workflowId: workflow_id }, 'Job completed');
  } catch (error) {
    const nextAttempt = attempt + 1;
    const maxAttempts = max_attempts || MAX_RETRIES;

    helpers.logger.error({ jobId: id, error: error.message }, 'Job processing error');

    if (nextAttempt >= maxAttempts) {
      await db.query(
        `UPDATE workflow_jobs
         SET status = $1, attempt = $2, last_error = $3, updated_at = NOW()
         WHERE id = $4`,
        ['failed', nextAttempt, error.message, id]
      );
      await db.query(
        'UPDATE workflows SET status = $1, updated_at = NOW() WHERE id = $2',
        ['failed', workflow_id]
      );
      helpers.logger.warn({ jobId: id }, 'Job failed permanently');
    } else {
      const backoffMs = 1000 * Math.pow(2, nextAttempt);
      const scheduledAt = new Date(Date.now() + backoffMs).toISOString();
      await db.query(
        `UPDATE workflow_jobs
         SET status = $1,
             attempt = $2,
             scheduled_at = $3,
             last_error = $4,
             updated_at = NOW()
         WHERE id = $5`,
        ['pending', nextAttempt, scheduledAt, error.message, id]
      );
      helpers.logger.info(
        { jobId: id, nextAttempt, scheduledAt },
        'Job rescheduled for retry'
      );
    }
  }
}

async function loop() {
  const client = await db.pool.connect();
  try {
    const job = await fetchPendingJob(client);
    if (!job) {
      return;
    }
    await processJob(job);
  } catch (error) {
    logger.error({ error: error.message }, 'Worker loop error');
  } finally {
    client.release();
  }
}

async function start() {
  logger.info('Workflow worker starting');
  while (true) {
    await loop();
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL));
  }
}

start().catch((error) => {
  logger.fatal({ error: error.message }, 'Worker failed to start');
  process.exit(1);
});
