import { useState } from 'react';

export default function Home() {
  const [workflowId, setWorkflowId] = useState('');
  const [status, setStatus] = useState(null);

  const startWorkflow = async () => {
    const res = await fetch('/api/workflows/start', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        type: 'demo_flow',
        payload: { origin: 'demo-ui' },
        tasks: [
          {
            name: 'sendEmail',
            payload: { to: 'demo@example.com', subject: 'Hello', body: 'Solar Concept Workflow demo' },
          },
          {
            name: 'callApi',
            payload: { url: 'https://httpbin.org/get' },
          },
        ],
      }),
    });
    const data = await res.json();
    if (res.ok) {
      setWorkflowId(data.workflowId);
      setStatus(null);
    } else {
      alert(data.error || 'Failed to start workflow');
    }
  };

  const refreshStatus = async () => {
    if (!workflowId) return;
    const res = await fetch(`/api/workflows/status?id=${workflowId}`);
    const data = await res.json();
    setStatus(data);
  };

  return (
    <main style={{ padding: '2rem', fontFamily: 'sans-serif' }}>
      <h1>Solar Concept Workflow Platform</h1>
      <p>Démarrez un workflow de démonstration et visualisez son statut.</p>
      <button onClick={startWorkflow}>Start demo workflow</button>
      {workflowId && (
        <section style={{ marginTop: '1.5rem' }}>
          <p>
            Workflow ID: <code>{workflowId}</code>
          </p>
          <button onClick={refreshStatus}>Refresh status</button>
        </section>
      )}
      {status && (
        <section style={{ marginTop: '1.5rem' }}>
          <h2>Status</h2>
          <pre style={{ background: '#f5f5f5', padding: '1rem', overflow: 'auto' }}>
            {JSON.stringify(status, null, 2)}
          </pre>
        </section>
      )}
    </main>
  );
}
