import { Pool } from 'pg';
import assert from 'assert';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { type, payload, tasks } = req.body ?? {};

  try {
    assert(type, 'type is required');
    assert(Array.isArray(tasks) && tasks.length > 0, 'tasks array required');
  } catch (err) {
    return res.status(400).json({ error: err.message });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const wfRes = await client.query(
      `INSERT INTO workflows (type, payload) VALUES ($1, $2) RETURNING *`,
      [type, payload || {}]
    );
    const workflow = wfRes.rows[0];

    const insertText = `INSERT INTO workflow_jobs 
      (workflow_id, name, payload, max_attempts, idempotency_key) 
      VALUES ($1, $2, $3, $4, $5)`;

    for (const task of tasks) {
      const maxAttempts = task.max_attempts || 3;
      await client.query(insertText, [
        workflow.id,
        task.name,
        task.payload || {},
        maxAttempts,
        task.idempotency_key || null,
      ]);
    }

    await client.query('COMMIT');
    res.status(201).json({ workflowId: workflow.id });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('start workflow error', err);
    res.status(500).json({ error: 'Failed to start workflow' });
  } finally {
    client.release();
  }
}
