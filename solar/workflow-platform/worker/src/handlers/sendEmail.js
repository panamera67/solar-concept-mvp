module.exports = async function sendEmail({ payload, meta, helpers }) {
  const { to, subject, body } = payload ?? {};
  if (!to) {
    throw new Error('sendEmail payload requires "to"');
  }
  helpers.logger.info({ jobId: meta.jobId, to, subject }, 'sendEmail handler invoked');
  await new Promise((resolve) => setTimeout(resolve, 400));
  helpers.logger.info({ jobId: meta.jobId }, 'Email sent successfully');
  return { ok: true, to, subject };
};
