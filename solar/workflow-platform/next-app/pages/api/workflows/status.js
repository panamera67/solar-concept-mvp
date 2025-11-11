import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

export default async function handler(req, res) {
  const { id } = req.query ?? {};

  if (!id) {
    return res.status(400).json({ error: 'id required' });
  }

  const client = await pool.connect();

  try {
    const workflowRes = await client.query('SELECT * FROM workflows WHERE id = $1', [id]);
    const workflow = workflowRes.rows[0];

    if (!workflow) {
      return res.status(404).json({ error: 'workflow not found' });
    }

    const jobsRes = await client.query(
      'SELECT * FROM workflow_jobs WHERE workflow_id = $1 ORDER BY created_at',
      [id]
    );
    res.json({ workflow, jobs: jobsRes.rows });
  } catch (err) {
    console.error('status error', err);
    res.status(500).json({ error: 'internal' });
  } finally {
    client.release();
  }
}
