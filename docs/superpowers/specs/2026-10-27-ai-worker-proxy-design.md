# Cloudflare Worker proxy for subscription coding tools

Status: proposed design, awaiting user approval.

## Intent and constraints

Route the user's Claude Code and Codex terminal traffic through a custom Cloudflare Worker so they can use their existing subscriptions from networks that restrict direct provider access. The user chose a Worker reverse proxy, rejected WARP, and wants Cloudflare to be the exit point. No homelab server or local forwarding daemon is part of this design.

Success means real subscription-authenticated requests work through the deployed Worker, including streaming and tool-call continuations. A working HTTP relay alone is not evidence of subscription compatibility. Authentication refresh and remaining direct connections must be tested and documented separately.

## Approaches

- Homelab forward proxy with Cloudflare Tunnel: preserves provider TLS but requires a local connector or WARP and depends on the homelab. Superseded by the user's preference for Cloudflare termination.
- WARP with Cloudflare Gateway: provides Cloudflare egress; explicitly rejected by the user.
- Custom Worker reverse proxy: selected by the user. Allows ordinary CLI configuration without a network daemon, but requires provider-specific routing and compatibility validation.

## Proposed implementation

Use a small TypeScript Worker with Wrangler configuration in a dedicated directory, `infrastructure/ai-worker-proxy`. This language, location, and the illustrative hostname `ai-proxy.hapa.dev` are implementation proposals, not user-selected details. Preserve all unrelated work already in the repository. Reconcile deployment ownership with the existing external-infrastructure contract before publishing.

Use separate path prefixes for Claude and Codex. Map each prefix to a fixed HTTPS provider origin and an explicit set of needed paths and methods. Do not accept arbitrary destination URLs, client-controlled upstream hosts, or credentials in URLs. Start with Anthropic's API origin and Codex's ChatGPT subscription backend, confirming exact path mappings against the installed clients before documenting executable client configurations.

Authenticate access to the Worker using a separate high-entropy secret in a custom header, stored as a Worker secret and supplied by client configuration. Preserve the provider Authorization header. Confirm both clients can attach this header with subscription authentication before deployment; do not fall back to embedding secrets in paths or replacing provider tokens. Strip the proxy credential before forwarding upstream.

Pass request bytes and provider-required headers without translating models or API formats. Preserve Anthropic version and beta headers, including the OAuth capability. Stream responses without full buffering. Preserve useful upstream status codes and rate-limit headers. Support Codex WebSocket upgrades if required by the installed client; validate close and cancellation behavior. Never automatically replay an inference request in the Worker.

Reject unapproved routes and methods before making upstream requests. Do not automatically follow upstream redirects with credentials. Filter hop-by-hop, proxy, and incoming forwarding headers; handle WebSocket upgrade headers separately. Do not relay arbitrary upstream cookies to clients. Return generic internal errors without credentials or request contents.

Disable caching and Worker invocation/request logging by default; do not log bodies, authorization headers, custom proxy secrets, or full request URLs. No KV, database, or provider-token storage is needed. TLS terminates at Cloudflare and a separate TLS connection goes to the provider, so Cloudflare and the Worker can access plaintext prompts, responses, and credentials in memory. This differs from an end-to-end encrypted CONNECT tunnel.

## Compatibility first

Claude's official gateway documentation explicitly allows claude.ai login with ANTHROPIC_BASE_URL when gateway credential variables are absent. Use that path, with independent proxy authentication through custom headers. Do not switch to API-key billing.

Codex's documented chatgpt_base_url does not configure every destination. Inspect the installed version's supported configuration and source/schema where needed to identify the actual model endpoint, subscription authentication selection, custom header support, HTTP streaming, and WebSocket routing. Do not present chatgpt_base_url alone as a complete solution.

Initial browser login, refresh, account metadata, telemetry, updates, MCP servers, and web tools may use other origins. Inventory these independently. Do not imitate provider login pages or send account passwords through the Worker. If required authentication traffic cannot be redirected using supported client settings, report the limitation; do not claim the requested full workflow works or substitute a VPN/API-key solution. An existing-session-only result is partial success.

## Verification and delivery

First validate client endpoint and independent proxy-header configuration without exposing real credentials. Implement focused tests for fixed destinations, missing/invalid proxy authentication, header preservation and stripping, path normalization, redirect handling, streaming, upstream errors, and WebSocket upgrades where applicable. Run type checks and a Wrangler build/dry run.

Prepare deployment configuration and a runbook with secret provisioning, reversible client settings, deployment, rollback, and a compatibility matrix. Publication and changes to active CLI configuration come only after the concrete configuration is reviewable and the Cloudflare account/domain are identified.

After deployment, verify each client using its existing subscription: a short streamed reply, a benign tool call and continuation, cancellation, a longer connection, and authentication refresh where safely testable. Run checks from the restricted network as well as an unrestricted connection. Record installed versions and only mark scenarios actually observed as passing. If Cloudflare egress is rejected by the provider, report that blocker without attempting to evade provider challenges.

## Builder decisions

The builder may choose test libraries, module structure, request bounds, and exact allowlisted paths based on client evidence. Unknown compatibility must be resolved through evidence, not assumptions. No UI, account sharing, token pooling, quota bypass, model translation, or public general-purpose proxy is in scope.

## References

- Claude gateway protocol: https://code.claude.com/docs/en/llm-gateway-protocol
- Codex configuration: https://learn.chatgpt.com/docs/config-file/config-reference
- Worker public CONNECT limitation: https://developers.cloudflare.com/workers/runtime-apis/handlers/connect/
