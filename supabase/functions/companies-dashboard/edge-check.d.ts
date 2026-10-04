/**
 * Minimal ambient declarations so `npm run typecheck:edge` can compile the
 * Edge Function with plain tsc (Deno is not installed here). Intentionally
 * narrow: any drift between these shapes and real usage fails loudly.
 */
declare module "https://esm.sh/@supabase/supabase-js@2" {
  export interface SupabaseClient {
    from(table: string): any;
    rpc(fn: string, params?: Record<string, unknown>): Promise<{ data: any; error: any }>;
  }
  export function createClient(url: string, key: string, options?: Record<string, unknown>): SupabaseClient;
}

declare module "https://esm.sh/jose@6" {
  export function createRemoteJWKSet(url: URL): unknown;
  export function decodeJwt(token: string): Record<string, unknown>;
  export function jwtVerify(
    token: string,
    key: unknown,
    options?: { issuer?: string | string[]; audience?: string | string[] },
  ): Promise<{ payload: Record<string, unknown> }>;
}

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): void;
};
