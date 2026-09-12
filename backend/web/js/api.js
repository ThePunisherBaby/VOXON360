// Cliente de la API local (servidor Java en la caja principal).

const SESSION_KEY = 'voxon90.session';

/** Error con el mismo código estable que devuelve el motor. */
export class ApiError extends Error {
  constructor(code, message, status = 0) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
  }
}

export class ApiClient {
  #baseUrl;
  #fetch;
  #storage;
  #EventSource;
  #session = null;
  #unauthorizedListeners = new Set();

  /**
   * @param {object} [options]
   * @param {string} [options.baseUrl] servidor; vacío usa el mismo origen de la página
   * @param {Function} [options.fetch]
   * @param {Storage} [options.storage] dónde recordar la sesión (p. ej. sessionStorage)
   * @param {Function} [options.EventSource]
   */
  constructor({
    baseUrl = '',
    fetch: fetchImpl = globalThis.fetch?.bind(globalThis),
    storage = null,
    EventSource: EventSourceImpl = globalThis.EventSource,
  } = {}) {
    this.#baseUrl = baseUrl.replace(/\/$/, '');
    this.#fetch = fetchImpl;
    this.#storage = storage;
    this.#EventSource = EventSourceImpl;
    this.#session = this.#readStoredSession();
  }

  /** Empleado con sesión abierta, o null. */
  get user() {
    return this.#session?.user ?? null;
  }

  get isLoggedIn() {
    return this.#session !== null;
  }

  /** Avisa cuando la sesión deja de ser válida (PIN vencido, empleado desactivado). */
  onUnauthorized(listener) {
    this.#unauthorizedListeners.add(listener);
    return () => this.#unauthorizedListeners.delete(listener);
  }

  async health() {
    return this.#request('GET', '/api/health');
  }

  async login(pin) {
    const result = await this.#request('POST', '/api/login', { pin });
    this.#session = { token: result.token, user: result.user };
    this.#storage?.setItem(SESSION_KEY, JSON.stringify(this.#session));
    return result.user;
  }

  async logout() {
    try {
      if (this.#session) {
        await this.#request('POST', '/api/logout', {});
      }
    } catch {
      // Cerrar la sesión local aunque el servidor no responda.
    } finally {
      this.#clearSession();
    }
  }

  /** Llama un método del motor, p. ej. call('sales.complete', {...}). */
  async call(method, params = {}) {
    return this.#request('POST', '/api/call', { method, params });
  }

  /**
   * Escucha los cambios hechos desde cualquier equipo.
   * @param {(change: {method: string, userId: string|null, at: string}) => void} onChange
   * @returns {() => void} función para dejar de escuchar
   */
  subscribe(onChange) {
    if (!this.#session || !this.#EventSource) {
      return () => {};
    }
    const url = `${this.#baseUrl}/api/events?token=${encodeURIComponent(this.#session.token)}`;
    const source = new this.#EventSource(url);
    source.addEventListener('change', (event) => {
      try {
        onChange(JSON.parse(event.data));
      } catch {
        // Ignorar eventos mal formados.
      }
    });
    return () => source.close();
  }

  async #request(httpMethod, path, body) {
    if (!this.#fetch) {
      throw new ApiError('offline', 'Este navegador no puede conectarse al servidor');
    }
    const headers = { 'Content-Type': 'application/json' };
    if (this.#session) {
      headers.Authorization = `Bearer ${this.#session.token}`;
    }

    let response;
    try {
      response = await this.#fetch(`${this.#baseUrl}${path}`, {
        method: httpMethod,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ApiError('offline', 'No hay conexión con la caja principal. Revisa el WiFi del negocio.');
    }

    let payload = null;
    try {
      payload = await response.json();
    } catch {
      payload = null;
    }
    if (!payload || typeof payload !== 'object') {
      throw new ApiError('invalid_response', 'El servidor respondió algo inesperado', response.status);
    }
    if (payload.ok === false) {
      const { code = 'internal_error', message = 'Error desconocido' } = payload.error ?? {};
      if (response.status === 401 && path !== '/api/login') {
        this.#clearSession();
        this.#unauthorizedListeners.forEach((listener) => listener());
      }
      throw new ApiError(code, message, response.status);
    }
    return 'result' in payload ? payload.result : payload;
  }

  #readStoredSession() {
    try {
      const stored = this.#storage?.getItem(SESSION_KEY);
      const session = stored ? JSON.parse(stored) : null;
      return session?.token && session?.user ? session : null;
    } catch {
      return null;
    }
  }

  #clearSession() {
    this.#session = null;
    this.#storage?.removeItem(SESSION_KEY);
  }
}
