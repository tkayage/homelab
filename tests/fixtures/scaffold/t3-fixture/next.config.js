/** @type {import('next').NextConfig} */
// output: 'standalone' is required by the scaffolder's T3 Dockerfile (the
// standalone build copies .next/standalone). Without it the scaffolder emits a
// warning; with it the generated multi-stage image works unchanged.
const nextConfig = {
  output: 'standalone',
};

module.exports = nextConfig;
