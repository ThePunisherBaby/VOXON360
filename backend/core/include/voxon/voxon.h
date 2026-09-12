/*
 * VOXON90 · API en C del motor local.
 *
 * Todo funciona sin internet: el motor guarda los datos en un archivo SQLite
 * del propio equipo.
 *
 * Cada operación es una solicitud JSON:
 *   {"method": "sales.complete", "actor": "<id de usuario>", "params": {...}}
 * y devuelve una respuesta JSON:
 *   {"ok": true,  "result": ...}
 *   {"ok": false, "error": {"code": "cash_session_closed", "message": "..."}}
 *
 * Un mismo voxon_engine puede usarse desde varios hilos: el motor ejecuta las
 * operaciones de una en una.
 */
#ifndef VOXON_VOXON_H
#define VOXON_VOXON_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  if defined(VOXON_BUILDING_SHARED)
#    define VOXON_API __declspec(dllexport)
#  elif defined(VOXON_STATIC)
#    define VOXON_API
#  else
#    define VOXON_API __declspec(dllimport)
#  endif
#else
#  define VOXON_API __attribute__((visibility("default")))
#endif

typedef struct voxon_engine voxon_engine;

/* Versión del motor, por ejemplo "0.1.0". No se libera. */
VOXON_API const char* voxon_version(void);

/*
 * Abre o crea la base de datos en `path` y aplica las migraciones pendientes.
 * Usa ":memory:" para una base temporal. Devuelve NULL si falla; en ese caso,
 * si `error_json` no es NULL, recibe una respuesta de error que debe liberarse
 * con voxon_free.
 */
VOXON_API voxon_engine* voxon_open(const char* path, char** error_json);

/*
 * Igual que voxon_open, con opciones en JSON (puede ser NULL):
 *   {"pinIterations": 60000, "loginMaxFailures": 5, "loginLockSeconds": 30}
 */
VOXON_API voxon_engine* voxon_open_with_options(const char* path, const char* options_json, char** error_json);

/*
 * Ejecuta una solicitud JSON y devuelve la respuesta JSON, que debe liberarse
 * con voxon_free. Solo devuelve NULL si no hay memoria.
 */
VOXON_API char* voxon_execute(voxon_engine* engine, const char* request_json);

/* Libera un texto devuelto por el motor. Acepta NULL. */
VOXON_API void voxon_free(char* text);

/* Cierra la base de datos y libera el motor. Acepta NULL. */
VOXON_API void voxon_close(voxon_engine* engine);

#ifdef __cplusplus
}
#endif

#endif /* VOXON_VOXON_H */
