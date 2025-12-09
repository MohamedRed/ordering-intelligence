import app from './app.js';

const port = process.env.PORT ?? 8080;
app.listen(port, () => {
  console.log(`menu-ingestion listening on :${port}`);
});
