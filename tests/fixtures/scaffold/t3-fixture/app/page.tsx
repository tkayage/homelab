// App Router marker: the presence of app/ (alongside a `next` dependency) makes
// detect classify this fixture as a T3 App-Router project, so the scaffolder
// generates app/api/health/route.ts for the readiness/liveness probe.
export default function Page() {
  return <main>t3-fixture</main>;
}
