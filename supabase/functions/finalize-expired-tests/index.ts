// LOGOS Test Driller expiry worker.
// Deploy as a Supabase Edge Function and invoke only from a trusted scheduler.
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CRON_SECRET.
// Never expose these values in browser code or commit them to the repository.

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const cronSecret = Deno.env.get("CRON_SECRET");
  const suppliedSecret = request.headers.get("x-cron-secret");
  if (!cronSecret || !suppliedSecret || suppliedSecret !== cronSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return Response.json(
      { error: "Server configuration is incomplete" },
      { status: 500 },
    );
  }

  try {
    const response = await fetch(
      `${supabaseUrl.replace(/\/$/, "")}/rest/v1/rpc/logos_td_finalize_expired_attempts`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
        body: "{}",
      },
    );

    const body = await response.text();
    if (!response.ok) {
      console.error("Expiry RPC failed", response.status, body);
      return Response.json(
        { error: "Expired-attempt processing failed" },
        { status: 502 },
      );
    }

    return Response.json({
      ok: true,
      finalized: Number(body) || 0,
    });
  } catch (error) {
    console.error("Expiry worker error", error);
    return Response.json(
      { error: "Expiry worker could not reach the database" },
      { status: 502 },
    );
  }
});
