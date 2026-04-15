import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

/**
 * webhook payload para Database Inserts (no technique_feedbacks)
 * ou webhook payload para insert no Storage (bucket = technique_videos).
 * 
 * Assumiremos que este server é engatilhado via Supabase Database Webhook (AFTER INSERT) 
 * na tabela `technique_feedbacks`.
 */
serve(async (req) => {
  try {
    const payload = await req.json();

    // Extrai informacões do trigger de database (record)
    const record = payload.record;
    if (!record) {
      return new Response(JSON.stringify({ error: "No record found" }), { status: 400 });
    }

    const { id, user_id, exercise_name, raw_video_path } = record;

    if (!raw_video_path) {
      return new Response(JSON.stringify({ error: "Missing raw_video_path" }), { status: 400 });
    }

    const pythonServiceUrl = Deno.env.get("PYTHON_CV_SERVICE_URL");
    const pythonAuthToken = Deno.env.get("PYTHON_CV_SERVICE_TOKEN"); // optional security

    if (!pythonServiceUrl) {
      console.warn("PYTHON_CV_SERVICE_URL is not set");
      // MOCK BEHAVIOR para testes se url não estiver setada
      return new Response(JSON.stringify({ message: "Simulated Webhook. Python CV URL not configured." }), { status: 200 });
    }

    // Dispara a requisição assíncrona pro Microserviço Python.
    // Usamos fetch e não fazemos await na resposta completa caso seja muito lenta.
    // Opcionalmente: esperar a resposta se timeout config > 60s
    fetch(`${pythonServiceUrl}/process-video`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${pythonAuthToken}`
      },
      body: JSON.stringify({
        feedback_id: id,
        user_id: user_id,
        exercise_name: exercise_name,
        raw_video_path: raw_video_path
      }),
    }).catch(err => {
      console.error("Failed to enqueue python job:", err);
    });

    return new Response(JSON.stringify({ 
      success: true, 
      message: "Processing job sent to CV service." 
    }), { status: 200, headers: { "Content-Type": "application/json" } });

  } catch (error) {
    console.error("Error processing technique trigger", error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
